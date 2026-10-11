using ApkManager.Core;

namespace ApkManager.Windows {
    public class InstallConfirmDialog : Adw.Dialog {
        public signal void confirmed();

        public InstallConfirmDialog(string app_name, Gdk.Paintable? icon) {
            title = "Open %s?".printf(app_name);
            content_width = 360;
            // Size to the child. The parent window must still be tall enough:
            // Adw.Dialog will not grow past it, and the last button is what gets cut.
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui(app_name, icon);
        }

        private void build_ui(string app_name, Gdk.Paintable? icon) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            var title = new Gtk.Label("Open %s?".printf(app_name));
            title.add_css_class("title-2");
            title.wrap = true;
            title.justify = Gtk.Justification.CENTER;
            title.halign = Gtk.Align.CENTER;
            box.append(title);

            var app_icon = new Gtk.Image();
            app_icon.pixel_size = 72;
            app_icon.halign = Gtk.Align.CENTER;
            app_icon.valign = Gtk.Align.CENTER;
            if (icon != null) {
                app_icon.set_from_paintable(icon);
            } else {
                app_icon.icon_name = "application-x-android-package";
            }

            var badge = new Gtk.Image.from_icon_name("dialog-warning");
            badge.pixel_size = 28;
            badge.halign = Gtk.Align.END;
            badge.valign = Gtk.Align.END;

            var overlay = new Gtk.Overlay();
            overlay.child = app_icon;
            overlay.add_overlay(badge);
            overlay.halign = Gtk.Align.CENTER;
            overlay.margin_top = 4;
            overlay.margin_bottom = 4;
            box.append(overlay);

            var warning = new Gtk.Label(
                "Origins of %s application can not be verified. Are you sure you want to install it?".printf(app_name)
            );
            warning.wrap = true;
            warning.max_width_chars = 36;
            warning.width_request = 320;
            warning.justify = Gtk.Justification.CENTER;
            warning.halign = Gtk.Align.CENTER;
            warning.add_css_class("heading");
            box.append(warning);

            var hint = new Gtk.Label("Install the APK to add it to your applications.");
            hint.wrap = true;
            hint.max_width_chars = 42;
            hint.width_request = 320;
            hint.justify = Gtk.Justification.CENTER;
            hint.halign = Gtk.Align.CENTER;
            hint.add_css_class("dim-label");
            box.append(hint);

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            actions.margin_top = 8;

            var install_button = new Gtk.Button.with_label("Install");
            install_button.hexpand = true;
            install_button.clicked.connect(() => {
                confirmed();
                close();
            });
            actions.append(install_button);

            var cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.hexpand = true;
            cancel_button.add_css_class("suggested-action");
            cancel_button.clicked.connect(() => {
                close();
            });
            actions.append(cancel_button);
            box.append(actions);

            child = box;
            default_widget = cancel_button;
        }
    }
}
