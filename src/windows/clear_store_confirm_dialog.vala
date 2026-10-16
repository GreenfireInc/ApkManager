namespace ApkManager.Windows {
    public class ClearStoreConfirmDialog : Adw.Dialog {
        public signal void confirmed();
        public signal void delete_confirmed();

        public ClearStoreConfirmDialog() {
            title = "Clear store?";
            content_width = 360;
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui();
        }

        private void build_ui() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            var heading = new Gtk.Label("Clear store data?");
            heading.add_css_class("title-2");
            heading.wrap = true;
            heading.justify = Gtk.Justification.CENTER;
            heading.halign = Gtk.Align.CENTER;
            box.append(heading);

            var icon = new Gtk.Image.from_icon_name("edit-clear-all-symbolic");
            icon.pixel_size = 72;
            icon.halign = Gtk.Align.CENTER;
            icon.add_css_class("warning");
            icon.margin_top = 4;
            icon.margin_bottom = 4;
            box.append(icon);

            var message = new Gtk.Label(
                "Reset all ApkManager settings to defaults, clear the store install history, and remove downloaded store APKs from the cache. You can also delete installed store APK files from disk."
            );
            message.wrap = true;
            message.max_width_chars = 36;
            message.width_request = 320;
            message.justify = Gtk.Justification.CENTER;
            message.halign = Gtk.Align.CENTER;
            message.add_css_class("heading");
            box.append(message);

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            actions.margin_top = 8;

            var clear_button = new Gtk.Button.with_label("Clear store");
            clear_button.hexpand = true;
            clear_button.clicked.connect(() => {
                confirmed();
                close();
            });
            actions.append(clear_button);

            var delete_button = new Gtk.Button.with_label("Clear and delete APKs from disk");
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
