import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Array;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
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

public final class WfcStateProbe {
    private static final int TARGET_SUB_ID = 11;
    private static final int TARGET_SLOT_ID = 1;
    private static final int TARGET_PHONE_ID = 1;
    private static final int TARGET_CARRIER_ID = 28;
    private static final int TARGET_MCC = 234;
    private static final int TARGET_MNC = 15;
    private static final int PROTECTED_SUB_ID = 1;
    private static final int PROTECTED_SLOT_ID = 0;
    private static final int PROTECTED_MCC = 460;
    private static final int PROTECTED_MNC = 11;
    private static final int CAPABILITY_TYPE_VOICE = 1;
    private static final int REGISTRATION_TECH_IWLAN = 1;
    private static final long CALLBACK_TIMEOUT_SECONDS = 10;
    private static final List<String> errors = new ArrayList<>();

    private WfcStateProbe() {
    }

    public static void main(String[] args) {
        if (args.length != 1 || !"read-only-json".equals(args[0])) {
            System.err.println("HARD LOCK: only read-only-json is accepted.");
            System.exit(2);
        }

        initializeFrameworkClient();

        String isubText = runReadOnly("dumpsys isub");
        String registryText = runReadOnly("dumpsys telephony.registry");
        String phoneText = runReadOnly("dumpsys phone");
        String connectivityText = runReadOnly("dumpsys connectivity");

        String targetRow = activeSubscriptionRow(isubText, TARGET_SUB_ID);
        String protectedRow = activeSubscriptionRow(isubText, PROTECTED_SUB_ID);

        Integer phoneId = null;
        Integer slotId = null;
        Integer registrationState = null;
        Integer registrationTransport = null;
        Boolean voiceAvailable = null;
        Boolean voiceCapable = null;
        Boolean settingEnabled = null;
        Boolean wifiCallingAvailable = null;

        try {
            Object binder = getService("isub");
            Object isub = asInterface("com.android.internal.telephony.ISub$Stub", binder);
            phoneId = invokeInt(isub, "getPhoneId", TARGET_SUB_ID);
            slotId = invokeInt(isub, "getSlotIndex", TARGET_SUB_ID);
        } catch (Throwable t) {
            addError("ISub mapping", t);
        }

        try {
            Class<?> managerClass = Class.forName("android.telephony.ims.ImsMmTelManager");
            Object manager = managerClass.getMethod("createForSubscriptionId", int.class)
                    .invoke(null, TARGET_SUB_ID);
            registrationState = queryAsyncInt(manager, "getRegistrationState");
            registrationTransport = queryAsyncInt(manager, "getRegistrationTransportType");
            voiceAvailable = (Boolean) managerClass.getMethod("isAvailable", int.class, int.class)
                    .invoke(manager, CAPABILITY_TYPE_VOICE, REGISTRATION_TECH_IWLAN);
            voiceCapable = (Boolean) managerClass.getMethod("isCapable", int.class, int.class)
                    .invoke(manager, CAPABILITY_TYPE_VOICE, REGISTRATION_TECH_IWLAN);
            settingEnabled = (Boolean) managerClass.getMethod("isVoWiFiSettingEnabled").invoke(manager);
        } catch (Throwable t) {
            addError("ImsMmTelManager", t);
        }

        try {
            Object phoneBinder = getService("phone");
            Object telephony = asInterface("com.android.internal.telephony.ITelephony$Stub", phoneBinder);
            wifiCallingAvailable = (Boolean) Class.forName("com.android.internal.telephony.ITelephony")
                    .getMethod("isWifiCallingAvailable", int.class).invoke(telephony, TARGET_SUB_ID);
        } catch (Throwable t) {
            addError("ITelephony WFC", t);
        }

        boolean active = targetRow != null;
        Boolean uiccEnabled = targetRow == null ? null : boolField(targetRow, "areUiccApplicationsEnabled");
        Integer carrierId = targetRow == null ? null : intField(targetRow, "carrierId");
        Integer mcc = targetRow == null ? null : intField(targetRow, "mcc");
        Integer mnc = targetRow == null ? null : intField(targetRow, "mnc");
        Integer rowSlot = targetRow == null ? null : intField(targetRow, "simSlotIndex");

        boolean protectedActive = protectedRow != null;
        Integer protectedSlot = protectedRow == null ? null : intField(protectedRow, "simSlotIndex");
        Integer protectedMcc = protectedRow == null ? null : intField(protectedRow, "mcc");
        Integer protectedMnc = protectedRow == null ? null : intField(protectedRow, "mnc");

        Integer defaultDataSubId = regexInt(isubText, "defaultDataSubId=(-?\\d+)");
        Integer activeDataSubId = regexInt(registryText, "mActiveDataSubId=(-?\\d+)");

        String phone1State = phoneStateLine(registryText, TARGET_PHONE_ID);
        String rilDataTechnology = regexGroup(phone1State, "getRilDataRadioTechnology=\\d+\\(([^)]+)\\)");
        String psWlanState = regexGroup(phone1State,
                "domain=PS transportType=WLAN registrationState=([A-Z_]+)");
        String accessNetworkTechnology = regexGroup(phone1State,
                "domain=PS transportType=WLAN[^}]*accessNetworkTechnology=([A-Z0-9_]+)");
        Boolean iwlanPreferred = regexBoolean(phone1State, "mIsIwlanPreferred=(true|false)");

        String featureState = regexGroup(phoneText,
                "Listener=\\{slotId=1, subId=11, state=([A-Z_]+)");

        String imsAgentLine = firstLineContainingAll(connectivityText,
                "MOBILE[IWLAN] CONNECTED extra: ims", "mSubId = 11");
        boolean imsAgent = imsAgentLine != null;
        Integer imsNetworkId = imsAgentLine == null ? null : regexInt(imsAgentLine, "network\\{(\\d+)\\}");
        boolean imsRequestActive = containsLineWithAll(connectivityText,
                "NetworkRequest", "Capabilities: IMS", "mSubId = 11");
        boolean qtiCneRequestActive = containsLineWithAll(connectivityText,
                "activeRequest:", "com.qualcomm.qti.cne", "Capabilities: IMS", "mSubId = 11");
        Integer qtiCneRequestId = regexInt(firstLineContainingAll(connectivityText,
                "activeRequest:", "com.qualcomm.qti.cne", "mSubId = 11"), "activeRequest: (\\d+)");

        String keepaliveLine = firstLineContainingAll(connectivityText, "KeepaliveInfo", ":4500", "STARTED");
        boolean udp4500Keepalive = keepaliveLine != null;
        Integer keepaliveInterval = keepaliveLine == null ? null : regexInt(keepaliveLine, "interval=(\\d+)");

        boolean targetGate = active
                && eq(phoneId, TARGET_PHONE_ID)
                && eq(slotId, TARGET_SLOT_ID)
                && eq(rowSlot, TARGET_SLOT_ID)
                && eq(carrierId, TARGET_CARRIER_ID)
                && eq(mcc, TARGET_MCC)
                && eq(mnc, TARGET_MNC);
        boolean slot0Gate = protectedActive
                && eq(protectedSlot, PROTECTED_SLOT_ID)
                && eq(protectedMcc, PROTECTED_MCC)
                && eq(protectedMnc, PROTECTED_MNC)
                && !eq(protectedSlot, TARGET_SLOT_ID);
        boolean safetyGate = targetGate && slot0Gate;

        boolean goldenStrong = eq(registrationState, 2)
                && eq(registrationTransport, 2)
                && Boolean.TRUE.equals(voiceAvailable)
                && Boolean.TRUE.equals(wifiCallingAvailable)
                && imsAgent;
        String failureClass = classify(active, targetGate, registrationState,
                registrationTransport, voiceAvailable, wifiCallingAvailable,
                imsAgent, qtiCneRequestActive, udp4500Keepalive, goldenStrong);

        StringBuilder j = new StringBuilder(4096);
        j.append('{');
        field(j, "timestamp", now());
        field(j, "uid", myUid());
        field(j, "selinuxContext", readFirstLine("/proc/self/attr/current").replace("\u0000", ""));
        objectStart(j, "target");
        field(j, "subId", TARGET_SUB_ID); field(j, "slotId", slotId); field(j, "phoneId", phoneId);
        field(j, "carrierId", carrierId); field(j, "mcc", mcc); field(j, "mnc", mnc);
        field(j, "mappingGate", targetGate); objectEnd(j);
        objectStart(j, "protectedSlot0");
        field(j, "subId", PROTECTED_SUB_ID); field(j, "slotId", protectedSlot);
        field(j, "mcc", protectedMcc); field(j, "mnc", protectedMnc);
        field(j, "active", protectedActive); field(j, "mappingGate", slot0Gate); objectEnd(j);
        objectStart(j, "subscription");
        field(j, "active", active); field(j, "areUiccApplicationsEnabled", uiccEnabled);
        field(j, "defaultDataSubId", defaultDataSubId); field(j, "activeDataSubId", activeDataSubId); objectEnd(j);
        objectStart(j, "iwlan");
        field(j, "rilDataTechnology", rilDataTechnology); field(j, "psWlanState", psWlanState);
        field(j, "accessNetworkTechnology", accessNetworkTechnology); field(j, "iwlanPreferred", iwlanPreferred); objectEnd(j);
        objectStart(j, "ims");
        field(j, "registrationStateRaw", registrationState); field(j, "registrationStateName", stateName(registrationState));
        field(j, "registrationTransportRaw", registrationTransport); field(j, "registrationTransportName", transportName(registrationTransport)); objectEnd(j);
        objectStart(j, "mmtel");
        field(j, "voiceIwlanAvailable", voiceAvailable); field(j, "voiceIwlanCapable", voiceCapable);
        field(j, "featureState", featureState); objectEnd(j);
        objectStart(j, "wfc");
        field(j, "settingEnabled", settingEnabled); field(j, "wifiCallingAvailable", wifiCallingAvailable); objectEnd(j);
        objectStart(j, "connectivity");
        field(j, "imsIwlanNetworkAgent", imsAgent); field(j, "imsNetworkId", imsNetworkId);
        field(j, "imsRequestActive", imsRequestActive); field(j, "qtiCneRequestActive", qtiCneRequestActive);
        field(j, "qtiCneRequestId", qtiCneRequestId); objectEnd(j);
        objectStart(j, "epdg");
        field(j, "udp4500Keepalive", udp4500Keepalive); field(j, "keepaliveInterval", keepaliveInterval); objectEnd(j);
        field(j, "safetyGate", safetyGate);
        field(j, "goldenStrong", goldenStrong);
        field(j, "failureClass", failureClass);
        array(j, "errors", errors);
        trimComma(j);
        j.append('}');
        System.out.println(j.toString());
    }

