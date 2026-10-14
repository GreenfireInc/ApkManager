using ApkManager.Core;

namespace ApkManager.Windows {
    public class GetApkConfirmDialog : Adw.Dialog {
        public signal void confirmed();

        public GetApkConfirmDialog(
            string app_name,
            string install_path,
            Gdk.Paintable? icon,
            bool browser_download,
            bool replace_existing = false,
            string? existing_install_path = null,
            string? existing_version_label = null,
            string? new_version_label = null,
            bool same_version = false
        ) {
            title = dialog_title(
                app_name,
                browser_download,
                replace_existing,
                same_version
            );
            content_width = 360;
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui(
                app_name,
                install_path,
                icon,
                browser_download,
                replace_existing,
                existing_install_path,
                existing_version_label,
                new_version_label,
                same_version
            );
        }

        private static string dialog_title(
            string app_name,
            bool browser_download,
            bool replace_existing,
            bool same_version
        ) {
            if (browser_download) {
                return "Open %s?".printf(app_name);
            }
            if (replace_existing) {
                return same_version
                    ? "Replace %s?".printf(app_name)
                    : "Update %s?".printf(app_name);
            }
            return "Download %s?".printf(app_name);
        }

        private void build_ui(
            string app_name,
            string install_path,
            Gdk.Paintable? icon,
            bool browser_download,
            bool replace_existing,
            string? existing_install_path,
            string? existing_version_label,
            string? new_version_label,
            bool same_version
        ) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            var heading = new Gtk.Label(
                dialog_title(app_name, browser_download, replace_existing, same_version)
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

            if (replace_existing && existing_install_path != null && existing_install_path != "") {
                var notice = new Gtk.Label(build_replace_notice(
                    existing_install_path,
                    existing_version_label,
                    new_version_label,
                    same_version
                ));
                notice.wrap = true;
                notice.max_width_chars = 36;
                notice.width_request = 320;
                notice.justify = Gtk.Justification.CENTER;
                notice.halign = Gtk.Align.CENTER;
                notice.add_css_class("warning");
                box.append(notice);
            }

            var shown_path = display_install_path(install_path);
            var question = new Gtk.Label(
                browser_download
                    ? "Uptodown opens in the browser. Save the APK, then install it to"
                    : replace_existing
                        ? "Confirm to download and overwrite the installed APK at"
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
                confirm_button_label(browser_download, replace_existing, same_version)
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

        private static string confirm_button_label(
            bool browser_download,
            bool replace_existing,
            bool same_version
        ) {
            if (browser_download) {
                return "Open in browser";
            }
            if (replace_existing) {
                return same_version ? "Replace and install" : "Update and install";
            }
            return "Download and install";
        }

        private static string build_replace_notice(
            string existing_install_path,
            string? existing_version_label,
            string? new_version_label,
            bool same_version
        ) {
            var shown_path = display_install_path(existing_install_path);
            if (same_version) {
                return "This version is already installed at %s. Downloading again will replace that copy.".printf(
                    shown_path
                );
            }

            var existing_version = existing_version_label != null && existing_version_label.strip() != ""
                ? existing_version_label.strip()
                : "unknown version";
            var new_version = new_version_label != null && new_version_label.strip() != ""
                ? new_version_label.strip()
                : "the selected version";
            return "Installed copy: %s (v%s). Downloading v%s will replace it.".printf(
                shown_path,
                existing_version,
                new_version
            );
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
