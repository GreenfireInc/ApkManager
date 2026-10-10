using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    public class OpenWindow : Adw.Window {
        private const int ICON_PX = 96;
        // Each icon center sits this fraction of row width away from the middle.
        private const double ICON_ROW_CENTER_OFFSET = 0.35;

        public signal void inspect_requested(string apk_path);
        public signal void install_requested(string installed_path);

        private string apk_path;
        private Gtk.Label title_label;
        private Gtk.Label subtitle_label;
        private Gtk.Label size_label;
        private Gtk.Image icon_image;
        private Gtk.Widget icon_drag_handle;
        private Gtk.Widget install_folder_column;
        private Gtk.Button install_folder_button;
        private Gtk.ProgressBar icon_progress;
        private Gtk.Button inspect_button;
        private uint icon_progress_timeout = 0;
        private bool icon_resolved = false;
        private bool closed = false;
        private bool installing = false;

        public OpenWindow(Adw.Application app, string path) {
            Object(
                application: app,
                title: "Install APK",
                modal: true,
                default_width: 520,
                default_height: 560,
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
            box.halign = Gtk.Align.FILL;
            box.hexpand = true;
            box.valign = Gtk.Align.CENTER;
            toolbar.content = box;

            var hint_label = new Gtk.Label("Drag and Drop to install in Applications");
            hint_label.add_css_class("dim-label");
            hint_label.wrap = true;
            hint_label.justify = Gtk.Justification.CENTER;
            box.append(hint_label);

            var icon_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            icon_row.hexpand = true;
            icon_row.halign = Gtk.Align.FILL;
            icon_row.valign = Gtk.Align.CENTER;

            icon_image = new Gtk.Image();
            icon_image.pixel_size = ICON_PX;
            icon_image.width_request = ICON_PX;
            icon_image.height_request = ICON_PX;
            icon_image.halign = Gtk.Align.CENTER;
            icon_image.valign = Gtk.Align.CENTER;
            // Gtk.Image ignores the pointer by default, so a DragSource on it never starts.
            icon_image.can_target = false;

            icon_drag_handle = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            icon_drag_handle.halign = Gtk.Align.START;
            icon_drag_handle.valign = Gtk.Align.START;
            icon_drag_handle.can_target = true;
            icon_drag_handle.add_css_class("apk-install-source");
            icon_drag_handle.tooltip_text = "Drag onto the Applications folder to install";
            icon_drag_handle.set_cursor_from_name("grab");
            ((Gtk.Box) icon_drag_handle).append(icon_image);
            setup_apk_drag_source(icon_drag_handle);
            icon_row.append(icon_drag_handle);

            var icon_spacer_before = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            icon_spacer_before.hexpand = true;
            icon_row.append(icon_spacer_before);

            var install_arrow = new Gtk.Label(">");
            install_arrow.add_css_class("apk-install-arrow");
            install_arrow.halign = Gtk.Align.CENTER;
            install_arrow.valign = Gtk.Align.START;
            install_arrow.margin_top = 4;
            icon_row.append(install_arrow);

            var icon_spacer_after = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            icon_spacer_after.hexpand = true;
            icon_row.append(icon_spacer_after);

            install_folder_button = new Gtk.Button();
            install_folder_button.add_css_class("flat");
            install_folder_button.halign = Gtk.Align.CENTER;
            install_folder_button.valign = Gtk.Align.CENTER;
            install_folder_button.width_request = ICON_PX;
            install_folder_button.height_request = ICON_PX;

            var folder_image = new Gtk.Image.from_icon_name("folder-symbolic");
            folder_image.pixel_size = ICON_PX;
            install_folder_button.child = folder_image;
            var install_path = AppSettings.get_default().get_install_path();
            install_folder_button.tooltip_text = "Open install folder (%s)".printf(install_path);
            install_folder_button.clicked.connect(on_open_install_folder);
            install_folder_button.set_cursor_from_name("pointer");
            setup_install_drop_target(install_folder_button);
            ensure_install_drag_css();

            var install_path_label = new Gtk.Label(display_install_path(install_path));
            install_path_label.add_css_class("caption");
            install_path_label.add_css_class("dim-label");
            install_path_label.wrap = true;
            install_path_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            install_path_label.justify = Gtk.Justification.CENTER;
            install_path_label.halign = Gtk.Align.CENTER;
            install_path_label.max_width_chars = 18;
            install_path_label.width_request = 140;
            install_path_label.tooltip_text = install_path;

            install_folder_column = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            install_folder_column.halign = Gtk.Align.END;
            install_folder_column.valign = Gtk.Align.START;
            ((Gtk.Box) install_folder_column).append(install_folder_button);
            ((Gtk.Box) install_folder_column).append(install_path_label);
            icon_row.append(install_folder_column);

            icon_row.notify["width"].connect((obj, pspec) => {
                update_icon_row_insets((Gtk.Widget) obj);
            });
            icon_row.map.connect(() => {
                update_icon_row_insets(icon_row);
            });
            box.append(icon_row);

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

        private void update_icon_row_insets(Gtk.Widget row) {
            int width = row.get_width();
            if (width <= 0) {
                return;
            }
            int margin = (int) (width * (0.5 - ICON_ROW_CENTER_OFFSET) - ICON_PX / 2.0);
            if (margin < 0) {
                margin = 0;
            }
            icon_drag_handle.margin_start = margin;
            install_folder_column.margin_end = margin;
        }

        private static string display_install_path(string path) {
            var home = Environment.get_home_dir();
            if (home != "" && (path == home || path.has_prefix(home + "/"))) {
                return "~" + path.substring(home.length);
            }
            return path;
        }

        private static bool install_drag_css_installed = false;

        private static void ensure_install_drag_css() {
            if (install_drag_css_installed) {
                return;
            }
            install_drag_css_installed = true;

            var css = new Gtk.CssProvider();
            css.load_from_string("""
                .apk-install-source {
                    border-radius: 16px;
                    padding: 6px;
                }
                .apk-install-source:hover {
                    background-color: alpha(currentColor, 0.12);
                }
                .apk-install-arrow {
                    font-size: 96px;
                    font-weight: 800;
                }
                .apk-install-target.drop-active {
                    background-color: alpha(@accent_bg_color, 0.28);
                    border-radius: 16px;
                }
            """);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private void setup_apk_drag_source(Gtk.Widget widget) {
            var drag_source = new Gtk.DragSource();
            drag_source.actions = Gdk.DragAction.COPY;
            drag_source.prepare.connect(on_apk_drag_prepare);
            drag_source.drag_begin.connect(on_apk_drag_begin);
            widget.add_controller(drag_source);
        }

        private Gdk.ContentProvider? on_apk_drag_prepare(Gtk.DragSource source, double x, double y) {
            if (installing) {
                return null;
            }
            var value = Value(typeof(string));
            value.set_string(apk_path);
            return new Gdk.ContentProvider.for_value(value);
        }

        private void on_apk_drag_begin(Gtk.DragSource source, Gdk.Drag drag) {
            var paintable = icon_image.paintable;
            if (paintable != null) {
                Gtk.DragIcon.set_from_paintable(drag, paintable, ICON_PX / 2, ICON_PX / 2);
            }
        }

        private void setup_install_drop_target(Gtk.Widget widget) {
            widget.add_css_class("apk-install-target");
            var drop_target = new Gtk.DropTarget(typeof(string), Gdk.DragAction.COPY);
            drop_target.preload = true;
            drop_target.enter.connect(on_install_drop_enter);
            drop_target.motion.connect(on_install_drop_motion);
            drop_target.leave.connect(on_install_drop_leave);
            drop_target.drop.connect(on_install_folder_drop);
            widget.add_controller(drop_target);
        }

        private Gdk.DragAction on_install_drop_enter(Gtk.DropTarget target, double x, double y) {
            install_folder_button.add_css_class("drop-active");
            return Gdk.DragAction.COPY;
        }

        private Gdk.DragAction on_install_drop_motion(Gtk.DropTarget target, double x, double y) {
            return Gdk.DragAction.COPY;
        }

        private void on_install_drop_leave(Gtk.DropTarget target) {
            install_folder_button.remove_css_class("drop-active");
        }

        private bool on_install_folder_drop(Gtk.DropTarget target, GLib.Value value, double x, double y) {
            install_folder_button.remove_css_class("drop-active");
            if (installing) {
                return false;
            }

            if (!value.holds(typeof(string))) {
                return false;
            }
            unowned string dropped_path = (string) value;
            if (dropped_path != apk_path) {
                return false;
            }

            perform_install_confirm();
            return true;
        }

        private void perform_install_confirm() {
            var name = ApkDisplayName.resolve(apk_path);
            if (name == null || name.strip() == "") {
                name = Path.get_basename(apk_path);
                if (name.has_suffix(".apk")) {
                    name = name.substring(0, name.length - 4);
                }
            }

            var dialog = new InstallConfirmDialog(name, icon_image.paintable);
            dialog.confirmed.connect(() => {
                perform_install_async.begin();
            });
            dialog.present(this);
        }

        private async void perform_install_async() {
            installing = true;
            icon_progress.visible = true;
            icon_progress.pulse();

            string? installed_path = null;
            Error? error = null;
            try {
                installed_path = yield copy_apk_to_install_folder_async(apk_path);
            } catch (Error e) {
                error = e;
            }

            if (closed) {
                return;
            }

            installing = false;
            icon_progress.visible = false;

            if (installed_path != null) {
                install_requested(installed_path);
                close();
                return;
            }

            subtitle_label.set_text(
                "Install failed: %s".printf(error?.message ?? "Could not copy APK")
            );
        }

        private async string copy_apk_to_install_folder_async(string path) throws Error {
            string? result = null;
            Error? error = null;
            new Thread<void>("apk-install", () => {
                try {
                    result = ApkInstall.install(path);
                } catch (Error e) {
                    error = e;
                }
                Idle.add(copy_apk_to_install_folder_async.callback);
            });
            yield;
            if (error != null) {
                throw error;
            }
            return result;
        }

        private void on_verify_clicked() {
            var verify = new VerifyApkWindow(this, apk_path);
            verify.present();
        }

        private void on_open_install_folder() {
            var install_path = AppSettings.get_default().get_install_path();
            try {
                DirUtils.create_with_parents(install_path, 0755);
                var folder = File.new_for_path(install_path);
                if (!AppInfo.launch_default_for_uri(folder.get_uri(), null)) {
                    warning("Could not open install folder: %s", install_path);
                }
            } catch (Error e) {
                warning("Could not open install folder: %s", e.message);
            }
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
