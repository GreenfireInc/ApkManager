using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    private enum SessionViewMode {
        LIST,
        GRID
    }

    public class MainWindow : Adw.ApplicationWindow {
        private DecodeSessionRegistry registry;
        private ApktoolRunner runner = new ApktoolRunner();
        private DecodeSession? active_session;

        private Adw.StatusPage empty_page;
        private Gtk.Stack session_stack;
        private Gtk.ListBox session_list;
        private Gtk.FlowBox session_grid;
        private Gtk.Button session_view_toggle_button;
        private SessionViewMode session_view_mode = SessionViewMode.LIST;
        private Gtk.TreeView archive_tree;
        private Gtk.ListStore archive_store;
        private Gtk.Label status_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.Button decode_manifest_button;
        private Gtk.Button decode_full_button;
        private Gtk.Button cancel_button;
        private Adw.NavigationSplitView split_view;
        private Adw.ViewStack content_stack;
        private Gtk.SearchEntry session_search;
        private Gtk.Label session_count_label;
        private string session_search_text = "";
        private string[] recent_paths = {};

        public MainWindow(Adw.Application app, DecodeSessionRegistry registry) {
            Object(application: app, default_width: 960, default_height: 640);
            this.registry = registry;
            title = "ApkManager";
            build_ui();
            refresh_sessions();
        }

        private void build_ui() {
            split_view = new Adw.NavigationSplitView();
            content = split_view;

            var sidebar_toolbar = new Adw.ToolbarView();
            var sidebar_header = new Adw.HeaderBar();
            sidebar_header.show_title = false;

            var sidebar_menu = new Gtk.MenuButton();
            sidebar_menu.icon_name = "open-menu-symbolic";
            sidebar_menu.tooltip_text = "Menu";
            sidebar_menu.add_css_class("flat");

            var sidebar_menu_model = new Menu();
            sidebar_menu_model.append("_Open APK…", "win.open-apk");
            sidebar_menu_model.append("_Quit", "win.quit");
            sidebar_menu.menu_model = sidebar_menu_model;

            var sidebar_actions = new SimpleActionGroup();
            var open_apk_action = new SimpleAction("open-apk", null);
            open_apk_action.activate.connect(on_open_clicked);
            sidebar_actions.add_action(open_apk_action);
            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => {
                application.quit();
            });
            sidebar_actions.add_action(quit_action);
            insert_action_group("win", sidebar_actions);

            sidebar_header.pack_start(sidebar_menu);

            session_search = new Gtk.SearchEntry();
            session_search.placeholder_text = "Search recent APKs";
            session_search.hexpand = true;
            session_search.halign = Gtk.Align.FILL;
            session_search.margin_start = 0;
            session_search.margin_end = 6;
            session_search.search_changed.connect(on_session_search_changed);
            sidebar_header.pack_start(session_search);

            sidebar_toolbar.add_top_bar(sidebar_header);

            var sidebar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            var session_status_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            session_status_bar.margin_start = 12;
            session_status_bar.margin_end = 12;
            session_status_bar.margin_top = 6;
            session_status_bar.margin_bottom = 4;

            session_count_label = new Gtk.Label("");
            session_count_label.xalign = 0;
            session_count_label.hexpand = true;
            session_count_label.halign = Gtk.Align.START;
            session_count_label.add_css_class("dim-label");
            session_status_bar.append(session_count_label);

            session_view_toggle_button = new Gtk.Button();
            session_view_toggle_button.add_css_class("flat");
            session_view_toggle_button.clicked.connect(on_session_view_toggle_clicked);
            update_session_view_toggle_icon();
            session_status_bar.append(session_view_toggle_button);
            sidebar_box.append(session_status_bar);

            session_list = new Gtk.ListBox();
            session_list.selection_mode = Gtk.SelectionMode.SINGLE;
            session_list.activate_on_single_click = true;
            session_list.row_activated.connect(on_session_activated);

            session_grid = new Gtk.FlowBox();
            session_grid.selection_mode = Gtk.SelectionMode.SINGLE;
            session_grid.activate_on_single_click = true;
            session_grid.max_children_per_line = 2;
            session_grid.column_spacing = 8;
            session_grid.row_spacing = 8;
            session_grid.margin_start = 12;
            session_grid.margin_end = 12;
            session_grid.margin_top = 4;
            session_grid.margin_bottom = 4;
            session_grid.child_activated.connect(on_session_grid_activated);

            var list_scrolled = new Gtk.ScrolledWindow();
            list_scrolled.set_vexpand(true);
            list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            list_scrolled.child = session_list;

            var grid_scrolled = new Gtk.ScrolledWindow();
            grid_scrolled.set_vexpand(true);
            grid_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            grid_scrolled.child = session_grid;

            session_stack = new Gtk.Stack();
            session_stack.set_vexpand(true);
            session_stack.add_named(list_scrolled, "list");
            session_stack.add_named(grid_scrolled, "grid");
            session_stack.visible_child_name = "list";
            sidebar_box.append(session_stack);

            var open_button = new Gtk.Button.with_label("Open APK…");
            open_button.margin_top = 8;
            open_button.margin_bottom = 8;
            open_button.margin_start = 12;
            open_button.margin_end = 12;
            open_button.clicked.connect(on_open_clicked);
            sidebar_box.append(open_button);
            sidebar_toolbar.content = sidebar_box;

            split_view.sidebar = new Adw.NavigationPage(sidebar_toolbar, "Sessions");

            var content_toolbar = new Adw.ToolbarView();
            var content_header = new Adw.HeaderBar();
            decode_manifest_button = new Gtk.Button.with_label("Quick Manifest");
            decode_full_button = new Gtk.Button.with_label("Full Decode");
            cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.sensitive = false;
            content_header.pack_start(decode_manifest_button);
            content_header.pack_start(decode_full_button);
            content_header.pack_start(cancel_button);
            content_header.title_widget = new Adw.WindowTitle("ApkManager", "");
            content_toolbar.add_top_bar(content_header);

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            progress_bar = new Gtk.ProgressBar();
            progress_bar.visible = false;
            content_box.append(progress_bar);

            status_label = new Gtk.Label("Open an APK to inspect its contents.");
            status_label.margin_start = 12;
            status_label.margin_end = 12;
            status_label.margin_top = 8;
            status_label.halign = Gtk.Align.START;
            status_label.xalign = 0;
            status_label.wrap = true;
            status_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            status_label.max_width_chars = 80;
            content_box.append(status_label);

            archive_store = new Gtk.ListStore.newv({typeof(string), typeof(string), typeof(string)});
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

            content_stack = new Adw.ViewStack();
            content_stack.add_titled(empty_page, "empty", "Empty");
            content_stack.add_titled(content_box, "content", "Content");
            content_stack.visible_child_name = "empty";
            content_toolbar.content = content_stack;
            split_view.content = new Adw.NavigationPage(content_toolbar, "ApkManager");

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
            active_session.label = ApkDisplayName.for_session(active_session);
            registry.save();
            title = "ApkManager — %s".printf(active_session.label ?? Path.get_basename(apk_path));
            status_label.set_text("Loaded %s".printf(apk_path));
            load_archive_entries(apk_path);
            content_stack.visible_child_name = "content";
            split_view.show_content = true;
            refresh_sessions();
            present();
        }

        private void on_session_activated(Gtk.ListBoxRow row) {
            activate_session_at_index(row.get_index());
        }

        private void on_session_grid_activated(Gtk.FlowBox box, Gtk.FlowBoxChild child) {
            activate_session_at_index(child.get_index());
        }

        private void activate_session_at_index(int index) {
            if (index < 0 || index >= recent_paths.length) {
                return;
            }
            var path = recent_paths[index];
            if (!FileUtils.test(path, FileTest.IS_REGULAR)) {
                status_label.set_text("That APK is no longer at %s".printf(path));
                content_stack.visible_child_name = "content";
                split_view.show_content = true;
                return;
            }
            open_apk(path);
        }

        private void update_session_view_toggle_icon() {
            if (session_view_mode == SessionViewMode.LIST) {
                session_view_toggle_button.icon_name = "view-grid-symbolic";
                session_view_toggle_button.tooltip_text = "Switch to grid view";
            } else {
                session_view_toggle_button.icon_name = "view-list-symbolic";
                session_view_toggle_button.tooltip_text = "Switch to list view";
            }
        }

        private void on_session_view_toggle_clicked() {
            if (session_view_mode == SessionViewMode.LIST) {
                session_view_mode = SessionViewMode.GRID;
            } else {
                session_view_mode = SessionViewMode.LIST;
            }
            update_session_view_toggle_icon();
            refresh_sessions();
        }

        private Gtk.Widget build_session_grid_tile(string apk_path, string name) {
            var tile = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            tile.width_request = 96;
            tile.margin_top = 8;
            tile.margin_bottom = 8;
            tile.margin_start = 4;
            tile.margin_end = 4;
            tile.halign = Gtk.Align.CENTER;

            tile.append(UiUtils.load_session_apk_icon(apk_path, UiUtils.SESSION_GRID_ICON_PX));

            var label = new Gtk.Label(name);
            label.xalign = 0.5f;
            label.justify = Gtk.Justification.CENTER;
            label.wrap = true;
            label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.max_width_chars = 14;
            label.add_css_class("title-4");
            tile.append(label);

            var size_label = new Gtk.Label(grid_tile_file_size(apk_path));
            size_label.xalign = 0.5f;
            size_label.justify = Gtk.Justification.CENTER;
            size_label.add_css_class("dim-label");
            tile.append(size_label);

            return tile;
        }

        private string grid_tile_file_size(string apk_path) {
            try {
                var file = File.new_for_path(apk_path);
                var info = file.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE, null);
                return FileUtilsHelper.format_bytes(info.get_size());
            } catch (Error e) {
                return "—";
            }
        }

        private Gtk.Widget build_session_list_row(string apk_path, string name) {
            var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            row_box.margin_top = 6;
            row_box.margin_bottom = 6;
            row_box.margin_start = 12;
            row_box.margin_end = 12;
            row_box.append(UiUtils.load_session_apk_icon(apk_path, UiUtils.SESSION_LIST_ICON_PX));

            var title = new Gtk.Label(name);
            title.xalign = 0;
            title.hexpand = true;
            title.add_css_class("title-4");
            title.ellipsize = Pango.EllipsizeMode.MIDDLE;
            row_box.append(title);

            return row_box;
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
                    if (mode == DecodeMode.MANIFEST_ONLY) {
                        show_manifest_popup(session.apk_path, final_dir);
                    }
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

        private void show_manifest_popup(string apk_path, string decode_dir) {
            try {
                var meta = ApkMetadata.from_decode_dir(decode_dir);
                if (active_session != null) {
                    active_session.label = meta.display_name(apk_path);
                    registry.save();
                }
                var popup = new ManifestPopup(this, apk_path, meta);
                popup.present();
                status_label.set_text("Manifest ready.");
            } catch (Error e) {
                status_label.set_text("Decoded, but metadata could not be read: %s".printf(e.message));
            }
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

        private void on_session_search_changed(Gtk.SearchEntry entry) {
            session_search_text = entry.get_text().down();
            refresh_sessions();
        }

        private bool session_matches_search(DecodeSession session) {
            if (session_search_text.length == 0) {
                return true;
            }
            var needle = session_search_text;
            if (session.label != null && session.label.down().contains(needle)) {
                return true;
            }
            if (session.apk_path.down().contains(needle)) {
                return true;
            }
            return Path.get_basename(session.apk_path).down().contains(needle);
        }

        private void update_session_count_label() {
            var total = registry.get_sessions().size;
            if (total == 1) {
                session_count_label.set_text("1 APK");
            } else {
                session_count_label.set_text("%d APKs".printf(total));
            }
        }

        private void clear_session_list_rows() {
            Gtk.Widget? child = session_list.get_first_child();
            while (child != null) {
                session_list.remove(child);
                child = session_list.get_first_child();
            }
        }

        private void clear_session_grid_children() {
            Gtk.Widget? child = session_grid.get_first_child();
            while (child != null) {
                session_grid.remove(child);
                child = session_grid.get_first_child();
            }
        }

        private void refresh_sessions() {
            clear_session_list_rows();
            clear_session_grid_children();

            update_session_count_label();

            recent_paths = {};
            var labels_dirty = false;
            var active_path = active_session?.apk_path;
            Gtk.ListBoxRow? selected_row = null;
            Gtk.FlowBoxChild? selected_grid_child = null;

            foreach (var session in registry.get_sessions()) {
                var previous_label = session.label;
                var name = ApkDisplayName.for_session(session);
                if (session.label != previous_label) {
                    labels_dirty = true;
                }
                if (!session_matches_search(session)) {
                    continue;
                }
                recent_paths += session.apk_path;

                if (session_view_mode == SessionViewMode.LIST) {
                    var row = new Gtk.ListBoxRow();
                    row.child = build_session_list_row(session.apk_path, name);
                    session_list.append(row);
                    if (active_path != null && session.apk_path == active_path) {
                        selected_row = row;
                    }
                } else {
                    var grid_item = new Gtk.FlowBoxChild();
                    grid_item.child = build_session_grid_tile(session.apk_path, name);
                    session_grid.append(grid_item);
                    if (active_path != null && session.apk_path == active_path) {
                        selected_grid_child = grid_item;
                    }
                }
            }

            if (labels_dirty) {
                registry.save();
            }

            if (session_view_mode == SessionViewMode.LIST) {
                session_stack.visible_child_name = "list";
                if (selected_row != null) {
                    session_list.select_row(selected_row);
                } else {
                    session_list.unselect_all();
                }
            } else {
                session_stack.visible_child_name = "grid";
                if (selected_grid_child != null) {
                    session_grid.select_child(selected_grid_child);
                } else {
                    session_grid.unselect_all();
                }
            }
        }

        private void on_open_clicked() {
            var dialog = new Gtk.FileDialog();
            dialog.set_title("Open APK");
            var filter = new Gtk.FileFilter();
            filter.add_pattern("*.apk");
            filter.add_pattern("*.APK");
            filter.set_filter_name("Android packages");
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
