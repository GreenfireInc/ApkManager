namespace ApkManager.Windows {
    public class RemoveSessionConfirmDialog : Adw.Dialog {
        public signal void confirmed();
        public signal void delete_confirmed();

        public RemoveSessionConfirmDialog(string app_name, Gdk.Paintable? icon, int count = 1) {
            title = "Remove from recents?";
            content_width = 360;
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui(app_name, icon, count);
        }

        private void build_ui(string app_name, Gdk.Paintable? icon, int count) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            string heading;
            string body;
            if (count > 1) {
                heading = "Remove %s from recents?".printf(app_name);
                body = "Remove these %d APKs from recents, or delete the APK files from disk permanently.".printf(count);
            } else {
                heading = "Remove %s from recents?".printf(app_name);
                body = "Remove %s from recents, or delete the APK file from disk permanently.".printf(app_name);
            }

            var title = new Gtk.Label(heading);
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
            app_icon.margin_top = 4;
            app_icon.margin_bottom = 4;
            box.append(app_icon);

            var message = new Gtk.Label(body);
            message.wrap = true;
            message.max_width_chars = 36;
            message.width_request = 320;
            message.justify = Gtk.Justification.CENTER;
            message.halign = Gtk.Align.CENTER;
            message.add_css_class("heading");
            box.append(message);

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            actions.margin_top = 8;

            var remove_button = new Gtk.Button.with_label("Remove from recents");
            remove_button.hexpand = true;
            remove_button.clicked.connect(() => {
                confirmed();
                close();
            });
            actions.append(remove_button);

            var delete_button = new Gtk.Button.with_label(
                count > 1 ? "Delete APKs from disk" : "Delete APK from disk"
            );
            delete_button.hexpand = true;
            delete_button.add_css_class("destructive-action");
            delete_button.clicked.connect(() => {
                delete_confirmed();
                close();
            });
            actions.append(delete_button);

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
