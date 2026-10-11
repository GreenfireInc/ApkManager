using ApkManager.Core;

namespace ApkManager.Windows {
    public class GetApkConfirmDialog : Adw.Dialog {
        public signal void confirmed();

        public GetApkConfirmDialog(
            string app_name,
            string install_path,
            Gdk.Paintable? icon,
            bool browser_download
        ) {
            title = browser_download
                ? "Open %s?".printf(app_name)
                : "Download %s?".printf(app_name);
            content_width = 360;
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui(app_name, install_path, icon, browser_download);
        }

        private void build_ui(
            string app_name,
            string install_path,
            Gdk.Paintable? icon,
            bool browser_download
        ) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            var heading = new Gtk.Label(
                browser_download
                    ? "Open %s?".printf(app_name)
                    : "Download %s?".printf(app_name)
            );
            heading.add_css_class("title-2");
            heading.wrap = true;
            heading.justify = Gtk.Justification.CENTER;
            heading.halign = Gtk.Align.CENTER;
            box.append(heading);

            var app_icon = new Gtk.Image();
            app_icon.pixel_size = 72;
            app_icon.halign = Gtk.Align.CENTER;
            if (icon != null) {
                app_icon.set_from_paintable(icon);
            } else {
                app_icon.icon_name = "application-x-android-package";
            }
            app_icon.margin_top = 4;
            app_icon.margin_bottom = 4;
            box.append(app_icon);

            var shown_path = display_install_path(install_path);
            var question = new Gtk.Label(
                browser_download
                    ? "Uptodown opens in the browser. Save the APK, then install it to"
                    : "Download this APK and install it to"
            );
            question.wrap = true;
            question.max_width_chars = 36;
            question.width_request = 320;
            question.justify = Gtk.Justification.CENTER;
            question.halign = Gtk.Align.CENTER;
            question.add_css_class("heading");
            box.append(question);

            var path_label = new Gtk.Label(
                browser_download ? "%s.".printf(shown_path) : "%s?".printf(shown_path)
            );
            path_label.wrap = true;
            path_label.max_width_chars = 36;
            path_label.width_request = 320;
            path_label.justify = Gtk.Justification.CENTER;
            path_label.halign = Gtk.Align.CENTER;
            path_label.add_css_class("heading");
            box.append(path_label);

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            actions.margin_top = 8;

            var confirm_button = new Gtk.Button.with_label(
                browser_download ? "Open in browser" : "Download and install"
            );
            confirm_button.hexpand = true;
            confirm_button.add_css_class("suggested-action");
            confirm_button.clicked.connect(() => {
                confirmed();
                close();
            });
            actions.append(confirm_button);

            var cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.hexpand = true;
            cancel_button.clicked.connect(() => {
                close();
            });
            actions.append(cancel_button);
            box.append(actions);

            child = box;
            default_widget = cancel_button;
        }

        private static string display_install_path(string path) {
            var home = Environment.get_home_dir();
            if (home != "" && (path == home || path.has_prefix(home + "/"))) {
                return "~" + path.substring(home.length);
            }
            return path;
        }
    }
}