    private static String classify(boolean active, boolean targetGate, Integer state,
            Integer transport, Boolean voice, Boolean wfc, boolean agent,
            boolean qtiRequest, boolean keepalive, boolean golden) {
        if (golden) return "F0";
        if (!active || !targetGate) return "F8";
        if (eq(state, 0)) return "F1";
        if (eq(state, 1)) return "F2";
        if (eq(state, 2) && !eq(transport, 2)) return "F3";
        if (eq(state, 2) && eq(transport, 2) && Boolean.FALSE.equals(voice)) return "F4";
        if (eq(state, 2) && eq(transport, 2) && Boolean.FALSE.equals(wfc)) return "F5";
        if (!agent || !qtiRequest) return "F6";
        if (!keepalive) return "F7";
        return "F9";
    }

    private static void initializeFrameworkClient() {
        try {
            Class<?> sm = Class.forName("android.os.TelephonyServiceManager");
            Object manager = sm.getConstructor().newInstance();
            Class.forName("android.telephony.TelephonyFrameworkInitializer")
                    .getMethod("setTelephonyServiceManager", sm).invoke(null, manager);
        } catch (Throwable t) {
            addError("TelephonyFrameworkInitializer", t);
        }
    }

    private static Integer queryAsyncInt(Object target, String methodName) throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        Integer[] result = new Integer[1];
        Executor executor = command -> command.run();
        Consumer<Integer> consumer = value -> { result[0] = value; latch.countDown(); };
        target.getClass().getMethod(methodName, Executor.class, Consumer.class)
                .invoke(target, executor, consumer);
        if (!latch.await(CALLBACK_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw new IllegalStateException(methodName + " callback timeout");
        }
        return result[0];
    }

