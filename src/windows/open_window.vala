using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    public class OpenWindow : Adw.Window {
        private const int ICON_PX = 96;

        public signal void inspect_requested(string apk_path);

        private string apk_path;
        private Gtk.Label title_label;
        private Gtk.Label subtitle_label;
        private Gtk.Label size_label;
        private Gtk.Image icon_image;
        private Gtk.ProgressBar icon_progress;
        private Gtk.Button inspect_button;
        private uint icon_progress_timeout = 0;
        private bool icon_resolved = false;
        private bool closed = false;

        public OpenWindow(Adw.Application app, string path) {
            Object(
                application: app,
                title: "Install APK",
                modal: true,
                default_width: 520,
                default_height: 420,
                destroy_with_parent: true
            );
            apk_path = path;
            build_ui();
            close_request.connect(on_close_request);
            start_icon_load();
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            var verify_button = new Gtk.Button.with_label("Verify");
            verify_button.clicked.connect(on_verify_clicked);
            header.pack_end(verify_button);
            toolbar.add_top_bar(header);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            box.margin_top = 24;
            box.margin_bottom = 24;
            box.margin_start = 24;
            box.margin_end = 24;
            box.halign = Gtk.Align.CENTER;
            box.valign = Gtk.Align.CENTER;
            toolbar.content = box;

            var hint_label = new Gtk.Label("Drag and Drop to install in Applications");
            hint_label.add_css_class("dim-label");
            hint_label.wrap = true;
            hint_label.justify = Gtk.Justification.CENTER;
            box.append(hint_label);

            icon_image = new Gtk.Image();
            icon_image.pixel_size = ICON_PX;
            icon_image.width_request = ICON_PX;
            icon_image.height_request = ICON_PX;
            icon_image.halign = Gtk.Align.CENTER;
            icon_image.valign = Gtk.Align.CENTER;
            box.append(icon_image);

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

            size_label = new Gtk.Label("");
            size_label.add_css_class("dim-label");
            size_label.justify = Gtk.Justification.CENTER;
            box.append(size_label);

            icon_progress = new Gtk.ProgressBar();
            icon_progress.visible = false;
            icon_progress.width_request = 280;
            icon_progress.halign = Gtk.Align.CENTER;
            box.append(icon_progress);

            inspect_button = new Gtk.Button.with_label("Inspect APK");
            inspect_button.add_css_class("suggested-action");
            inspect_button.clicked.connect(() => {
                inspect_requested(apk_path);
                close();
            });
            box.append(inspect_button);

            update_summary();
        }

        private void start_icon_load() {
            // Small APKs resolve immediately. Show the bar only if lookup is still running.
            icon_progress_timeout = Timeout.add(200, () => {
                icon_progress_timeout = 0;
                if (icon_resolved || closed) {
                    return Source.REMOVE;
                }
                icon_progress.visible = true;
                icon_progress.pulse();
                icon_progress_timeout = Timeout.add(80, () => {
                    if (icon_resolved || closed) {
                        icon_progress_timeout = 0;
                        return Source.REMOVE;
                    }
                    icon_progress.pulse();
                    return Source.CONTINUE;
                });
                return Source.REMOVE;
            });
            load_icon_async.begin();
        }

        private async void load_icon_async() {
            Bytes? icon = yield read_icon_bytes();
            if (closed) {
                return;
            }

            icon_resolved = true;
            icon_progress.visible = false;
            if (icon_progress_timeout != 0) {
                Source.remove(icon_progress_timeout);
                icon_progress_timeout = 0;
            }

            if (icon != null) {
                try {
                    icon_image.set_from_paintable(Gdk.Texture.from_bytes(icon));
                    return;
                } catch (Error e) {
                    warning("Could not decode APK icon: %s", e.message);
                }
            }
            icon_image.icon_name = "application-x-android-package";
        }

        private async Bytes? read_icon_bytes() {
            Bytes? icon = null;
            new Thread<void>("apk-open-icon", () => {
                var icon_ref = ApkDisplayName.application_icon_ref(apk_path);
                if (icon_ref != null) {
                    icon = ApkIcon.load(apk_path, icon_ref);
                }
                Idle.add(read_icon_bytes.callback);
            });
            yield;
            return icon;
        }

        private bool on_close_request() {
            closed = true;
            if (icon_progress_timeout != 0) {
                Source.remove(icon_progress_timeout);
                icon_progress_timeout = 0;
            }
            return false;
        }

        private void on_verify_clicked() {
            var verify = new VerifyApkWindow(this, apk_path);
            verify.present();
        }

        private void update_summary() {
            size_label.set_text(apk_file_size(apk_path));

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

        private string apk_file_size(string path) {
            try {
                var file = File.new_for_path(path);
                var info = file.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE, null);
                return FileUtilsHelper.format_bytes(info.get_size());
            } catch (Error e) {
                return "Unknown size";
            }
        }
    }
}
