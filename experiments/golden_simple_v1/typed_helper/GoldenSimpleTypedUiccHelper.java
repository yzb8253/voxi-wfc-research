import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

public final class GoldenSimpleTypedUiccHelper {
    private static final int SUB_ID = 11;
    private static final int SLOT_ID = 1;
    private static final int PHONE_ID = 1;
    private static final String DESCRIPTOR = "com.android.internal.telephony.ISub";

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !("dry-run".equals(args[0]) || "disable".equals(args[0]) || "enable".equals(args[0]))) fail("MODE", 2);
        String mode = args[0];
        int uid = androidInt("android.os.Process", "myUid");
        Object binder = Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, "isub");
        require(uid == 0, "UID_NOT_ROOT");
        require(binder != null, "ISUB_BINDER_MISSING");
        String descriptor = String.valueOf(invoke(binder, "getInterfaceDescriptor", new Class<?>[0]));
        require(DESCRIPTOR.equals(descriptor), "ISUB_DESCRIPTOR_MISMATCH");
        Class<?> ibinder = Class.forName("android.os.IBinder");
        Object isub = Class.forName("com.android.internal.telephony.ISub$Stub").getMethod("asInterface", ibinder).invoke(null, binder);
        require(isub != null, "ISUB_PROXY_MISSING");

        int phone = (Integer) invoke(isub, "getPhoneId", new Class<?>[]{int.class}, SUB_ID);
        int slot = (Integer) invoke(isub, "getSlotIndex", new Class<?>[]{int.class}, SUB_ID);
        int[] slot1 = intArray(invoke(isub, "getSubId", new Class<?>[]{int.class}, SLOT_ID));
        int[] slot0 = intArray(invoke(isub, "getSubId", new Class<?>[]{int.class}, 0));
        String simState = run("getprop gsm.sim.state").trim();
        require(simState.split(",", -1).length >= 2 && "ABSENT".equals(simState.split(",", -1)[0].trim()), "SLOT0_NOT_ABSENT");
        require(!contains(slot0, SUB_ID), "SLOT0_CONTAINS_TARGET");

        String dump = run("dumpsys isub");
        Sections sections = Sections.parse(dump);
        require(sections.valid, "ISUB_SECTIONS_INVALID");
        Row active = Row.find(sections.active, SUB_ID);
        Row db = Row.find(sections.db, SUB_ID);
        Row all = Row.find(sections.all, SUB_ID);
        boolean activeExact = active.exact("1", "true");
        boolean storedF8 = db.exact("-1", "false") && all.exact("-1", "false") && db.sameState(all);
        boolean storedIdentity = db.identityExact() && all.identityExact();

        System.out.println("MODE=" + mode);
        System.out.println("UID=" + uid);
        System.out.println("ISUB_DESCRIPTOR=" + descriptor);
        System.out.println("PHONE_ID=" + phone);
        System.out.println("SLOT_INDEX=" + slot);
        System.out.println("SLOT1_SUBIDS=" + ints(slot1));
        System.out.println("SLOT0_SUBIDS=" + ints(slot0));
        System.out.println("SLOT0_PHYSICAL_ABSENT=YES");
        System.out.println("ACTIVE_TARGET=" + active.describe());
        System.out.println("DB_TARGET=" + db.describe());
        System.out.println("ALL_TARGET=" + all.describe());

        if ("dry-run".equals(mode) || "disable".equals(mode)) {
            require(phone == PHONE_ID && slot == SLOT_ID && contains(slot1, SUB_ID), "ACTIVE_MAPPING_GATE");
            require(activeExact, "ACTIVE_VOXI_GATE");
        } else {
            require(storedIdentity, "STORED_VOXI_IDENTITY_GATE");
        }

        if ("dry-run".equals(mode)) {
            System.out.println("TYPED_UICC_DRY_RUN=PASS");
            return;
        }
        boolean enabled = "enable".equals(mode);
        long start = System.currentTimeMillis();
        System.out.println("TYPED_UICC_" + mode.toUpperCase() + "_START_MS=" + start);
        Object result;
        try {
            result = invoke(isub, "setUiccApplicationsEnabled", new Class<?>[]{boolean.class, int.class}, enabled, SUB_ID);
        } catch (Throwable t) {
            System.out.println("TYPED_UICC_" + mode.toUpperCase() + "_EXCEPTION=" + t.getClass().getName() + ":" + safe(t));
            fail("TYPED_INVOCATION_EXCEPTION", 11);
            return;
        }
        System.out.println("TYPED_UICC_" + mode.toUpperCase() + "_RETURN=" + String.valueOf(result));
        System.out.println("TYPED_UICC_" + mode.toUpperCase() + "_END_MS=" + System.currentTimeMillis());
    }

    private static Object invoke(Object target, String name, Class<?>[] types, Object... args) throws Exception {
        Method method = target.getClass().getMethod(name, types);
        return method.invoke(target, args);
    }
    private static int androidInt(String clazz, String method) { try { return (Integer) Class.forName(clazz).getMethod(method).invoke(null); } catch (Throwable t) { return -1; } }
    private static String run(String command) throws Exception {
        Process p = Runtime.getRuntime().exec(new String[]{"/system/bin/sh", "-c", command});
        StringBuilder b = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) { String line; while ((line = r.readLine()) != null) b.append(line).append('\n'); }
        int rc = p.waitFor(); require(rc == 0, "READ_COMMAND_FAILED_" + command); return b.toString();
    }
    private static int[] intArray(Object value) { if (value == null) return new int[0]; int[] out = new int[Array.getLength(value)]; for (int i=0;i<out.length;i++) out[i]=(Integer)Array.get(value,i); return out; }
    private static boolean contains(int[] a, int n) { for(int v:a) if(v==n) return true; return false; }
    private static String ints(int[] a) { StringBuilder b=new StringBuilder("["); for(int i=0;i<a.length;i++){if(i>0)b.append(',');b.append(a[i]);} return b.append(']').toString(); }
    private static String safe(Throwable t) { String m=t.getMessage(); return m==null?"":m.replace('\n',' ').replace('\r',' '); }
    private static void require(boolean ok, String message) { if(!ok) fail(message,10); }
    private static void fail(String message, int code) { System.out.println("ERROR="+message); System.exit(code); }

    private static final class Sections {
        boolean valid; String active="",db="",all="";
        static Sections parse(String text) {
            Sections s=new Sections(); String[] lines=text.split("\\R",-1); int a=-1,d=-1,l=-1,e=-1;
            for(int i=0;i<lines.length;i++){String x=lines[i].trim();if("ActiveSubInfoList:".equals(x))a=i;else if("ActiveSubInfoList in the DB:".equals(x))d=i;else if("AllSubInfoList:".equals(x))l=i;}
            if(a<0||d<=a||l<=d)return s;
            for(int i=l+1;i<lines.length;i++){if(lines[i].trim().matches("\\+{10,}")){e=i;break;}}
            if(e<0)return s;
            s.active=join(lines,a+1,d);s.db=join(lines,d+1,l);s.all=join(lines,l+1,e);s.valid=true;return s;
        }
        static String join(String[] lines,int start,int end){StringBuilder b=new StringBuilder();for(int i=start;i<end;i++)b.append(lines[i]).append('\n');return b.toString();}
    }
    private static final class Row {
        boolean present; String slot,carrier,mcc,mnc,apps;
        static Row find(String section,int id){Row r=new Row();for(String line:section.split("\\R")){if(line.trim().startsWith("{id="+id+" ")){r.present=true;r.slot=field(line,"simSlotIndex");r.carrier=field(line,"carrierId");r.mcc=field(line,"mcc");r.mnc=field(line,"mnc");r.apps=field(line,"areUiccApplicationsEnabled");break;}}return r;}
        static String field(String row,String name){java.util.regex.Matcher m=java.util.regex.Pattern.compile("(?:^|\\s)"+java.util.regex.Pattern.quote(name)+"=([^\\s}]+)").matcher(row);return m.find()?m.group(1):null;}
        boolean exact(String expectedSlot,String expectedApps){return present&&expectedSlot.equals(slot)&&"28".equals(carrier)&&"234".equals(mcc)&&"15".equals(mnc)&&expectedApps.equals(apps);}
        boolean identityExact(){return present&&"28".equals(carrier)&&"234".equals(mcc)&&"15".equals(mnc);}
        boolean sameState(Row x){return present&&x.present&&eq(slot,x.slot)&&eq(carrier,x.carrier)&&eq(mcc,x.mcc)&&eq(mnc,x.mnc)&&eq(apps,x.apps);}
        static boolean eq(Object a,Object b){return a==null?b==null:a.equals(b);}
        String describe(){return present?("slot"+slot+"/apps="+apps+"/carrier="+carrier+"/mccmnc="+mcc+mnc):"MISSING";}
    }
}
