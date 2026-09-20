import java.lang.reflect.Array;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Fixed-target root helper for the L1.5 controlled experiment. */
public final class SingleSimSlot1PowerHelper {
    private static final int TARGET_SUB_ID = 11;
    private static final int TARGET_SLOT_ID = 1;
    private static final int TARGET_PHONE_ID = 1;
    private static final int TARGET_CARRIER_ID = 28;
    private static final int TARGET_MCC = 234;
    private static final int TARGET_MNC = 15;

    private static final int PROTECTED_SUB_ID = 1;
    private static final int PROTECTED_SLOT_ID = 0;
    private static final int PROTECTED_CARRIER_ID = 2237;
    private static final int PROTECTED_MCC = 460;
    private static final int PROTECTED_MNC = 11;

    private static final int CARD_POWER_DOWN = 0;
    private static final int CARD_POWER_UP = 1;
    private static final int RESULT_SUCCESS = 0;
    private static final int RESULT_ALREADY_IN_STATE = 1;
    private static final int SIM_STATE_ABSENT = 1;
    private static final int SIM_STATE_READY = 5;
    private static final long CALLBACK_TIMEOUT_SECONDS = 20;
    private static final long ARM_LIFETIME_MS = 15 * 60 * 1000L;

    private static final Path STATE_DIR = Paths.get("/data/local/tmp/voxi-single-sim");
    private static final Path ARM_FILE = STATE_DIR.resolve("rollback.armed");
    private static final Path WATCHDOG_READY_FILE = STATE_DIR.resolve("watchdog.ready");
    private static final Path POWER_DOWN_SENT_FILE = STATE_DIR.resolve("power_down.sent");
    private static final Path POWER_UP_CONFIRMED_FILE = STATE_DIR.resolve("power_up.confirmed");
    private static final Path BOOT_ID_FILE = Paths.get("/proc/sys/kernel/random/boot_id");

    private SingleSimSlot1PowerHelper() {}

    public static void main(String[] args) {
        if (args.length != 1 || !("DRY_RUN".equals(args[0])
                || "ARM_ROLLBACK".equals(args[0])
                || "CHECK_ROLLBACK".equals(args[0])
                || "POWER_DOWN".equals(args[0])
                || "POWER_UP".equals(args[0]))) {
            fail("accepted commands: DRY_RUN, ARM_ROLLBACK, CHECK_ROLLBACK, POWER_DOWN, POWER_UP", 2);
        }

        String command = args[0];
        log("event", "helper_start");
        log("command", command);
        log("fixedTarget", "slot=1 phoneId=1 subId=11");
        log("uid", String.valueOf(myUid()));
        log("selinux", readFirstLine(Paths.get("/proc/self/attr/current")));

        initializeFrameworkClient();
        Snapshot before = Snapshot.capture();
        before.print("before");

        try {
            if ("DRY_RUN".equals(command)) {
                require(before.strictGate(), "strict dual-SIM safety gate");
                log("wouldCall", "TelephonyManager.setSimPowerStateForSlot(1, CARD_POWER_DOWN/UP, Executor, Consumer)");
                Snapshot.capture().print("after");
                log("result", "DRY_RUN_ZERO_WRITE");
                return;
            }

            requireExecutionEnvironment();

            if ("ARM_ROLLBACK".equals(command)) {
                require(before.strictGate(), "strict dual-SIM safety gate");
                armRollback(before);
                Snapshot.capture().print("after");
                log("result", "ROLLBACK_ARMED");
                return;
            }

            if ("CHECK_ROLLBACK".equals(command)) {
                require(before.slot0Gate, "protected slot0 gate");
                require(validRollbackArm(), "valid rollback arm");
                Snapshot.capture().print("after");
                log("result", "ROLLBACK_ARM_VALID");
                return;
            }

            if ("POWER_DOWN".equals(command)) {
                require(before.strictGate(), "strict dual-SIM safety gate");
                require(validRollbackArm(), "valid rollback arm");
                require(Files.isRegularFile(WATCHDOG_READY_FILE), "independent watchdog ready marker");
                writeMarker(POWER_DOWN_SENT_FILE, "power_down_sent");
                invokePowerWithCallback(CARD_POWER_DOWN, "POWER_DOWN");
            } else {
                // After a real power-down either active subscription row may temporarily
                // disappear. A same-boot, short-lived pre-down arm record is the only
                // fallback to the live dual-SIM mapping.
                boolean armed = validRollbackArm();
                require(before.slot0Gate && (before.targetGate || armed),
                        "slot0 absent plus live target mapping or valid pre-down rollback arm");
                int callback = invokePowerWithCallback(CARD_POWER_UP, "POWER_UP");
                if (callback == RESULT_SUCCESS || callback == RESULT_ALREADY_IN_STATE) {
                    writeMarker(POWER_UP_CONFIRMED_FILE, "power_up_callback_accepted");
                }
            }

            Snapshot after = Snapshot.capture();
            after.print("after");
            log("result", "COMMAND_COMPLETED");
        } catch (HelperFailure failure) {
            Snapshot.capture().print("after");
            fail(failure.getMessage(), failure.code);
        }
    }