    private static Object getService(String name) throws Exception {
        return Class.forName("android.os.ServiceManager").getMethod("getService", String.class)
                .invoke(null, name);
    }

    private static Object asInterface(String stubName, Object binder) throws Exception {
        return Class.forName(stubName).getMethod("asInterface", Class.forName("android.os.IBinder"))
                .invoke(null, binder);
    }

    private static Integer invokeInt(Object target, String name, int arg) throws Exception {
        Object value = target.getClass().getMethod(name, int.class).invoke(target, arg);
        return value == null ? null : (Integer) value;
    }

    private static String runReadOnly(String command) {
        StringBuilder out = new StringBuilder();
        try {
            Process p = Runtime.getRuntime().exec(new String[] { "/system/bin/sh", "-c", command });
            try (BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = br.readLine()) != null) out.append(line).append('\n');
            }
            int rc = p.waitFor();
            if (rc != 0) errors.add(command + " exit=" + rc);
        } catch (Throwable t) {
            addError(command, t);
        }
        return out.toString();
    }

    private static String activeSubscriptionRow(String text, int subId) {
        int start = text.indexOf("ActiveSubInfoList:");
        if (start < 0) return null;
        int end = text.indexOf("AllSubInfoList:", start);
        String block = end < 0 ? text.substring(start) : text.substring(start, end);
        for (String line : block.split("\\R")) {
            if (Pattern.compile("\\bid\\s*=\\s*" + subId + "\\b").matcher(line).find()) return line.trim();
        }
        return null;
    }

    private static String phoneStateLine(String text, int phoneId) {
        int start = text.indexOf("Phone Id=" + phoneId);
        if (start < 0) return "";
        int next = text.indexOf("Phone Id=" + (phoneId + 1), start + 1);
        String block = next < 0 ? text.substring(start) : text.substring(start, next);
        return firstLineContainingAll(block, "mServiceState=");
    }

    private static Integer intField(String row, String name) {
        return regexInt(row, "\\b" + Pattern.quote(name) + "\\s*=\\s*(-?\\d+)");
    }

    private static Boolean boolField(String row, String name) {
        return regexBoolean(row, "\\b" + Pattern.quote(name) + "\\s*=\\s*(true|false)");
    }

    private static Integer regexInt(String text, String regex) {
        if (text == null) return null;
        Matcher m = Pattern.compile(regex).matcher(text);
        return m.find() ? Integer.valueOf(m.group(1)) : null;
    }

    private static String regexGroup(String text, String regex) {
        if (text == null) return null;
        Matcher m = Pattern.compile(regex).matcher(text);
        return m.find() ? m.group(1) : null;
    }

    private static Boolean regexBoolean(String text, String regex) {
        String value = regexGroup(text, regex);
        return value == null ? null : Boolean.valueOf(value);
    }

    private static String firstLineContainingAll(String text, String... terms) {
        if (text == null) return null;
        for (String line : text.split("\\R")) {
            boolean all = true;
            for (String term : terms) if (!line.contains(term)) { all = false; break; }
            if (all) return line;
        }
        return null;
    }

    private static boolean containsLineWithAll(String text, String... terms) {
        return firstLineContainingAll(text, terms) != null;
    }

    private static boolean eq(Integer value, int expected) {
        return value != null && value == expected;
    }

    private static String stateName(Integer value) {
        if (eq(value, 0)) return "NOT_REGISTERED";
        if (eq(value, 1)) return "REGISTERING";
        if (eq(value, 2)) return "REGISTERED";
        return value == null ? "UNKNOWN" : "UNKNOWN_" + value;
    }

    private static String transportName(Integer value) {
        if (eq(value, 1)) return "WWAN";
        if (eq(value, 2)) return "WLAN";
        if (eq(value, 255)) return "INVALID";
        return value == null ? "UNKNOWN" : "UNKNOWN_" + value;
    }

    private static int myUid() {
        try {
            return (Integer) Class.forName("android.os.Process").getMethod("myUid").invoke(null);
        } catch (Throwable t) {
            addError("Process.myUid", t);
            return -1;
        }
    }

    private static String readFirstLine(String path) {
        try {
            List<String> lines = Files.readAllLines(Paths.get(path));
            return lines.isEmpty() ? "" : lines.get(0);
        } catch (Throwable t) {
            addError(path, t);
            return null;
        }
    }

    private static void addError(String label, Throwable throwable) {
        Throwable t = throwable;
        while (t instanceof InvocationTargetException
                && ((InvocationTargetException) t).getTargetException() != null) {
            t = ((InvocationTargetException) t).getTargetException();
        }
        errors.add(label + ": " + t.getClass().getName() + ": " + String.valueOf(t.getMessage()));
    }

    private static String now() {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
        f.setTimeZone(TimeZone.getDefault());
        return f.format(new Date());
    }

    private static void objectStart(StringBuilder j, String name) { quote(j, name); j.append(":{"); }
    private static void objectEnd(StringBuilder j) { trimComma(j); j.append("},"); }
    private static void field(StringBuilder j, String name, Object value) {
        quote(j, name); j.append(':');
        if (value == null) j.append("null");
        else if (value instanceof Number || value instanceof Boolean) j.append(value);
        else quote(j, String.valueOf(value));
        j.append(',');
    }
    private static void array(StringBuilder j, String name, List<String> values) {
        quote(j, name); j.append(": [");
        for (String value : values) { quote(j, value); j.append(','); }
        trimComma(j); j.append("],");
    }
    private static void quote(StringBuilder j, String value) {
        j.append('"');
        if (value != null) {
            for (int i = 0; i < value.length(); i++) {
                char c = value.charAt(i);
                if (c == '"' || c == '\\') j.append('\\').append(c);
                else if (c == '\n') j.append("\\n");
                else if (c == '\r') j.append("\\r");
                else if (c == '\t') j.append("\\t");
                else if (c < 0x20) j.append(String.format("\\u%04x", (int) c));
                else j.append(c);
            }
        }
        j.append('"');
    }
    private static void trimComma(StringBuilder j) {
        if (j.length() > 0 && j.charAt(j.length() - 1) == ',') j.setLength(j.length() - 1);
    }
}
