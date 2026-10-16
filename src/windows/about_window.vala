using ApkManager.Core;

namespace ApkManager.Windows {
    public class AboutDialog : Object {
        public static void present(Gtk.Window parent) {
            var about = new Adw.AboutWindow();
            about.transient_for = parent;
            about.modal = true;
            about.destroy_with_parent = true;

            about.application_name = "ApkManager";
            about.application_icon = Core.APPLICATION_ID;
            about.version = Core.APPLICATION_VERSION;
            about.comments = "Inspect Android APK package contents on Linux";
            about.license_type = Gtk.License.GPL_3_0;

            about.add_credit_section("Credits", { "AppManager" });
            about.add_link("AppManager", "https://github.com/kem-a/AppManager");

            about.add_credit_section("Engines", { "APKTool" });
            about.add_link("APKTool", "https://apktool.org/");

            about.present();
        }
    }
}
