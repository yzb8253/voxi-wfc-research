import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

public final class Slot1UiccRecoverHelper {
    private static final int TARGET_SUB_ID = 11;
    private static final int PROTECTED_SUB_ID = 1;

    private Slot1UiccRecoverHelper() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !("dry-run".equals(args[0]) || "recover".equals(args[0]))) {
            fail("Only dry-run or recover is accepted", 2);
        }

        int uid = androidInt("android.os.Process", "myUid");
        Object binder = service("isub");
        require(binder != null, "isub binder unavailable");
        Object isub = asInterface(binder);
        int slot11 = (Integer) invoke(isub, "getSlotIndex", new Class<?>[] {int.class}, TARGET_SUB_ID);
        int phone11 = (Integer) invoke(isub, "getPhoneId", new Class<?>[] {int.class}, TARGET_SUB_ID);
        int[] slot0 = intArray(invoke(isub, "getSubId", new Class<?>[] {int.class}, 0));
        String dump = run("dumpsys isub");
        String voxi = findRow(dump, "id=11");
        String ct = findRow(dump, "id=1");

        boolean voxiIdentity = voxi != null && field(voxi, "carrierId", 28)
                && field(voxi, "mcc", 234) && field(voxi, "mnc", 15);
        boolean voxiInactive = voxiIdentity && field(voxi, "simSlotIndex", -1)
                && boolField(voxi, "areUiccApplicationsEnabled", false)
                && slot11 == -1 && phone11 == Integer.MAX_VALUE;
        boolean slot0Protected = ct != null && field(ct, "simSlotIndex", 0)
                && field(ct, "carrierId", 2237) && field(ct, "mcc", 460)
                && field(ct, "mnc", 11) && boolField(ct, "areUiccApplicationsEnabled", true)
                && contains(slot0, PROTECTED_SUB_ID) && !contains(slot0, TARGET_SUB_ID);
        boolean gate = uid == 0 && voxiInactive && slot0Protected;

        System.out.println("mode=" + args[0]);
        System.out.println("uid=" + uid);
        System.out.println("selinux=" + firstLine("/proc/self/attr/current"));
        System.out.println("descriptor=" + invoke(binder, "getInterfaceDescriptor", new Class<?>[0]));
        System.out.println("voxiIdentity11Carrier28MccMnc23415=" + pass(voxiIdentity));
        System.out.println("voxiInactiveSlotMinus1=" + pass(slot11 == -1 && phone11 == Integer.MAX_VALUE));
        System.out.println("voxiUiccAppsDisabled=" + pass(voxi != null && boolField(voxi, "areUiccApplicationsEnabled", false)));
        System.out.println("protectedSlot0Sub1MccMnc46011Enabled=" + pass(slot0Protected));
        System.out.println("inactiveRecoveryGate=" + pass(gate));

        if (!gate) fail("Inactive recovery gate failed; no write executed", 10);
        if ("dry-run".equals(args[0])) {
            System.out.println("WOULD_CALL=ISub.setUiccApplicationsEnabled(true,11)");
            return;
        }

        System.out.println("WRITE_CALL=ISub.setUiccApplicationsEnabled(true,11)");
        System.out.println("writeStartEpochMs=" + System.currentTimeMillis());
        Object result = invoke(isub, "setUiccApplicationsEnabled",
                new Class<?>[] {boolean.class, int.class}, true, TARGET_SUB_ID);
        System.out.println("writeEndEpochMs=" + System.currentTimeMillis());
        System.out.println("return=" + result);
    }

    private static Object service(String name) throws Exception {
        return Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, name);
    }

    private static Object asInterface(Object binder) throws Exception {
        Class<?> ib = Class.forName("android.os.IBinder");
        return Class.forName("com.android.internal.telephony.ISub$Stub")
                .getMethod("asInterface", ib).invoke(null, binder);
    }

    private static Object invoke(Object target, String name, Class<?>[] types, Object... args) throws Exception {
        Method method = target.getClass().getMethod(name, types);
        return method.invoke(target, args);
    }

    private static String run(String command) throws Exception {
        Process process = Runtime.getRuntime().exec(new String[] {"/system/bin/sh", "-c", command});
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) out.append(line).append('\n');
        }
        process.waitFor();
        return out.toString();
    }

    private static String findRow(String text, String id) {
        for (String line : text.split("\\R")) {
            if (line.contains("{" + id + " ")) return line.trim();
        }
        return null;
    }

    private static boolean field(String row, String name, int value) {
        return row.matches("(?s).*\\b" + name + "\\s*=\\s*" + value + "\\b.*");
    }

    private static boolean boolField(String row, String name, boolean value) {
        return row.matches("(?s).*\\b" + name + "\\s*=\\s*" + value + "\\b.*");
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

    private static int androidInt(String className, String method) {
        try { return (Integer) Class.forName(className).getMethod(method).invoke(null); }
        catch (Throwable t) { return -1; }
    }

    private static String firstLine(String path) {
        try {
            List<String> lines = Files.readAllLines(Paths.get(path));
            return lines.isEmpty() ? "" : lines.get(0);
        } catch (Throwable t) { return "UNAVAILABLE:" + t.getClass().getName(); }
    }

    private static void require(boolean ok, String message) { if (!ok) fail(message, 3); }
    private static String pass(boolean ok) { return ok ? "PASS" : "FAIL"; }
    private static void fail(String message, int code) {
        System.out.println("ERROR=" + message);
        System.exit(code);
    }
}
