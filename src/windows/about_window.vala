using ApkManager.Core;

namespace ApkManager.Windows {
    public class AboutDialog : Object {
        private const string GITHUB_CREDIT_TITLE = "ApkManager";
        private const string GITHUB_REPOSITORY_URL = "https://github.com/GreenfireInc/ApkManager/";
        private const string GITHUB_ICON_DATA_KEY = "apk-manager-github-icon";
        private const int DISTRO_ICON_PX = 32;

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

            var distro = HostDistro.detect();
            about.debug_info = build_debug_info(distro);
            about.debug_info_filename = "apk-manager-debug-info.txt";

            // Credit subpages are only parented once pushed, so decorate rows on each push.
            var navigation = find_navigation_view(about);
            if (navigation != null) {
                navigation.pushed.connect(() => add_github_icon(navigation));
            }

            add_distro_badge(about, distro);

            about.present();
        }

        // Adw.AboutWindow has no API for extra main-page content, so place the badge
        // right after its version pill (the button with the "app-version" style class).
        private static void add_distro_badge(Adw.AboutWindow about, HostDistro distro) {
            var version_button = find_with_css_class(about, "app-version");
            if (version_button == null || version_button.get_parent() == null) {
                return;
            }

            var icon_name = distro.icon_name;
            var theme = Gtk.IconTheme.get_for_display(about.get_display());
            if (!theme.has_icon(icon_name)) {
                icon_name = "apk-manager-distro-linux";
            }

            var badge = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            badge.halign = Gtk.Align.CENTER;
            badge.margin_top = 12;
            badge.tooltip_text = distro.family_name != null
                ? "Detected %s (%s family)".printf(distro.pretty_name, distro.family_name)
                : "Detected %s".printf(distro.pretty_name);

            var icon = new Gtk.Image.from_icon_name(icon_name);
            icon.pixel_size = DISTRO_ICON_PX;
            badge.append(icon);

            var text = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            text.valign = Gtk.Align.CENTER;
            var caption = new Gtk.Label("Running on");
            caption.xalign = 0;
            caption.add_css_class("caption");
            caption.add_css_class("dim-label");
            text.append(caption);
            var name = new Gtk.Label(distro.pretty_name);
            name.xalign = 0;
            name.add_css_class("heading");
            text.append(name);
            if (distro.matched_by_id_like && distro.family_name != null) {
                var family = new Gtk.Label("%s-based".printf(distro.family_name));
                family.xalign = 0;
                family.add_css_class("caption");
                family.add_css_class("dim-label");
                text.append(family);
            }
            badge.append(text);

            badge.insert_after(version_button.get_parent(), version_button);
        }

        private static string build_debug_info(HostDistro distro) {
            var info = new StringBuilder();
            info.append_printf("ApkManager %s\n", Core.APPLICATION_VERSION);
            info.append_printf("Distribution: %s\n", distro.pretty_name);
            info.append_printf("ID: %s\n", distro.id);
            if (distro.version_id != "") {
                info.append_printf("Version: %s\n", distro.version_id);
            }
            info.append_printf("Family: %s\n", distro.family_name ?? "Other");
            info.append_printf(
                "GTK: %u.%u.%u\n", Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()
            );
            info.append_printf(
                "Libadwaita: %u.%u.%u\n", Adw.get_major_version(), Adw.get_minor_version(), Adw.get_micro_version()
            );
            return info.str;
        }

        private static Gtk.Widget? find_with_css_class(Gtk.Widget root, string css_class) {
            for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) {
                if (child.has_css_class(css_class)) {
                    return child;
                }
                var found = find_with_css_class(child, css_class);
                if (found != null) {
                    return found;
                }
            }
            return null;
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
