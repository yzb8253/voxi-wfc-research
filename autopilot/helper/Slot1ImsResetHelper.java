import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public final class Slot1ImsResetHelper {
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

    private Slot1ImsResetHelper() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !("dry-run".equals(args[0]) || "reset-slot1".equals(args[0]))) {
            fail("Only dry-run or reset-slot1 is accepted", 2);
        }

        int uid = androidInt("android.os.Process", "myUid");
        System.out.println("mode=" + args[0]);
        System.out.println("uid=" + uid);
        System.out.println("selinux=" + firstLine("/proc/self/attr/current"));

        Object isubBinder = service("isub");
        Object phoneBinder = service("phone");
        require(isubBinder != null, "isub binder");
        require(phoneBinder != null, "phone binder");
        System.out.println("isubDescriptor=" + invoke(isubBinder, "getInterfaceDescriptor", new Class<?>[0]));
        System.out.println("phoneDescriptor=" + invoke(phoneBinder, "getInterfaceDescriptor", new Class<?>[0]));

        Object isub = asInterface("com.android.internal.telephony.ISub$Stub", isubBinder);
        Object phone = asInterface("com.android.internal.telephony.ITelephony$Stub", phoneBinder);
        int phoneId = (Integer) invoke(isub, "getPhoneId", new Class<?>[] {int.class}, TARGET_SUB_ID);
        int slotId = (Integer) invoke(isub, "getSlotIndex", new Class<?>[] {int.class}, TARGET_SUB_ID);
        int[] slot1Subs = intArray(invoke(isub, "getSubId", new Class<?>[] {int.class}, TARGET_SLOT_ID));
        int[] slot0Subs = intArray(invoke(isub, "getSubId", new Class<?>[] {int.class}, PROTECTED_SLOT_ID));
        List<String> rows = activeRows(isub);
        String voxi = rowFor(rows, TARGET_SUB_ID);
        String ct = rowFor(rows, PROTECTED_SUB_ID);

        boolean uidPass = uid == 0;
        boolean targetPass = phoneId == TARGET_PHONE_ID && slotId == TARGET_SLOT_ID
                && contains(slot1Subs, TARGET_SUB_ID) && !contains(slot0Subs, TARGET_SUB_ID)
                && has(voxi, "carrierId", TARGET_CARRIER_ID)
                && has(voxi, "mcc", TARGET_MCC) && has(voxi, "mnc", TARGET_MNC);
        boolean slot0Pass = contains(slot0Subs, PROTECTED_SUB_ID)
                && has(ct, "simSlotIndex", PROTECTED_SLOT_ID)
                && has(ct, "mcc", PROTECTED_MCC) && has(ct, "mnc", PROTECTED_MNC);

        System.out.println("targetSub11=" + pass(voxi != null));
        System.out.println("targetSlot1=" + pass(slotId == TARGET_SLOT_ID && contains(slot1Subs, TARGET_SUB_ID)));
        System.out.println("targetPhone1=" + pass(phoneId == TARGET_PHONE_ID));
        System.out.println("targetCarrier28=" + pass(has(voxi, "carrierId", TARGET_CARRIER_ID)));
        System.out.println("targetMccMnc23415=" + pass(has(voxi, "mcc", TARGET_MCC) && has(voxi, "mnc", TARGET_MNC)));
        System.out.println("protectedSlot0Sub1MccMnc46011=" + pass(slot0Pass));
        System.out.println("safetyGate=" + pass(uidPass && targetPass && slot0Pass));

        if (!(uidPass && targetPass && slot0Pass)) {
            fail("Safety gate failed; no write executed", 10);
        }
        if ("dry-run".equals(args[0])) {
            System.out.println("WOULD_CALL=ITelephony.resetIms(1)");
            return;
        }

        System.out.println("WRITE_CALL=ITelephony.resetIms(1)");
        System.out.println("writeStartEpochMs=" + System.currentTimeMillis());
        invoke(phone, "resetIms", new Class<?>[] {int.class}, TARGET_SLOT_ID);
        System.out.println("writeEndEpochMs=" + System.currentTimeMillis());
        System.out.println("writeResult=RETURNED_NO_EXCEPTION");
    }

    private static Object service(String name) throws Exception {
        Class<?> sm = Class.forName("android.os.ServiceManager");
        return sm.getMethod("getService", String.class).invoke(null, name);
    }

    private static Object asInterface(String stubName, Object binder) throws Exception {
        Class<?> ib = Class.forName("android.os.IBinder");
        return Class.forName(stubName).getMethod("asInterface", ib).invoke(null, binder);
    }

    private static Object invoke(Object target, String name, Class<?>[] types, Object... args) throws Exception {
        Method m = target.getClass().getMethod(name, types);
        return m.invoke(target, args);
    }

    private static int androidInt(String className, String method) {
        try {
            return (Integer) Class.forName(className).getMethod(method).invoke(null);
        } catch (Throwable t) {
            return -1;
        }
    }

    private static List<String> activeRows(Object isub) throws Exception {
        Object list = invoke(isub, "getActiveSubscriptionInfoList",
                new Class<?>[] {String.class, String.class}, "com.android.shell", null);
        List<String> rows = new ArrayList<>();
        if (list instanceof Iterable) {
            for (Object item : (Iterable<?>) list) rows.add(String.valueOf(item));
        }
        return rows;
    }

    private static String rowFor(List<String> rows, int subId) {
        for (String row : rows) {
            if (row.matches("(?s).*\\bid\\s*=\\s*" + subId + "\\b.*")
                    || row.matches("(?s).*\\bsubId\\s*=\\s*" + subId + "\\b.*")) return row;
        }
        return null;
    }

    private static boolean has(String row, String field, int value) {
        return row != null && row.matches("(?s).*\\b" + field + "\\s*=\\s*" + value + "\\b.*");
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

    private static String firstLine(String path) {
        try {
            List<String> lines = Files.readAllLines(Paths.get(path));
            return lines.isEmpty() ? "" : lines.get(0);
        } catch (Throwable t) {
            return "UNAVAILABLE:" + t.getClass().getName();
        }
    }

    private static void require(boolean ok, String label) {
        if (!ok) fail(label + " unavailable", 3);
    }

    private static String pass(boolean ok) { return ok ? "PASS" : "FAIL"; }

    private static void fail(String message, int code) {
        System.out.println("ERROR=" + message);
        System.exit(code);
    }
}
