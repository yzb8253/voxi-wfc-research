import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

public final class Phase5ImsProbe {
    private static final int TARGET_SUB_ID = 11;
    private static final int CAPABILITY_TYPE_VOICE = 1;
    private static final int REGISTRATION_TECH_IWLAN = 1;
    private static final long CALLBACK_TIMEOUT_SECONDS = 15;

    private Phase5ImsProbe() {
    }

    public static void main(String[] args) {
        if (args.length != 1 || !"read-only".equals(args[0])) {
            System.out.println("HARD LOCK: only the read-only mode is accepted.");
            System.exit(2);
        }

        System.out.println("=== PHASE 5B IMS PROBE START ===");
        System.out.println("mode: read-only");
        System.out.println("TARGET_SUB_ID: " + TARGET_SUB_ID);
        printIdentity();
        initializeFrameworkClient();

        Throwable firstFailure = null;
        Object manager = null;
        try {
            Class<?> managerClass = Class.forName("android.telephony.ims.ImsMmTelManager");
            printApi(managerClass, "createForSubscriptionId", int.class);
            printApi(managerClass, "getRegistrationState", Executor.class, Consumer.class);
            printApi(managerClass, "getRegistrationTransportType", Executor.class, Consumer.class);
            printApi(managerClass, "isAvailable", int.class, int.class);
            printApi(managerClass, "isCapable", int.class, int.class);
            manager = managerClass.getMethod("createForSubscriptionId", int.class)
                    .invoke(null, TARGET_SUB_ID);
            System.out.println("ImsMmTelManager instance: " + passFail(manager != null));
        } catch (Throwable t) {
            firstFailure = unwrap(t);
            printFailure("ImsMmTelManager setup", t);
        }

        Integer registrationState = null;
        Integer registrationTransport = null;
        Boolean voiceAvailable = null;
        Boolean voiceCapable = null;

        if (manager != null) {
            try {
                registrationState = queryAsyncInt(manager, "getRegistrationState");
                System.out.println("getRegistrationState raw: " + value(registrationState));
                System.out.println("getRegistrationState result: " + registrationStateName(registrationState));
            } catch (Throwable t) {
                if (firstFailure == null) firstFailure = unwrap(t);
                printFailure("getRegistrationState", t);
            }

            try {
                registrationTransport = queryAsyncInt(manager, "getRegistrationTransportType");
                System.out.println("getRegistrationTransportType raw: " + value(registrationTransport));
                System.out.println("getRegistrationTransportType result: " + transportName(registrationTransport));
            } catch (Throwable t) {
                if (firstFailure == null) firstFailure = unwrap(t);
                printFailure("getRegistrationTransportType", t);
            }

            try {
                Method method = manager.getClass().getMethod("isAvailable", int.class, int.class);
                voiceAvailable = (Boolean) method.invoke(manager, CAPABILITY_TYPE_VOICE, REGISTRATION_TECH_IWLAN);
                System.out.println("isAvailable(VOICE=1, IWLAN=1): " + voiceAvailable);
            } catch (Throwable t) {
                if (firstFailure == null) firstFailure = unwrap(t);
                printFailure("isAvailable(VOICE, IWLAN)", t);
            }

            try {
                Method method = manager.getClass().getMethod("isCapable", int.class, int.class);
                voiceCapable = (Boolean) method.invoke(manager, CAPABILITY_TYPE_VOICE, REGISTRATION_TECH_IWLAN);
                System.out.println("isCapable(VOICE=1, IWLAN=1): " + voiceCapable);
            } catch (Throwable t) {
                if (firstFailure == null) firstFailure = unwrap(t);
                printFailure("isCapable(VOICE, IWLAN)", t);
            }

            invokeBooleanRead(manager, "isVoWiFiSettingEnabled");
        }

        Boolean wifiCallingAvailable = queryTelephonyManager();

        boolean registered = registrationState != null && registrationState == 2;
        boolean wlan = registrationTransport != null && registrationTransport == 2;
        boolean directGolden = registered && wlan;
        boolean strongGolden = directGolden && Boolean.TRUE.equals(voiceAvailable);

        System.out.println("=== PHASE 5B DIRECT RESULT ===");
        System.out.println("registrationState: " + value(registrationState) + " / " + registrationStateName(registrationState));
        System.out.println("registrationTransport: " + value(registrationTransport) + " / " + transportName(registrationTransport));
        System.out.println("MMTEL voice over IWLAN available: " + value(voiceAvailable));
        System.out.println("MMTEL voice over IWLAN capable: " + value(voiceCapable));
        System.out.println("TelephonyManager WFC available: " + value(wifiCallingAvailable));
        System.out.println("DIRECT IMS/WFC GOLDEN: " + (strongGolden ? "STRONG YES" : (directGolden ? "YES" : "NO")));
        System.out.println("Security/Binder failure: " + (firstFailure == null ? "NONE" : firstFailure.getClass().getName() + ": " + safeMessage(firstFailure)));
        System.out.println("=== PHASE 5B IMS PROBE END ===");
    }

