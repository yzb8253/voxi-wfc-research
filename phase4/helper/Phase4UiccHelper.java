import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class Phase4UiccHelper {
    private static final int TARGET_SUB_ID = 11;
    private static final int TARGET_SLOT_ID = 1;
    private static final int TARGET_PHONE_ID = 1;
    private static final int TARGET_CARRIER_ID = 28;
    private static final int TARGET_MCC = 234;
    private static final int TARGET_MNC = 15;
    private static final String I_SUB_DESCRIPTOR = "com.android.internal.telephony.ISub";

    private Phase4UiccHelper() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || (!"dry-run".equals(args[0]) && !"disable".equals(args[0]))) {
            System.out.println("Only dry-run and the Phase 4D-2 approved disable mode are enabled.");
            System.exit(2);
        }
        boolean disableMode = "disable".equals(args[0]);

        System.out.println("=== PHASE 4D HELPER START ===");
        System.out.println("mode: " + args[0]);
        printIdentity();

        Object binder = getService("isub");
        System.out.println("isub binder != null: " + passFail(binder != null));
        if (binder == null) {
            System.exit(3);
        }

        String descriptor = invokeString(binder, "getInterfaceDescriptor");
        System.out.println("isub descriptor: " + descriptor);
        System.out.println("descriptor expected: " + I_SUB_DESCRIPTOR + " " + passFail(I_SUB_DESCRIPTOR.equals(descriptor)));

        Object isub = asISubInterface(binder);
        System.out.println("ISub proxy != null: " + passFail(isub != null));
        if (isub == null) {
            System.exit(4);
        }

        Integer phoneId = invokeInt(isub, "getPhoneId", new Class<?>[] { int.class }, TARGET_SUB_ID);
        Integer slotIndex = invokeInt(isub, "getSlotIndex", new Class<?>[] { int.class }, TARGET_SUB_ID);
        int[] subIdsForSlot = invokeIntArray(isub, "getSubId", new Class<?>[] { int.class }, TARGET_SLOT_ID);

        System.out.println("=== BINDER MAPPING ===");
        System.out.println("getPhoneId(11): " + valueOrError(phoneId) + " " + passFail(phoneId != null && phoneId == TARGET_PHONE_ID));
        System.out.println("getSlotIndex(11): " + valueOrError(slotIndex) + " " + passFail(slotIndex != null && slotIndex == TARGET_SLOT_ID));
        System.out.println("getSubId(1): " + intArrayToString(subIdsForSlot) + " " + passFail(contains(subIdsForSlot, TARGET_SUB_ID)));

        System.out.println("=== PRIVILEGED READ PROBE ===");
        Boolean enabled = null;
        try {
            enabled = invokeBoolean(isub, "isSubscriptionEnabled", new Class<?>[] { int.class }, TARGET_SUB_ID);
            System.out.println("isSubscriptionEnabled(11): " + enabled);
        } catch (Throwable t) {
            System.out.println("isSubscriptionEnabled(11) exception: " + t.getClass().getName() + ": " + safeMessage(t));
            Throwable cause = t.getCause();
            if (cause != null) {
                System.out.println("cause: " + cause.getClass().getName() + ": " + safeMessage(cause));
            }
        }

        Verification verification = verifyTarget(isub, phoneId, subIdsForSlot);
        verification.print();

        if (disableMode) {
            System.out.println("=== PHASE 4D-2 PRE-WRITE GATE ===");
            System.out.println("target verification all pass: " + passFail(verification.allPass()));
            System.out.println("areUiccApplicationsEnabled=true: " + passFail(verification.uiccAppsEnabledPass)
                    + " [" + verification.activeEvidence + "]");
            if (!verification.allPass() || !verification.uiccAppsEnabledPass) {
                System.out.println("PRE-WRITE GATE FAILED. No write call executed.");
                System.exit(10);
            }
            executeApprovedDisable(isub);
            return;
        }

        HalInfo halInfo = detectHalBranch();
        System.out.println("=== RADIO HAL BRANCH ===");
        System.out.println("phoneId 1 HAL version: " + halInfo.version);
        System.out.println("QTI expected branch: " + halInfo.branch);
        if (halInfo.error != null) {
            System.out.println("HAL detection note: " + halInfo.error);
        }

        System.out.println("=== PHASE 4D-1 DRY RUN RESULT ===");
        System.out.println("helper UID0: " + passFail(getUid() == 0));
        System.out.println("isub bound: " + passFail(isub != null));
        System.out.println("descriptor: " + descriptor);
        System.out.println("getPhoneId(11): " + valueOrError(phoneId));
        System.out.println("getSlotIndex(11): " + valueOrError(slotIndex));
        System.out.println("getSubId(1): " + intArrayToString(subIdsForSlot));
        System.out.println("isSubscriptionEnabled(11): " + (enabled == null ? "FAILED_OR_DENIED" : enabled.toString()));
        System.out.println("privileged read passed: " + passFail(enabled != null));
        System.out.println("target verification all pass: " + passFail(verification.allPass()));
        System.out.println("current Radio HAL version: " + halInfo.version);
        System.out.println("QTI branch: " + halInfo.branch);
        System.out.println("SELinux/Binder denial observed: " + (enabled == null ? "CHECK OUTPUT ABOVE" : "NO"));

        System.out.println("WOULD CALL ON FUTURE DISABLE:");
        System.out.println("ISub." + "setUiccApplicationsEnabled" + "(false, 11)");
        System.out.println("WOULD CALL ON FUTURE RECOVER:");
        System.out.println("ISub." + "setUiccApplicationsEnabled" + "(true, 11)");
    }

    private static void executeApprovedDisable(Object isub) {
        System.out.println("=== PHASE 4D-2 APPROVED WRITE ===");
        System.out.println("approved call: ISub.setUiccApplicationsEnabled(false, 11)");
        String start = now();
        System.out.println("call_start_epoch_ms: " + System.currentTimeMillis());
        System.out.println("call_start_iso: " + start);
        try {
            Method m = isub.getClass().getMethod("setUiccApplicationsEnabled", boolean.class, int.class);
            Object result = m.invoke(isub, false, TARGET_SUB_ID);
            System.out.println("call_end_epoch_ms: " + System.currentTimeMillis());
            System.out.println("call_end_iso: " + now());
            System.out.println("return_int: " + result);
            System.out.println("exception: NONE");
        } catch (Throwable t) {
            System.out.println("call_end_epoch_ms: " + System.currentTimeMillis());
            System.out.println("call_end_iso: " + now());
            System.out.println("return_int: UNAVAILABLE");
            System.out.println("exception: " + t.getClass().getName() + ": " + safeMessage(t));
            Throwable cause = t.getCause();
            if (cause != null) {
                System.out.println("cause: " + cause.getClass().getName() + ": " + safeMessage(cause));
            }
            System.exit(11);
        }
    }

    private static void printIdentity() {
        System.out.println("Process.myUid(): " + getUid());
        System.out.println("Process.myPid(): " + getPid());
        System.out.println("SELinux context: " + readFirstLine("/proc/self/attr/current"));
    }

    private static int getUid() {
        try {
            Class<?> process = Class.forName("android.os.Process");
            return (Integer) process.getMethod("myUid").invoke(null);
        } catch (Throwable t) {
            return -1;
        }
    }

    private static int getPid() {
        try {
            Class<?> process = Class.forName("android.os.Process");
            return (Integer) process.getMethod("myPid").invoke(null);
        } catch (Throwable t) {
            return -1;
        }
    }

    private static Object getService(String name) throws Exception {
        Class<?> sm = Class.forName("android.os.ServiceManager");
        Method getService = sm.getMethod("getService", String.class);
        return getService.invoke(null, name);
    }

    private static Object asISubInterface(Object binder) throws Exception {
        Class<?> stub = Class.forName("com.android.internal.telephony.ISub$Stub");
        Method asInterface = stub.getMethod("asInterface", Class.forName("android.os.IBinder"));
        return asInterface.invoke(null, binder);
    }

    private static String invokeString(Object target, String methodName) throws Exception {
        Object out = target.getClass().getMethod(methodName).invoke(target);
        return out == null ? null : String.valueOf(out);
    }

    private static Integer invokeInt(Object target, String methodName, Class<?>[] types, Object... args) throws Exception {
        Object out = target.getClass().getMethod(methodName, types).invoke(target, args);
        return out == null ? null : (Integer) out;
    }

    private static Boolean invokeBoolean(Object target, String methodName, Class<?>[] types, Object... args) throws Exception {
        Object out = target.getClass().getMethod(methodName, types).invoke(target, args);
        return out == null ? null : (Boolean) out;
    }

    private static int[] invokeIntArray(Object target, String methodName, Class<?>[] types, Object... args) throws Exception {
        Object out = target.getClass().getMethod(methodName, types).invoke(target, args);
        if (out == null) {
            return null;
        }
        int len = Array.getLength(out);
        int[] values = new int[len];
        for (int i = 0; i < len; i++) {
            values[i] = (Integer) Array.get(out, i);
        }
        return values;
    }

    private static Verification verifyTarget(Object isub, Integer phoneId, int[] subIdsForSlot) {
        Verification v = new Verification();
        v.phoneEvidence = "ISub.getPhoneId(11)=" + valueOrError(phoneId);
        v.phonePass = phoneId != null && phoneId == TARGET_PHONE_ID;

        v.slot0Evidence = "ISub.getSubId(0)=";
        try {
            int[] slot0 = invokeIntArray(isub, "getSubId", new Class<?>[] { int.class }, 0);
            v.slot0Evidence += intArrayToString(slot0);
            v.slot0Pass = !contains(slot0, TARGET_SUB_ID);
        } catch (Throwable t) {
            v.slot0Evidence += "ERROR " + t.getClass().getName() + ": " + safeMessage(t);
            v.slot0Pass = false;
        }

        List<String> rows = loadActiveSubscriptionRows(isub);
        String targetRow = findTargetSubRow(rows);
        v.activeEvidence = targetRow == null ? "no active row containing id=11/subId=11" : targetRow;
        v.subPass = targetRow != null;
        v.slotPass = targetRow != null && hasField(targetRow, "simSlotIndex", TARGET_SLOT_ID);
        v.carrierPass = targetRow != null && hasField(targetRow, "carrierId", TARGET_CARRIER_ID);
        v.mccPass = targetRow != null && hasField(targetRow, "mcc", TARGET_MCC);
        v.mncPass = targetRow != null && hasField(targetRow, "mnc", TARGET_MNC);
        v.uiccAppsEnabledPass = targetRow != null && hasBooleanField(targetRow, "areUiccApplicationsEnabled", true);

        if (!v.slotPass && contains(subIdsForSlot, TARGET_SUB_ID)) {
            v.slotPass = true;
            v.slotEvidenceOverride = "ISub.getSubId(1) contains 11";
        }

        return v;
    }

    private static List<String> loadActiveSubscriptionRows(Object isub) {
        List<String> rows = new ArrayList<>();
        try {
            Method m = isub.getClass().getMethod("getActiveSubscriptionInfoList", String.class, String.class);
            Object list = m.invoke(isub, "com.android.shell", null);
            if (list instanceof Iterable) {
                for (Object item : (Iterable<?>) list) {
                    rows.add(String.valueOf(item));
                }
            }
            if (!rows.isEmpty()) {
                return rows;
            }
        } catch (Throwable ignored) {
            rows.add("ISub.getActiveSubscriptionInfoList failed: " + ignored.getClass().getName() + ": " + safeMessage(ignored));
        }

        String dumpsys = runReadOnlyCommand("dumpsys isub");
        for (String line : dumpsys.split("\\R")) {
            if (line.contains("id=11") || line.contains("simSlotIndex") || line.contains("carrierId") || line.contains("mcc=")) {
                rows.add(line.trim());
            }
        }
        return rows;
    }

    private static String findTargetSubRow(List<String> rows) {
        for (String row : rows) {
            if (row.contains("id=11") || row.contains("subId=11")) {
                return row;
            }
        }
        return null;
    }

    private static boolean hasField(String row, String field, int expected) {
        Pattern p = Pattern.compile("\\b" + Pattern.quote(field) + "\\s*=\\s*" + expected + "\\b");
        Matcher m = p.matcher(row);
        return m.find();
    }

    private static boolean hasBooleanField(String row, String field, boolean expected) {
        Pattern p = Pattern.compile("\\b" + Pattern.quote(field) + "\\s*=\\s*" + expected + "\\b");
        Matcher m = p.matcher(row);
        return m.find();
    }

    private static HalInfo detectHalBranch() {
        HalInfo info = new HalInfo();
        info.version = "UNKNOWN";
        info.branch = "UNKNOWN";
        try {
            Class<?> phoneFactory = Class.forName("com.android.internal.telephony.PhoneFactory");
            Object phone = phoneFactory.getMethod("getPhone", int.class).invoke(null, TARGET_PHONE_ID);
            if (phone == null) {
                info.error = "PhoneFactory.getPhone(1) returned null";
                return info;
            }
            Object hal = phone.getClass().getMethod("getHalVersion").invoke(phone);
            info.version = String.valueOf(hal);

            Object radio15 = findRadioHalVersion15();
            if (radio15 != null) {
                Method greaterOrEqual = hal.getClass().getMethod("greaterOrEqual", hal.getClass());
                boolean ge15 = (Boolean) greaterOrEqual.invoke(hal, radio15);
                info.branch = ge15 ? "super.setUiccApplicationsEnabled path" : "QtiUiccCardProvisioner activate/deactivate path";
            } else {
                info.branch = "UNKNOWN";
                info.error = "RADIO_HAL_VERSION_1_5 not found";
            }
        } catch (Throwable t) {
            info.error = t.getClass().getName() + ": " + safeMessage(t);
        }
        return info;
    }

    private static Object findRadioHalVersion15() {
        String[] holders = new String[] {
                "com.android.internal.telephony.RIL",
                "com.android.internal.telephony.RadioConfig",
                "com.android.internal.telephony.HalVersion"
        };
        for (String holder : holders) {
            try {
                Class<?> c = Class.forName(holder);
                return c.getField("RADIO_HAL_VERSION_1_5").get(null);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    private static String runReadOnlyCommand(String command) {
        StringBuilder out = new StringBuilder();
        try {
            Process p = Runtime.getRuntime().exec(new String[] { "/system/bin/sh", "-c", command });
            try (BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = br.readLine()) != null) {
                    out.append(line).append('\n');
                }
            }
            p.waitFor();
        } catch (Throwable t) {
            out.append("ERROR ").append(t.getClass().getName()).append(": ").append(safeMessage(t));
        }
        return out.toString();
    }

    private static boolean contains(int[] values, int target) {
        if (values == null) {
            return false;
        }
        for (int value : values) {
            if (value == target) {
                return true;
            }
        }
        return false;
    }

    private static String intArrayToString(int[] values) {
        if (values == null) {
            return "null";
        }
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < values.length; i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(values[i]);
        }
        sb.append(']');
        return sb.toString();
    }

    private static String readFirstLine(String path) {
        try {
            List<String> lines = Files.readAllLines(Paths.get(path));
            return lines.isEmpty() ? "" : lines.get(0);
        } catch (Throwable t) {
            return "UNAVAILABLE: " + t.getClass().getName() + ": " + safeMessage(t);
        }
    }

    private static String valueOrError(Object value) {
        return value == null ? "ERROR_OR_NULL" : String.valueOf(value);
    }

    private static String passFail(boolean ok) {
        return ok ? "PASS" : "FAIL";
    }

    private static String safeMessage(Throwable t) {
        String message = t.getMessage();
        return message == null ? "" : message.replace('\n', ' ').replace('\r', ' ');
    }

    private static String now() {
        return new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ").format(new java.util.Date());
    }

    private static final class Verification {
        boolean subPass;
        boolean slotPass;
        boolean phonePass;
        boolean carrierPass;
        boolean mccPass;
        boolean mncPass;
        boolean slot0Pass;
        boolean uiccAppsEnabledPass;
        String activeEvidence;
        String phoneEvidence;
        String slot0Evidence;
        String slotEvidenceOverride;

        void print() {
            System.out.println("=== TARGET VERIFICATION ===");
            System.out.println("subId 11: " + passFail(subPass) + " [" + activeEvidence + "]");
            System.out.println("slot 1: " + passFail(slotPass) + " [" + (slotEvidenceOverride == null ? activeEvidence : slotEvidenceOverride) + "]");
            System.out.println("phoneId 1: " + passFail(phonePass) + " [" + phoneEvidence + "]");
            System.out.println("carrierId 28: " + passFail(carrierPass) + " [" + activeEvidence + "]");
            System.out.println("MCC 234: " + passFail(mccPass) + " [" + activeEvidence + "]");
            System.out.println("MNC 15: " + passFail(mncPass) + " [" + activeEvidence + "]");
            System.out.println("slot0 != 11: " + passFail(slot0Pass) + " [" + slot0Evidence + "]");
        }

        boolean allPass() {
            return subPass && slotPass && phonePass && carrierPass && mccPass && mncPass && slot0Pass;
        }
    }

    private static final class HalInfo {
        String version;
        String branch;
        String error;
    }
}
