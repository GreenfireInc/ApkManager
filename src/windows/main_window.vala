using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    public class MainWindow : Adw.ApplicationWindow {
        private DecodeSessionRegistry registry;
        private ApktoolRunner runner = new ApktoolRunner();
        private DecodeSession? active_session;

        private Adw.StatusPage empty_page;
        private Gtk.ListBox session_list;
        private Gtk.TreeView archive_tree;
        private Gtk.ListStore archive_store;
        private Gtk.Label status_label;
        private Adw.ProgressBar progress_bar;
        private Gtk.Button decode_manifest_button;
        private Gtk.Button decode_full_button;
        private Gtk.Button cancel_button;

        public MainWindow(Adw.Application app, DecodeSessionRegistry registry) {
            Object(application: app, default_width: 960, default_height: 640);
            this.registry = registry;
            title = "ApkManager";
            build_ui();
            refresh_sessions();
        }

        private void build_ui() {
            var split = new Adw.NavigationSplitView();
            content = split;

            var sidebar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            var sidebar_header = new Adw.HeaderBar();
            sidebar_header.title_widget = new Adw.WindowTitle("Sessions", "Recent APKs");
            sidebar_box.append(sidebar_header);

            session_list = new Gtk.ListBox();
            session_list.selection_mode = Gtk.SelectionMode.SINGLE;
            session_list.set_vexpand(true);
            sidebar_box.append(session_list);

            var open_button = new Gtk.Button.with_label("Open APK…");
            open_button.margin_top = 8;
            open_button.margin_bottom = 8;
            open_button.margin_start = 12;
            open_button.margin_end = 12;
            open_button.clicked.connect(on_open_clicked);
            sidebar_box.append(open_button);

            split.sidebar = sidebar_box;

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            var content_header = new Adw.HeaderBar();
            decode_manifest_button = new Gtk.Button.with_label("Quick Manifest");
            decode_full_button = new Gtk.Button.with_label("Full Decode");
            cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.sensitive = false;
            content_header.pack_start(decode_manifest_button);
            content_header.pack_start(decode_full_button);
            content_header.pack_end(cancel_button);
            content_box.append(content_header);

            progress_bar = new Adw.ProgressBar();
            progress_bar.visible = false;
            content_box.append(progress_bar);

            status_label = new Gtk.Label("Open an APK to inspect its contents.");
            status_label.margin_start = 12;
            status_label.margin_end = 12;
            status_label.margin_top = 8;
            status_label.halign = Gtk.Align.START;
            status_label.xalign = 0;
            content_box.append(status_label);

            archive_store = new Gtk.ListStore(typeof(string), typeof(string), typeof(string));
            archive_tree = new Gtk.TreeView.with_model(archive_store);
            archive_tree.set_vexpand(true);

            var col_name = new Gtk.TreeViewColumn.with_attributes("Entry", new Gtk.CellRendererText(), "text", 0);
            var col_size = new Gtk.TreeViewColumn.with_attributes("Size", new Gtk.CellRendererText(), "text", 1);
            var col_kind = new Gtk.TreeViewColumn.with_attributes("Type", new Gtk.CellRendererText(), "text", 2);
            archive_tree.append_column(col_name);
            archive_tree.append_column(col_size);
            archive_tree.append_column(col_kind);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.child = archive_tree;
            scrolled.set_vexpand(true);
            content_box.append(scrolled);

            empty_page = new Adw.StatusPage();
            empty_page.icon_name = "application-x-android-package";
            empty_page.title = "No APK selected";
            empty_page.description = "Open an Android package to browse its raw archive entries and decode with Apktool.";

            var stack = new Adw.ViewStack();
            stack.add_titled(content_box, "content", "Content");
            stack.add_titled(empty_page, "empty", "Empty");
            split.content = stack;

            decode_manifest_button.clicked.connect(() => {
                start_decode(DecodeMode.MANIFEST_ONLY);
            });
            decode_full_button.clicked.connect(() => {
                start_decode(DecodeMode.FULL);
            });
            cancel_button.clicked.connect(() => {
                runner.cancel();
            });

            runner.phase_changed.connect(on_phase_changed);
            runner.finished.connect(on_decode_finished);
        }

        public void open_apk(string apk_path) {
            active_session = registry.get_or_create(apk_path);
            title = "ApkManager — %s".printf(active_session.label ?? Path.get_basename(apk_path));
            status_label.set_text("Loaded %s".printf(apk_path));
            load_archive_entries(apk_path);
            refresh_sessions();
            present();
        }

        private void load_archive_entries(string apk_path) {
            archive_store.clear();
            try {
                var entries = ApkArchive.list_entries(apk_path);
                foreach (var entry in entries) {
                    Gtk.TreeIter iter;
                    archive_store.append(out iter);
                    archive_store.set(iter, 0, entry.path, 1, FileUtilsHelper.format_bytes(entry.uncompressed_size),
                        2, entry.is_directory ? "directory" : "file");
                }
            } catch (Error e) {
                status_label.set_text("Failed to read archive: %s".printf(e.message));
            }
        }

        private void start_decode(DecodeMode mode) {
            if (active_session == null) {
                return;
            }

            if (!runner.java_available) {
                status_label.set_text("Java runtime not found. Install a JRE 17 or newer to decode APKs.");
                return;
            }

            var cache_key = active_session.cache_key(mode);
            var partial_dir = AppPaths.partial_decode_dir(cache_key);
            FileUtilsHelper.remove_tree_if_exists(partial_dir);

            active_session.state = DecodeState.DECODING;
            active_session.last_mode = mode;
            registry.save();

            progress_bar.visible = true;
            progress_bar.pulse();
            cancel_button.sensitive = true;
            decode_manifest_button.sensitive = false;
            decode_full_button.sensitive = false;

            decode_async.begin(active_session, partial_dir, mode, cache_key);
        }

        private async void decode_async(DecodeSession session, string partial_dir, DecodeMode mode, string cache_key) {
            var success = yield runner.decode_async(session.apk_path, partial_dir, mode);
            if (success) {
                var final_dir = AppPaths.decoded_dir_for_key(cache_key);
                FileUtilsHelper.remove_tree_if_exists(final_dir);
                try {
                    DirUtils.create_with_parents(Path.get_dirname(final_dir), 0700);
                    FileUtils.rename(partial_dir, final_dir);
                    session.cache_dir = final_dir;
                    session.state = DecodeState.DECODED;
                } catch (Error e) {
                    session.state = DecodeState.FAILED;
                    status_label.set_text("Failed to finalize cache: %s".printf(e.message));
                }
            } else {
                session.state = DecodeState.FAILED;
                FileUtilsHelper.remove_tree_if_exists(partial_dir);
            }
            registry.save();
        }

        private void on_phase_changed(ApktoolPhase phase, string message) {
            status_label.set_text(message);
        }

        private void on_decode_finished(bool success, string? error_message) {
            progress_bar.visible = false;
            cancel_button.sensitive = false;
            decode_manifest_button.sensitive = true;
            decode_full_button.sensitive = true;

            if (success) {
                status_label.set_text("Decode complete.");
            } else if (error_message != null) {
                status_label.set_text(error_message);
            }
        }

        private void refresh_sessions() {
            while (var child = session_list.get_first_child()) {
                session_list.remove(child);
            }

            foreach (var session in registry.get_sessions()) {
                var row = new Gtk.ListBoxRow();
                var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
                var title = new Gtk.Label(session.label ?? session.apk_path);
                title.xalign = 0;
                title.add_css_class("title-4");
                var subtitle = new Gtk.Label(session.apk_path);
                subtitle.xalign = 0;
                subtitle.add_css_class("dim-label");
                subtitle.ellipsize = Pango.EllipsizeMode.MIDDLE;
                box.append(title);
                box.append(subtitle);
                row.child = box;
                session_list.append(row);
            }
        }

        private void on_open_clicked() {
            var dialog = new Gtk.FileDialog();
            dialog.set_title("Open APK");
            var filter = new Gtk.FileFilter();
            filter.add_pattern("*.apk");
            filter.add_pattern("*.APK");
            filter.set_name("Android packages");
            var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            dialog.set_filters(filters);

            dialog.open.begin(this, null, (obj, res) => {
                try {
                    var file = dialog.open.end(res);
                    open_apk(file.get_path());
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED)) {
                        warning("Open dialog failed: %s", e.message);
                    }
                }
            });
        }
    }
}
