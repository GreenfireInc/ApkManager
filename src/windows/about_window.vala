using ApkManager.Core;

namespace ApkManager.Windows {
    public class AboutDialog : Object {
        private const string GITHUB_CREDIT_TITLE = "ApkManager";
        private const string GITHUB_REPOSITORY_URL = "https://github.com/GreenfireInc/ApkManager/";
        private const string GITHUB_ICON_DATA_KEY = "apk-manager-github-icon";

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

            about.add_credit_section("Credits", {
                "%s %s".printf(GITHUB_CREDIT_TITLE, GITHUB_REPOSITORY_URL),
                "AppManager https://github.com/kem-a/AppManager"
            });
            about.add_link("AppManager", "https://github.com/kem-a/AppManager");

            about.add_credit_section("Engines", { "APKTool https://apktool.org/" });
            about.add_link("APKTool", "https://apktool.org/");

            // Credit subpages are only parented once pushed, so decorate rows on each push.
            var navigation = find_navigation_view(about);
            if (navigation != null) {
                navigation.pushed.connect(() => add_github_icon(navigation));
            }

            about.present();
        }

        private static Adw.NavigationView? find_navigation_view(Gtk.Widget root) {
            for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) {
                var navigation = child as Adw.NavigationView;
                if (navigation != null) {
                    return navigation;
                }
                navigation = find_navigation_view(child);
                if (navigation != null) {
                    return navigation;
                }
            }
            return null;
        }

        private static void add_github_icon(Gtk.Widget root) {
            for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) {
                var row = child as Adw.ActionRow;
                if (row != null && row.title == GITHUB_CREDIT_TITLE
                    && !row.get_data<bool>(GITHUB_ICON_DATA_KEY)) {
                    var icon = new Gtk.Image.from_icon_name("github-symbolic");
                    icon.pixel_size = 16;
                    icon.tooltip_text = "GitHub";
                    row.add_prefix(icon);
                    row.set_data<bool>(GITHUB_ICON_DATA_KEY, true);
                    continue;
                }
                add_github_icon(child);
            }
        }
    }
}
