// The smallest CRaC round trip for test/smoke.sh. It calls jdk.crac.Core.checkpointRestore() by reflection.
public class Crac {
    public static void main(String[] a) throws Exception {
        System.out.println("before checkpoint pid=" + ProcessHandle.current().pid());
        Class.forName("jdk.crac.Core").getMethod("checkpointRestore").invoke(null);
        System.out.println("restored pid=" + ProcessHandle.current().pid() + " java=" + System.getProperty("java.vm.version"));
    }
}