    private static int invokePowerWithCallback(int state, String label) {
        require(state == CARD_POWER_DOWN || state == CARD_POWER_UP, "fixed power state");
        CountDownLatch latch = new CountDownLatch(1);
        int[] callbackResult = new int[] { Integer.MIN_VALUE };
        Executor direct = command -> command.run();
        Consumer<Integer> callback = value -> {
            callbackResult[0] = value == null ? Integer.MIN_VALUE : value;
            log("callbackTime", now());
            log("callbackResult", String.valueOf(callbackResult[0]));
            latch.countDown();
        };

        try {
            Class<?> tmClass = Class.forName("android.telephony.TelephonyManager");
            Object tm = tmClass.getMethod("getDefault").invoke(null);
            require(tm != null, "TelephonyManager.getDefault");
            Method method = tmClass.getMethod("setSimPowerStateForSlot",
                    int.class, int.class, Executor.class, Consumer.class);
            log("requestTime", now());
            log("api", "TelephonyManager.setSimPowerStateForSlot");
            log("arguments", "slot=1 state=" + label);
            method.invoke(tm, TARGET_SLOT_ID, state, direct, callback);
            if (!latch.await(CALLBACK_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw new HelperFailure(label + " callback timeout", 31);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new HelperFailure(label + " interrupted", 32);
        } catch (HelperFailure failure) {
            throw failure;
        } catch (Throwable t) {
            throw new HelperFailure(label + " exception=" + describe(t), 33);
        }

        if (callbackResult[0] != RESULT_SUCCESS
                && callbackResult[0] != RESULT_ALREADY_IN_STATE) {
            throw new HelperFailure(label + " callback rejected result=" + callbackResult[0], 34);
        }
        return callbackResult[0];
    }

    private static void armRollback(Snapshot snapshot) {
        try {
            Files.createDirectories(STATE_DIR);
            Files.deleteIfExists(WATCHDOG_READY_FILE);
            Files.deleteIfExists(POWER_DOWN_SENT_FILE);
            Files.deleteIfExists(POWER_UP_CONFIRMED_FILE);
            long now = System.currentTimeMillis();
            List<String> lines = new ArrayList<>();
            lines.add("bootId=" + readFirstLine(BOOT_ID_FILE));
            lines.add("createdEpochMs=" + now);
            lines.add("expiresEpochMs=" + (now + ARM_LIFETIME_MS));
            lines.add("slot=1");
            lines.add("phoneId=1");
            lines.add("subId=11");
            lines.add("carrierId=28");
            lines.add("mccmnc=23415");
            lines.add("protectedSubId=1");
            lines.add("protectedSlot=0");
            lines.add("protectedMccMnc=46011");
            lines.add("strictGate=" + snapshot.strictGate());
            Files.write(ARM_FILE, lines, StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
            log("rollbackArm", ARM_FILE.toString());
            log("rollbackExpiresEpochMs", String.valueOf(now + ARM_LIFETIME_MS));
        } catch (Throwable t) {
            throw new HelperFailure("cannot arm rollback: " + describe(t), 20);
        }
    }

    private static boolean validRollbackArm() {
        try {
            if (!Files.isRegularFile(ARM_FILE)) return false;
            String text = new String(Files.readAllBytes(ARM_FILE), StandardCharsets.UTF_8);
            Long expires = longField(text, "expiresEpochMs");
            return hasLine(text, "bootId", readFirstLine(BOOT_ID_FILE))
                    && expires != null && System.currentTimeMillis() <= expires
                    && hasLine(text, "slot", "1")
                    && hasLine(text, "phoneId", "1")
                    && hasLine(text, "subId", "11")
                    && hasLine(text, "carrierId", "28")
                    && hasLine(text, "mccmnc", "23415")
                    && hasLine(text, "protectedSubId", "1")
                    && hasLine(text, "protectedSlot", "0")
                    && hasLine(text, "protectedMccMnc", "46011")
                    && hasLine(text, "strictGate", "true");
        } catch (Throwable t) {
            log("rollbackArmError", describe(t));
            return false;
        }
    }

    private static void writeMarker(Path path, String event) {
        try {
            Files.write(path, ("event=" + event + "\ntime=" + now() + "\n")
                    .getBytes(StandardCharsets.UTF_8), StandardOpenOption.CREATE,
                    StandardOpenOption.TRUNCATE_EXISTING);
        } catch (Throwable t) {
            throw new HelperFailure("cannot write marker " + path + ": " + describe(t), 21);
        }
    }

    private static void requireExecutionEnvironment() {
        require("1".equals(System.getenv("LAB_MODE")), "LAB_MODE=1");
        require("YES".equals(System.getenv("LAB_EXECUTE")), "LAB_EXECUTE=YES");
        require(myUid() == 0, "UID 0");
    }

    private static void initializeFrameworkClient() {
        try {
            Class<?> sm = Class.forName("android.os.TelephonyServiceManager");
            Object manager = sm.getConstructor().newInstance();
            Class.forName("android.telephony.TelephonyFrameworkInitializer")
                    .getMethod("setTelephonyServiceManager", sm).invoke(null, manager);
        } catch (Throwable t) {
            log("frameworkInitNote", describe(t));
        }
    }

    private static final class Snapshot {
        int uid;
        Integer targetPhoneId;
        Integer targetSlotId;
        boolean targetActive;
        boolean targetUiccEnabled;
        Integer targetCarrierId;
        Integer targetMcc;
        Integer targetMnc;
        Integer targetRowSlot;
        Integer targetSimState;
        boolean protectedActive;
        Integer protectedCarrierId;
        Integer protectedMcc;
        Integer protectedMnc;
        Integer protectedRowSlot;
        Integer protectedSimState;
        Integer imsState;
        Integer imsTransport;
        Boolean voiceIwlanAvailable;
        Boolean wfcAvailable;
        boolean targetGate;
        boolean slot0Gate;
        final List<String> errors = new ArrayList<>();

        static Snapshot capture() {
            Snapshot s = new Snapshot();
            s.uid = myUid();
            try {
                Object binder = service("isub");
                Object isub = asInterface("com.android.internal.telephony.ISub$Stub", binder);
                s.targetPhoneId = (Integer) invoke(isub, "getPhoneId",
                        new Class<?>[] { int.class }, TARGET_SUB_ID);
                s.targetSlotId = (Integer) invoke(isub, "getSlotIndex",
                        new Class<?>[] { int.class }, TARGET_SUB_ID);
                int[] slot1 = intArray(invoke(isub, "getSubId",
                        new Class<?>[] { int.class }, TARGET_SLOT_ID));
                int[] slot0 = intArray(invoke(isub, "getSubId",
                        new Class<?>[] { int.class }, PROTECTED_SLOT_ID));
                List<String> rows = activeRows(isub);
                String target = rowFor(rows, TARGET_SUB_ID);
                String protectedRow = rowFor(rows, PROTECTED_SUB_ID);
                s.targetActive = target != null;
                s.targetUiccEnabled = boolField(target, "areUiccApplicationsEnabled", false);
                s.targetCarrierId = intField(target, "carrierId");
                s.targetMcc = intField(target, "mcc");
                s.targetMnc = intField(target, "mnc");
                s.targetRowSlot = intField(target, "simSlotIndex");
                s.protectedActive = protectedRow != null;
                s.protectedCarrierId = intField(protectedRow, "carrierId");
                s.protectedMcc = intField(protectedRow, "mcc");
                s.protectedMnc = intField(protectedRow, "mnc");
                s.protectedRowSlot = intField(protectedRow, "simSlotIndex");
                s.targetGate = s.targetActive && eq(s.targetPhoneId, TARGET_PHONE_ID)
                        && eq(s.targetSlotId, TARGET_SLOT_ID)
                        && contains(slot1, TARGET_SUB_ID) && !contains(slot0, TARGET_SUB_ID)
                        && eq(s.targetRowSlot, TARGET_SLOT_ID)
                        && eq(s.targetCarrierId, TARGET_CARRIER_ID)
                        && eq(s.targetMcc, TARGET_MCC) && eq(s.targetMnc, TARGET_MNC);
                s.slot0Gate = !s.protectedActive && !contains(slot0, PROTECTED_SUB_ID)
                        && !contains(slot0, TARGET_SUB_ID);
            } catch (Throwable t) {
                s.errors.add("ISub=" + describe(t));
            }

            try {
                Class<?> tmClass = Class.forName("android.telephony.TelephonyManager");
                Object tm = tmClass.getMethod("getDefault").invoke(null);
                s.targetSimState = (Integer) tmClass.getMethod("getSimState", int.class)
                        .invoke(tm, TARGET_SLOT_ID);
                s.protectedSimState = (Integer) tmClass.getMethod("getSimState", int.class)
                        .invoke(tm, PROTECTED_SLOT_ID);
            } catch (Throwable t) {
                s.errors.add("TelephonyManager.getSimState=" + describe(t));
            }
            s.targetGate = s.targetGate && eq(s.targetSimState, SIM_STATE_READY);
            s.slot0Gate = s.slot0Gate && eq(s.protectedSimState, SIM_STATE_ABSENT);

            try {
                Class<?> cls = Class.forName("android.telephony.ims.ImsMmTelManager");
                Object ims = cls.getMethod("createForSubscriptionId", int.class)
                        .invoke(null, TARGET_SUB_ID);
                s.imsState = queryAsyncInt(ims, "getRegistrationState");
                s.imsTransport = queryAsyncInt(ims, "getRegistrationTransportType");
                s.voiceIwlanAvailable = (Boolean) cls.getMethod("isAvailable", int.class, int.class)
                        .invoke(ims, 1, 1);
            } catch (Throwable t) {
                s.errors.add("ImsMmTelManager=" + describe(t));
            }

            try {
                Object phone = asInterface("com.android.internal.telephony.ITelephony$Stub", service("phone"));
                s.wfcAvailable = (Boolean) invoke(phone, "isWifiCallingAvailable",
                        new Class<?>[] { int.class }, TARGET_SUB_ID);
            } catch (Throwable t) {
                s.errors.add("WFC=" + describe(t));
            }
            return s;
        }

        boolean strictGate() {
            return uid == 0 && targetGate && slot0Gate && targetUiccEnabled;
        }

        void print(String prefix) {
            log(prefix + ".timestamp", now());
            log(prefix + ".target", "subId=11 slot=" + targetSlotId + " phoneId=" + targetPhoneId
                    + " carrierId=" + targetCarrierId + " mcc=" + targetMcc + " mnc=" + targetMnc
                    + " active=" + targetActive + " uiccEnabled=" + targetUiccEnabled
                    + " simState=" + targetSimState + " mappingGate=" + targetGate);
            log(prefix + ".slot0", "subId=1 slot=" + protectedRowSlot
                    + " carrierId=" + protectedCarrierId + " mcc=" + protectedMcc
                    + " mnc=" + protectedMnc + " active=" + protectedActive
                    + " simState=" + protectedSimState + " mappingGate=" + slot0Gate);
            log(prefix + ".ims", "registrationState=" + imsState
                    + " transport=" + imsTransport + " voiceIwlanAvailable=" + voiceIwlanAvailable);
            log(prefix + ".wfc", "available=" + wfcAvailable);
            log(prefix + ".strictGate", String.valueOf(strictGate()));
            if (!errors.isEmpty()) log(prefix + ".errors", String.join(" | ", errors));
        }
    }

    private static Integer queryAsyncInt(Object target, String methodName) throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        Integer[] result = new Integer[1];
        Executor direct = command -> command.run();
        Consumer<Integer> callback = value -> { result[0] = value; latch.countDown(); };
        target.getClass().getMethod(methodName, Executor.class, Consumer.class)
                .invoke(target, direct, callback);
        if (!latch.await(10, TimeUnit.SECONDS)) throw new IllegalStateException(methodName + " timeout");
        return result[0];
    }

    private static Object service(String name) throws Exception {
        return Class.forName("android.os.ServiceManager").getMethod("getService", String.class)
                .invoke(null, name);
    }

    private static Object asInterface(String stubName, Object binder) throws Exception {
        require(binder != null, stubName + " binder");
        return Class.forName(stubName).getMethod("asInterface", Class.forName("android.os.IBinder"))
                .invoke(null, binder);
    }

    private static Object invoke(Object target, String name, Class<?>[] types, Object... args)
            throws Exception {
        return target.getClass().getMethod(name, types).invoke(target, args);
    }

    private static List<String> activeRows(Object isub) throws Exception {
        Object list = invoke(isub, "getActiveSubscriptionInfoList",
                new Class<?>[] { String.class, String.class }, "com.android.shell", null);
        List<String> rows = new ArrayList<>();
        if (list instanceof Iterable) {
            for (Object item : (Iterable<?>) list) rows.add(String.valueOf(item));
        }
        return rows;
    }

    private static String rowFor(List<String> rows, int subId) {
        Pattern p = Pattern.compile("(?s).*\\b(?:id|subId)\\s*=\\s*" + subId + "\\b.*");
        for (String row : rows) if (p.matcher(row).matches()) return row;
        return null;
    }

    private static Integer intField(String row, String name) {
        if (row == null) return null;
        Matcher m = Pattern.compile("\\b" + Pattern.quote(name) + "\\s*=\\s*(-?\\d+)").matcher(row);
        return m.find() ? Integer.valueOf(m.group(1)) : null;
    }

    private static boolean boolField(String row, String name, boolean fallback) {
        if (row == null) return fallback;
        Matcher m = Pattern.compile("\\b" + Pattern.quote(name) + "\\s*=\\s*(true|false)").matcher(row);
        return m.find() ? Boolean.parseBoolean(m.group(1)) : fallback;
    }

    private static int[] intArray(Object value) {
        if (value == null) return new int[0];
        int[] out = new int[Array.getLength(value)];
        for (int i = 0; i < out.length; i++) out[i] = (Integer) Array.get(value, i);
        return out;
    }

    private static boolean contains(int[] values, int target) {
        for (int value : values) if (value == target) return true;
        return false;
    }

    private static boolean eq(Integer value, int expected) {
        return value != null && value == expected;
    }

    private static boolean hasLine(String text, String key, String value) {
        return Pattern.compile("(?m)^" + Pattern.quote(key) + "=" + Pattern.quote(value) + "$")
                .matcher(text).find();
    }

    private static Long longField(String text, String key) {
        Matcher m = Pattern.compile("(?m)^" + Pattern.quote(key) + "=(\\d+)$").matcher(text);
        return m.find() ? Long.valueOf(m.group(1)) : null;
    }

    private static int myUid() {
        try {
            return (Integer) Class.forName("android.os.Process").getMethod("myUid").invoke(null);
        } catch (Throwable t) {
            return -1;
        }
    }

    private static String readFirstLine(Path path) {
        try {
            List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
            return lines.isEmpty() ? "" : lines.get(0).trim();
        } catch (Throwable t) {
            return "UNAVAILABLE:" + describe(t);
        }
    }

    private static String describe(Throwable throwable) {
        Throwable t = throwable;
        while (t instanceof InvocationTargetException
                && ((InvocationTargetException) t).getTargetException() != null) {
            t = ((InvocationTargetException) t).getTargetException();
        }
        return t.getClass().getName() + ":" + String.valueOf(t.getMessage())
                .replace('\n', ' ').replace('\r', ' ');
    }

    private static String now() {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
        f.setTimeZone(TimeZone.getDefault());
        return f.format(new Date());
    }

    private static void log(String key, String value) {
        System.out.println(key + "=" + value);
    }

    private static void require(boolean condition, String label) {
        if (!condition) throw new HelperFailure("gate failed: " + label, 10);
    }

    private static void fail(String message, int code) {
        log("failureTime", now());
        log("ERROR", message);
        System.exit(code);
    }

    private static final class HelperFailure extends RuntimeException {
        final int code;

        HelperFailure(String message, int code) {
            super(message);
            this.code = code;
        }
    }
}
