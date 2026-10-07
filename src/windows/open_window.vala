using ApkManager.Core;

namespace ApkManager.Windows {
    public class OpenWindow : Adw.Window {
        public signal void inspect_requested(string apk_path);

        private string apk_path;
        private Gtk.Label title_label;
        private Gtk.Label subtitle_label;
        private Gtk.Button inspect_button;

        public OpenWindow(Adw.Application app, string path) {
            Object(
                application: app,
                title: "Open APK",
                modal: true,
                default_width: 520,
                default_height: 360,
                destroy_with_parent: true
            );
            apk_path = path;
            build_ui();
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            toolbar.add_top_bar(header);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            box.margin_top = 24;
            box.margin_bottom = 24;
            box.margin_start = 24;
            box.margin_end = 24;
            box.halign = Gtk.Align.CENTER;
            box.valign = Gtk.Align.CENTER;
            toolbar.content = box;

            var icon = new Gtk.Image.from_icon_name("application-x-android-package");
            icon.set_pixel_size(96);
            box.append(icon);

            title_label = new Gtk.Label(Path.get_basename(apk_path));
            title_label.add_css_class("title-1");
            title_label.wrap = true;
            title_label.justify = Gtk.Justification.CENTER;
            box.append(title_label);

            subtitle_label = new Gtk.Label("");
            subtitle_label.add_css_class("dim-label");
            subtitle_label.wrap = true;
            subtitle_label.justify = Gtk.Justification.CENTER;
            box.append(subtitle_label);

            inspect_button = new Gtk.Button.with_label("Inspect APK");
            inspect_button.add_css_class("suggested-action");
            inspect_button.clicked.connect(() => {
                inspect_requested(apk_path);
                close();
            });
            box.append(inspect_button);

            update_summary();
        }

        private void update_summary() {
            try {
                var entries = ApkArchive.list_entries(apk_path);
                int dex_count = 0;
                foreach (var entry in entries) {
                    if (entry.path.has_suffix(".dex")) {
                        dex_count++;
                    }
                }
                subtitle_label.set_text("%d archive entries • %d DEX file(s)".printf(entries.size, dex_count));
            } catch (Error e) {
                subtitle_label.set_text("Could not read archive: %s".printf(e.message));
                inspect_button.sensitive = false;
            }
        }
    }
}