    private static Integer queryAsyncInt(Object target, String methodName) throws Exception {
        final CountDownLatch latch = new CountDownLatch(1);
        final Integer[] result = new Integer[1];
        Executor directExecutor = new Executor() {
            @Override
            public void execute(Runnable command) {
                command.run();
            }
        };
        Consumer<Integer> consumer = new Consumer<Integer>() {
            @Override
            public void accept(Integer value) {
                result[0] = value;
                latch.countDown();
            }
        };
        Method method = target.getClass().getMethod(methodName, Executor.class, Consumer.class);
        method.invoke(target, directExecutor, consumer);
        if (!latch.await(CALLBACK_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw new IllegalStateException(methodName + " callback timed out after "
                    + CALLBACK_TIMEOUT_SECONDS + " seconds");
        }
        return result[0];
    }

    private static Boolean queryTelephonyManager() {
        try {
            Class<?> tmClass = Class.forName("android.telephony.TelephonyManager");
            printApi(tmClass, "isWifiCallingAvailable");
            Object binder = Class.forName("android.os.ServiceManager")
                    .getMethod("getService", String.class).invoke(null, "phone");
            Class<?> iBinderClass = Class.forName("android.os.IBinder");
            Object telephony = Class.forName("com.android.internal.telephony.ITelephony$Stub")
                    .getMethod("asInterface", iBinderClass).invoke(null, binder);
            Object out = Class.forName("com.android.internal.telephony.ITelephony")
                    .getMethod("isWifiCallingAvailable", int.class)
                    .invoke(telephony, TARGET_SUB_ID);
            System.out.println("TelephonyManager WFC backend ITelephony.isWifiCallingAvailable(11): " + out);
            return (Boolean) out;
        } catch (Throwable t) {
            printFailure("TelephonyManager.isWifiCallingAvailable", t);
            return null;
        }
    }

    private static void initializeFrameworkClient() {
        try {
            Class<?> serviceManagerClass = Class.forName("android.os.TelephonyServiceManager");
            Object serviceManager = serviceManagerClass.getConstructor().newInstance();
            Class<?> initializerClass = Class.forName("android.telephony.TelephonyFrameworkInitializer");
            initializerClass.getMethod("setTelephonyServiceManager", serviceManagerClass)
                    .invoke(null, serviceManager);
            System.out.println("TelephonyServiceManager client initialized: PASS");
        } catch (Throwable t) {
            printFailure("TelephonyServiceManager client initialization", t);
        }

    }

    private static void invokeBooleanRead(Object target, String methodName) {
        try {
            Method method = target.getClass().getMethod(methodName);
            Object out = method.invoke(target);
            System.out.println(methodName + "(): " + out);
        } catch (Throwable t) {
            printFailure(methodName, t);
        }
    }

    private static void printApi(Class<?> owner, String name, Class<?>... params) {
        try {
            Method method = owner.getMethod(name, params);
            System.out.println("API present: " + method.toGenericString());
        } catch (Throwable t) {
            System.out.println("API missing: " + owner.getName() + "." + name + " - "
                    + t.getClass().getName() + ": " + safeMessage(t));
        }
    }

    private static void printIdentity() {
        try {
            Class<?> process = Class.forName("android.os.Process");
            System.out.println("Process.myUid(): " + process.getMethod("myUid").invoke(null));
            System.out.println("Process.myPid(): " + process.getMethod("myPid").invoke(null));
        } catch (Throwable t) {
            printFailure("Process identity", t);
        }
        System.out.println("SELinux context: " + readFirstLine("/proc/self/attr/current"));
    }

    private static String registrationStateName(Integer value) {
        if (value == null) return "UNKNOWN/UNAVAILABLE";
        if (value == 0) return "NOT_REGISTERED";
        if (value == 1) return "REGISTERING";
        if (value == 2) return "REGISTERED";
        return "UNKNOWN(" + value + ")";
    }

    private static String transportName(Integer value) {
        if (value == null) return "UNKNOWN/UNAVAILABLE";
        if (value == 1) return "WWAN";
        if (value == 2) return "WLAN";
        if (value == -1) return "INVALID";
        return "UNKNOWN(" + value + ")";
    }

    private static void printFailure(String label, Throwable throwable) {
        Throwable root = unwrap(throwable);
        System.out.println(label + " exception: " + root.getClass().getName() + ": " + safeMessage(root));
    }

    private static Throwable unwrap(Throwable throwable) {
        Throwable current = throwable;
        while (current instanceof InvocationTargetException
                && ((InvocationTargetException) current).getTargetException() != null) {
            current = ((InvocationTargetException) current).getTargetException();
        }
        return current;
    }

    private static String readFirstLine(String path) {
        try {
            List<String> lines = Files.readAllLines(Paths.get(path));
            return lines.isEmpty() ? "" : lines.get(0);
        } catch (Throwable t) {
            return "UNAVAILABLE: " + t.getClass().getName() + ": " + safeMessage(t);
        }
    }

    private static String value(Object value) {
        return value == null ? "UNAVAILABLE" : String.valueOf(value);
    }

    private static String passFail(boolean ok) {
        return ok ? "PASS" : "FAIL";
    }

    private static String safeMessage(Throwable t) {
        String message = t.getMessage();
        return message == null ? "" : message.replace('\n', ' ').replace('\r', ' ');
    }
}
