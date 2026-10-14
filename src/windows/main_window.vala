using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    private enum SessionViewMode {
        LIST,
        GRID
    }

    private enum SessionSortMode {
        NAME_ASC,
        NAME_DESC,
        SIZE_ASC,
        SIZE_DESC
    }

    private const int SESSION_GRID_TILE_PX = 96;
    private const int SESSION_GRID_TILE_MARGIN_PX = 8;
    private const int SESSION_GRID_MIN_COLUMNS = 2;

    public class MainWindow : Adw.ApplicationWindow {
        private DecodeSessionRegistry registry;
        private ApktoolRunner runner = new ApktoolRunner();
        private DecodeSession? active_session;

        private Adw.StatusPage empty_page;
        private Gtk.Stack session_stack;
        private Gtk.ListBox session_list;
        private Gtk.FlowBox session_grid;
        private Gtk.ScrolledWindow session_grid_scrolled;
        private Gtk.Button session_view_toggle_button;
        private SessionViewMode session_view_mode = SessionViewMode.GRID;
        private SessionSortMode session_sort_mode = SessionSortMode.NAME_ASC;
        private Gtk.TreeView archive_tree;
        private Gtk.ListStore archive_store;
        private Adw.ViewStack detail_stack;
        private Adw.ViewSwitcher detail_switcher;
        private Gtk.Box properties_content_box;
        private Gtk.Label status_label;
        private Gtk.ProgressBar progress_bar;
        private string status_before_decode = "";
        private Gtk.Button decode_manifest_button;
        private Gtk.Button decode_full_button;
        private Gtk.Button cancel_button;
        private Adw.NavigationSplitView split_view;
        private Adw.ViewStack content_stack;
        private Gtk.SearchEntry session_search;
        private Gtk.Label session_count_label;
        private string session_search_text = "";
        private string[] recent_paths = {};
        private Gtk.PopoverMenu session_context_menu;
        private string[] context_menu_apk_paths = {};
        private bool suppress_session_selection_open = false;
        private bool last_selection_gesture_modified = false;

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
            sidebar_menu_model.append("_Get APKs", "win.get-apks");
            sidebar_menu_model.append("_Preferences", "win.preferences");
            sidebar_menu_model.append("_Quit", "win.quit");
            sidebar_menu.menu_model = sidebar_menu_model;

            var sidebar_actions = new SimpleActionGroup();
            var get_apks_action = new SimpleAction("get-apks", null);
            get_apks_action.activate.connect(on_get_apks_clicked);
            sidebar_actions.add_action(get_apks_action);
            var preferences_action = new SimpleAction("preferences", null);
            preferences_action.activate.connect(on_preferences_clicked);
            sidebar_actions.add_action(preferences_action);
            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => {
                application.quit();
            });
            sidebar_actions.add_action(quit_action);
            var remove_session_action = new SimpleAction("remove-session", null);
            remove_session_action.activate.connect(on_remove_session_from_recents);
            sidebar_actions.add_action(remove_session_action);
            var sort_action = new SimpleAction.stateful(
                "sort-sessions",
                VariantType.STRING,
                new Variant.string("name-asc")
            );
            sort_action.change_state.connect((value) => {
                on_session_sort_changed(sort_action, value);
            });
            sidebar_actions.add_action(sort_action);
            insert_action_group("win", sidebar_actions);

            var session_context_model = new Menu();
            session_context_model.append("_Remove from recents", "win.remove-session");
            session_context_menu = new Gtk.PopoverMenu.from_model(session_context_model);

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
            session_count_label.add_css_class("session-count-link");
            session_count_label.can_target = true;
            session_count_label.set_cursor_from_name("pointer");
            session_count_label.tooltip_text = "Scan install folder for APKs not in recents";
            ensure_session_view_controls_css();

            var count_click = new Gtk.GestureClick();
            count_click.released.connect(() => {
                scan_install_folder_for_missing_apks();
            });
            session_count_label.add_controller(count_click);
            session_status_bar.append(session_count_label);

            var view_controls = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            view_controls.halign = Gtk.Align.END;
            view_controls.valign = Gtk.Align.CENTER;
            view_controls.add_css_class("session-view-controls");
            ensure_session_view_controls_css();

            session_view_toggle_button = new Gtk.Button();
            session_view_toggle_button.add_css_class("flat");
            session_view_toggle_button.clicked.connect(on_session_view_toggle_clicked);
            update_session_view_toggle_icon();
            view_controls.append(session_view_toggle_button);

            var view_separator = new Gtk.Label("|");
            view_separator.add_css_class("dim-label");
            view_separator.valign = Gtk.Align.CENTER;
            view_controls.append(view_separator);

            var sort_menu = new Menu();
            sort_menu.append_item(sort_menu_item("Name (A to Z)", "name-asc"));
            sort_menu.append_item(sort_menu_item("Name (Z to A)", "name-desc"));
            sort_menu.append_item(sort_menu_item("Size (Smallest to Largest)", "size-asc"));
            sort_menu.append_item(sort_menu_item("Size (Largest to Smallest)", "size-desc"));

            var sort_button = new Gtk.MenuButton();
            sort_button.icon_name = "pan-down-symbolic";
            sort_button.tooltip_text = "Reorder recent APKs";
            sort_button.add_css_class("flat");
            sort_button.menu_model = sort_menu;
            view_controls.append(sort_button);
            session_status_bar.append(view_controls);
            sidebar_box.append(session_status_bar);

            session_list = new Gtk.ListBox();
            session_list.selection_mode = Gtk.SelectionMode.MULTIPLE;
            session_list.activate_on_single_click = false;
            session_list.row_activated.connect(on_session_activated);
            session_list.selected_rows_changed.connect(on_session_selection_changed);
            attach_session_selection_gesture(session_list);

            session_grid = new Gtk.FlowBox();
            session_grid.selection_mode = Gtk.SelectionMode.MULTIPLE;
            session_grid.activate_on_single_click = false;
            session_grid.min_children_per_line = SESSION_GRID_MIN_COLUMNS;
            session_grid.max_children_per_line = SESSION_GRID_MIN_COLUMNS;
            session_grid.homogeneous = true;
            session_grid.column_spacing = 8;
            session_grid.row_spacing = 8;
            session_grid.margin_start = 12;
            session_grid.margin_end = 12;
            session_grid.margin_top = 4;
            session_grid.margin_bottom = 4;
            session_grid.child_activated.connect(on_session_grid_activated);
            session_grid.selected_children_changed.connect(on_session_selection_changed);
            attach_session_selection_gesture(session_grid);

            var list_scrolled = new Gtk.ScrolledWindow();
            list_scrolled.set_vexpand(true);
            list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            list_scrolled.child = session_list;

            session_grid_scrolled = new Gtk.ScrolledWindow();
            session_grid_scrolled.set_vexpand(true);
            session_grid_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            session_grid_scrolled.child = session_grid;
            session_grid_scrolled.notify["width"].connect(() => {
                update_session_grid_columns();
            });
            session_grid.map.connect(() => {
                update_session_grid_columns();
            });

            session_stack = new Gtk.Stack();
            session_stack.set_vexpand(true);
            session_stack.add_named(list_scrolled, "list");
            session_stack.add_named(session_grid_scrolled, "grid");
            session_stack.visible_child_name = "grid";
            sidebar_box.append(session_stack);

            var get_apks_button = new Gtk.Button.with_label("Get APKs");
            get_apks_button.margin_top = 8;
            get_apks_button.margin_bottom = 8;
            get_apks_button.margin_start = 12;
            get_apks_button.margin_end = 12;
            get_apks_button.clicked.connect(on_get_apks_clicked);
            sidebar_box.append(get_apks_button);
            sidebar_toolbar.content = sidebar_box;

            split_view.sidebar = new Adw.NavigationPage(sidebar_toolbar, "Sessions");

            var content_toolbar = new Adw.ToolbarView();
            var content_header = new Adw.HeaderBar();
            content_header.title_widget = new Adw.WindowTitle("ApkManager", "");
            content_toolbar.add_top_bar(content_header);

            decode_manifest_button = new Gtk.Button.with_label("Quick Manifest");
            decode_full_button = new Gtk.Button.with_label("Full Decode");

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            archive_store = new Gtk.ListStore.newv({
                typeof(string), typeof(string), typeof(string), typeof(int64)
            });
            archive_tree = new Gtk.TreeView.with_model(archive_store);
            archive_tree.headers_visible = true;
            archive_tree.headers_clickable = true;
            archive_tree.set_vexpand(true);

            var col_name = new Gtk.TreeViewColumn.with_attributes("Entry", new Gtk.CellRendererText(), "text", 0);
            col_name.sort_column_id = 0;
            col_name.resizable = true;
            var col_size = new Gtk.TreeViewColumn.with_attributes("Size", new Gtk.CellRendererText(), "text", 1);
            col_size.sort_column_id = 3;
            col_size.resizable = true;
            var col_kind = new Gtk.TreeViewColumn.with_attributes("Type", new Gtk.CellRendererText(), "text", 2);
            col_kind.sort_column_id = 2;
            col_kind.resizable = true;
            archive_tree.append_column(col_name);
            archive_tree.append_column(col_size);
            archive_tree.append_column(col_kind);

            var files_scrolled = new Gtk.ScrolledWindow();
            files_scrolled.child = archive_tree;
            files_scrolled.set_vexpand(true);
            files_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

            properties_content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            var properties_scrolled = new Gtk.ScrolledWindow();
            properties_scrolled.child = properties_content_box;
            properties_scrolled.set_vexpand(true);
            properties_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

            var decode_buttons_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            decode_buttons_row.margin_top = 12;
            decode_buttons_row.margin_start = 12;
            decode_buttons_row.margin_end = 12;
            decode_buttons_row.margin_bottom = 8;
            decode_buttons_row.halign = Gtk.Align.START;
            decode_buttons_row.append(decode_manifest_button);
            decode_buttons_row.append(decode_full_button);

            var properties_tab_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            properties_tab_box.append(decode_buttons_row);
            properties_tab_box.append(properties_scrolled);

            detail_stack = new Adw.ViewStack();
            detail_stack.add_titled(files_scrolled, "files", "Files");
            detail_stack.add_titled(properties_tab_box, "properties", "Properties");
            detail_stack.set_vexpand(true);
            detail_stack.visible_child_name = "files";

            detail_switcher = new Adw.ViewSwitcher();
            detail_switcher.stack = detail_stack;
            detail_switcher.margin_start = 12;
            detail_switcher.margin_end = 12;
            detail_switcher.margin_top = 6;
            detail_switcher.margin_bottom = 4;
            detail_switcher.halign = Gtk.Align.START;

            content_box.append(detail_switcher);
            content_box.append(detail_stack);

            empty_page = new Adw.StatusPage();
            empty_page.icon_name = "application-x-android-package";
            empty_page.title = "No APK selected";
            empty_page.description = "Open an Android package to browse its raw archive entries and decode with Apktool.";

            content_stack = new Adw.ViewStack();
            content_stack.add_titled(empty_page, "empty", "Empty");
            content_stack.add_titled(content_box, "content", "Content");
            content_stack.visible_child_name = "empty";
            content_toolbar.content = content_stack;

            var status_footer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            status_footer.add_css_class("toolbar");

            progress_bar = new Gtk.ProgressBar();
            progress_bar.visible = false;
            progress_bar.margin_start = 12;
            progress_bar.margin_end = 12;
            progress_bar.margin_top = 6;
            progress_bar.margin_bottom = 0;
            status_footer.append(progress_bar);

            var status_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            status_row.margin_start = 12;
            status_row.margin_end = 12;
            status_row.margin_top = 6;
            status_row.margin_bottom = 6;

            status_label = new Gtk.Label("Open an APK to inspect its contents.");
            status_label.hexpand = true;
            status_label.halign = Gtk.Align.FILL;
            status_label.xalign = 0;
            status_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            status_label.add_css_class("dim-label");
            status_row.append(status_label);

            cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.visible = false;
            cancel_button.sensitive = false;
            cancel_button.halign = Gtk.Align.END;
            cancel_button.valign = Gtk.Align.CENTER;
            status_row.append(cancel_button);
            status_footer.append(status_row);
            content_toolbar.add_bottom_bar(status_footer);

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
            refresh_properties_panel();
            detail_stack.visible_child_name = "files";
            content_stack.visible_child_name = "content";
            split_view.show_content = true;
            refresh_sessions();
            present();
        }

        private void attach_session_selection_gesture(Gtk.Widget widget) {
            var gesture = new Gtk.GestureClick();
            gesture.pressed.connect((n_press, x, y) => {
                var state = gesture.get_current_event_state();
                last_selection_gesture_modified =
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0
                    || (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            });
            widget.add_controller(gesture);
        }

        private string[] collect_selected_session_paths() {
            var paths = new Gee.ArrayList<string>();
            if (session_view_mode == SessionViewMode.LIST) {
                foreach (unowned Gtk.ListBoxRow row in session_list.get_selected_rows()) {
                    var index = row.get_index();
                    if (index >= 0 && index < recent_paths.length) {
                        paths.add(recent_paths[index]);
                    }
                }
            } else {
                foreach (unowned Gtk.FlowBoxChild child in session_grid.get_selected_children()) {
                    var index = child.get_index();
                    if (index >= 0 && index < recent_paths.length) {
                        paths.add(recent_paths[index]);
                    }
                }
            }
            return paths.to_array();
        }

        private void on_session_selection_changed() {
            if (suppress_session_selection_open || last_selection_gesture_modified) {
                return;
            }

            var paths = collect_selected_session_paths();
            if (paths.length != 1) {
                return;
            }

            if (active_session != null && active_session.apk_path == paths[0]) {
                return;
            }

            for (int i = 0; i < recent_paths.length; i++) {
                if (recent_paths[i] == paths[0]) {
                    activate_session_at_index(i);
                    return;
                }
            }
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
            if (session_view_mode == SessionViewMode.GRID) {
                update_session_grid_columns();
            }
        }

        private void update_session_grid_columns() {
            if (session_view_mode != SessionViewMode.GRID) {
                return;
            }

            int width = session_grid_scrolled.get_allocated_width();
            if (width <= 0) {
                return;
            }

            int cell = SESSION_GRID_TILE_PX + SESSION_GRID_TILE_MARGIN_PX;
            int available = width - (int) session_grid.margin_start - (int) session_grid.margin_end;
            int columns = available / cell;
            if (columns < SESSION_GRID_MIN_COLUMNS) {
                columns = SESSION_GRID_MIN_COLUMNS;
            }

            uint column_count = (uint) columns;
            if (session_grid.max_children_per_line != column_count) {
                session_grid.max_children_per_line = column_count;
            }
        }

        private static bool session_view_controls_css_installed = false;

        private static void ensure_session_view_controls_css() {
            if (session_view_controls_css_installed) {
                return;
            }
            session_view_controls_css_installed = true;

            var css = new Gtk.CssProvider();
            css.load_from_string("""
                .session-view-controls button {
                    padding: 2px 4px;
                    min-width: 0;
                    min-height: 0;
                }
                .session-count-link:hover {
                    color: @accent_color;
                }
            """);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private static MenuItem sort_menu_item(string label, string target) {
            var item = new MenuItem(label, null);
            item.set_action_and_target_value("win.sort-sessions", new Variant.string(target));
            return item;
        }

        private void on_session_sort_changed(SimpleAction action, Variant? value) {
            if (value == null) {
                return;
            }
            action.set_state(value);
            switch (value.get_string()) {
            case "name-desc":
                session_sort_mode = SessionSortMode.NAME_DESC;
                break;
            case "size-asc":
                session_sort_mode = SessionSortMode.SIZE_ASC;
                break;
            case "size-desc":
                session_sort_mode = SessionSortMode.SIZE_DESC;
                break;
            default:
                session_sort_mode = SessionSortMode.NAME_ASC;
                break;
            }
            refresh_sessions();
        }

        private int compare_sessions(
            DecodeSession a,
            DecodeSession b,
            Gee.Map<string, string> names,
            Gee.Map<string, int64?> sizes
        ) {
            switch (session_sort_mode) {
            case SessionSortMode.NAME_DESC:
                return names[b.id].collate(names[a.id]);
            case SessionSortMode.SIZE_ASC:
                return compare_int64(sizes[a.id], sizes[b.id]);
            case SessionSortMode.SIZE_DESC:
                return compare_int64(sizes[b.id], sizes[a.id]);
            default:
                return names[a.id].collate(names[b.id]);
            }
        }

        private static int compare_int64(int64 a, int64 b) {
            if (a < b) {
                return -1;
            }
            if (a > b) {
                return 1;
            }
            return 0;
        }

        private static int64 apk_file_size_bytes(string path) {
            try {
                var info = File.new_for_path(path).query_info(
                    FileAttribute.STANDARD_SIZE,
                    FileQueryInfoFlags.NONE,
                    null
                );
                return info.get_size();
            } catch (Error e) {
                return -1;
            }
        }

        private void attach_session_context_menu(Gtk.Widget widget, string apk_path) {
            var gesture = new Gtk.GestureClick();
            // Default is the primary button, so a right click never emits pressed.
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            gesture.pressed.connect((n_press, x, y) => {
                var selected = collect_selected_session_paths();
                var in_selection = false;
                foreach (var path in selected) {
                    if (path == apk_path) {
                        in_selection = true;
                        break;
                    }
                }

                if (in_selection && selected.length > 0) {
                    context_menu_apk_paths = selected;
                } else {
                    context_menu_apk_paths = { apk_path };
                    suppress_session_selection_open = true;
                    if (widget is Gtk.ListBoxRow) {
                        var row = (Gtk.ListBoxRow) widget;
                        session_list.select_row(null);
                        session_list.select_row(row);
                    } else if (widget is Gtk.FlowBoxChild) {
                        var child = (Gtk.FlowBoxChild) widget;
                        session_grid.unselect_all();
                        session_grid.select_child(child);
                    }
                    suppress_session_selection_open = false;
                }

                var parent = session_context_menu.get_parent();
                if (parent != null) {
                    session_context_menu.unparent();
                }
                session_context_menu.set_parent(widget);
                session_context_menu.has_arrow = false;
                session_context_menu.popup();
            });
            widget.add_controller(gesture);
        }

        private void on_remove_session_from_recents() {
            if (context_menu_apk_paths.length == 0) {
                return;
            }
            var apk_paths = context_menu_apk_paths;
            context_menu_apk_paths = {};

            string title_name;
            Gdk.Paintable? icon = null;
            if (apk_paths.length == 1) {
                title_name = ApkDisplayName.resolve(apk_paths[0]) ?? Path.get_basename(apk_paths[0]);
                icon = UiUtils.load_session_icon_paintable(apk_paths[0]);
            } else {
                title_name = "%d APKs".printf(apk_paths.length);
            }

            var dialog = new RemoveSessionConfirmDialog(title_name, icon, apk_paths.length);
            dialog.confirmed.connect(() => {
                remove_recent_sessions(apk_paths);
            });
            dialog.delete_confirmed.connect(() => {
                remove_recent_sessions_and_delete_files(apk_paths);
            });
            dialog.present(this);
        }

        private void remove_recent_sessions_and_delete_files(string[] apk_paths) {
            remove_recent_sessions(apk_paths);

            int deleted = 0;
            var failures = new Gee.ArrayList<string>();
            foreach (var path in apk_paths) {
                try {
                    File.new_for_path(path).delete();
                    deleted++;
                } catch (Error e) {
                    failures.add("%s: %s".printf(path, e.message));
                }
            }

            if (failures.size == 0) {
                if (deleted == 1) {
                    status_label.set_text("Deleted 1 APK from disk");
                } else {
                    status_label.set_text("Deleted %d APKs from disk".printf(deleted));
                }
            } else if (deleted == 0) {
                status_label.set_text("Could not delete selected APKs");
            } else {
                status_label.set_text(
                    "Deleted %d APKs; %d could not be deleted".printf(deleted, failures.size)
                );
            }
        }

        private void remove_recent_sessions(string[] apk_paths) {
            bool active_removed = false;
            foreach (var path in apk_paths) {
                registry.remove_by_apk_path(path);
                if (active_session != null && active_session.apk_path == path) {
                    active_removed = true;
                }
            }

            if (active_removed) {
                active_session = null;
                title = "ApkManager";
                archive_store.clear();
                content_stack.visible_child_name = "empty";
                status_label.set_text("Open an APK to inspect its contents.");
            } else if (apk_paths.length == 1) {
                status_label.set_text("Removed from recents");
            } else {
                status_label.set_text("Removed %d APKs from recents".printf(apk_paths.length));
            }
            refresh_sessions();
        }

        private Gtk.Widget build_session_grid_tile(string apk_path, string name) {
            var tile = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            tile.width_request = SESSION_GRID_TILE_PX;
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

            var size_label = new Gtk.Label(session_apk_file_size(apk_path));
            size_label.xalign = 0.5f;
            size_label.justify = Gtk.Justification.CENTER;
            size_label.add_css_class("dim-label");
            tile.append(size_label);

            return tile;
        }

        private string session_apk_file_size(string apk_path) {
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

            var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;
            text_box.halign = Gtk.Align.FILL;

            var title = new Gtk.Label(name);
            title.xalign = 0;
            title.hexpand = true;
            title.add_css_class("title-4");
            title.ellipsize = Pango.EllipsizeMode.MIDDLE;
            text_box.append(title);

            var size_label = new Gtk.Label(session_apk_file_size(apk_path));
            size_label.xalign = 0;
            size_label.add_css_class("dim-label");
            text_box.append(size_label);

            row_box.append(text_box);

            return row_box;
        }

        private void clear_box_children(Gtk.Box box) {
            Gtk.Widget? child = box.get_first_child();
            while (child != null) {
                box.remove(child);
                child = box.get_first_child();
            }
        }

        private bool session_has_decoded_manifest(DecodeSession session) {
            if (session.cache_dir == null) {
                return false;
            }
            var manifest = Path.build_filename(session.cache_dir, "AndroidManifest.xml");
            var yml = Path.build_filename(session.cache_dir, "apktool.yml");
            return FileUtils.test(manifest, FileTest.EXISTS)
                || FileUtils.test(yml, FileTest.EXISTS);
        }

        private void refresh_properties_panel() {
            clear_box_children(properties_content_box);

            if (active_session == null || !session_has_decoded_manifest(active_session)) {
                var empty = new Adw.StatusPage();
                empty.icon_name = "text-x-generic";
                empty.title = "No manifest yet";
                empty.description = "Run Quick Manifest to view application properties.";
                properties_content_box.append(empty);
                return;
            }

            try {
                var meta = ApkMetadata.from_decode_dir(active_session.cache_dir);
                properties_content_box.append(
                    ManifestPopup.build_properties_view(active_session.apk_path, meta)
                );
            } catch (Error e) {
                var error_page = new Adw.StatusPage();
                error_page.icon_name = "dialog-warning";
                error_page.title = "Could not read manifest";
                error_page.description = e.message;
                properties_content_box.append(error_page);
            }
        }

        private void show_properties_tab() {
            refresh_properties_panel();
            detail_stack.visible_child_name = "properties";
        }

        private void load_archive_entries(string apk_path) {
            archive_store.clear();
            try {
                var entries = ApkArchive.list_entries(apk_path);
                foreach (var entry in entries) {
                    Gtk.TreeIter iter;
                    archive_store.append(out iter);
                    archive_store.set(
                        iter,
                        0, entry.path,
                        1, FileUtilsHelper.format_bytes(entry.uncompressed_size),
                        2, entry.is_directory ? "directory" : "file",
                        3, entry.uncompressed_size
                    );
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

            status_before_decode = status_label.get_text();
            progress_bar.visible = true;
            progress_bar.pulse();
            if (mode == DecodeMode.FULL) {
                cancel_button.visible = true;
                cancel_button.sensitive = true;
            } else {
                cancel_button.visible = false;
                cancel_button.sensitive = false;
            }
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
                        try {
                            var meta = ApkMetadata.from_decode_dir(final_dir);
                            session.label = meta.display_name(session.apk_path);
                            refresh_sessions();
                        } catch (Error e) {
                            warning("Could not read manifest metadata: %s", e.message);
                        }
                        show_properties_tab();
                    } else {
                        refresh_properties_panel();
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

        private void on_phase_changed(ApktoolPhase phase, string message) {
            status_label.set_text(message);
        }

        private void on_decode_finished(bool success, string? error_message) {
            progress_bar.visible = false;
            cancel_button.visible = false;
            cancel_button.sensitive = false;
            decode_manifest_button.sensitive = true;
            decode_full_button.sensitive = true;

            if (success) {
                status_label.set_text(status_before_decode);
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
            int64 total_bytes = 0;
            foreach (var session in registry.get_sessions()) {
                var size = apk_file_size_bytes(session.apk_path);
                if (size >= 0) {
                    total_bytes += size;
                }
            }
            var size_text = FileUtilsHelper.format_bytes(total_bytes);
            if (total == 1) {
                session_count_label.set_text("1 APK (%s)".printf(size_text));
            } else {
                session_count_label.set_text("%d APKs (%s)".printf(total, size_text));
            }
        }

        private bool is_apk_in_recents(string apk_path) {
            foreach (var session in registry.get_sessions()) {
                if (session.apk_path == apk_path) {
                    return true;
                }
            }
            return false;
        }

        private void scan_install_folder_for_missing_apks() {
            var install_dir = AppSettings.get_default().get_install_path();
            if (!FileUtils.test(install_dir, FileTest.IS_DIR)) {
                status_label.set_text("Install folder not found: %s".printf(install_dir));
                return;
            }

            int added = 0;
            try {
                var dir = Dir.open(install_dir, 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (name == "." || name == "..") {
                        continue;
                    }
                    var path = Path.build_filename(install_dir, name);
                    if (!FileUtils.test(path, FileTest.IS_REGULAR)) {
                        continue;
                    }
                    if (!ApkArchive.is_apk_path(path)) {
                        continue;
                    }
                    if (is_apk_in_recents(path)) {
                        continue;
                    }
                    registry.get_or_create(path);
                    added++;
                }
            } catch (FileError e) {
                status_label.set_text("Could not scan %s: %s".printf(install_dir, e.message));
                return;
            }

            refresh_sessions();
            if (added == 0) {
                status_label.set_text("No new APKs found in %s".printf(install_dir));
            } else if (added == 1) {
                status_label.set_text("Added 1 APK from %s".printf(install_dir));
            } else {
                status_label.set_text("Added %d APKs from %s".printf(added, install_dir));
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
            var active_path = active_session?.apk_path;
            var paths_to_select = new Gee.HashSet<string>();
            foreach (var path in collect_selected_session_paths()) {
                paths_to_select.add(path);
            }
            if (paths_to_select.size == 0 && active_path != null) {
                paths_to_select.add(active_path);
            }

            clear_session_list_rows();
            clear_session_grid_children();

            update_session_count_label();

            recent_paths = {};
            var labels_dirty = false;
            var rows_to_select = new Gee.ArrayList<Gtk.ListBoxRow>();
            var grid_children_to_select = new Gee.ArrayList<Gtk.FlowBoxChild>();

            var visible = new Gee.ArrayList<DecodeSession>();
            var names = new Gee.HashMap<string, string>();
            var sizes = new Gee.HashMap<string, int64?>();
            foreach (var session in registry.get_sessions()) {
                var previous_label = session.label;
                var name = ApkDisplayName.for_session(session);
                if (session.label != previous_label) {
                    labels_dirty = true;
                }
                if (!session_matches_search(session)) {
                    continue;
                }
                visible.add(session);
                names[session.id] = name;
                sizes[session.id] = apk_file_size_bytes(session.apk_path);
            }

            visible.sort((a, b) => compare_sessions(a, b, names, sizes));

            foreach (var session in visible) {
                var name = names[session.id];
                recent_paths += session.apk_path;

                if (session_view_mode == SessionViewMode.LIST) {
                    var row = new Gtk.ListBoxRow();
                    row.child = build_session_list_row(session.apk_path, name);
                    attach_session_context_menu(row, session.apk_path);
                    session_list.append(row);
                    if (paths_to_select.contains(session.apk_path)) {
                        rows_to_select.add(row);
                    }
                } else {
                    var grid_item = new Gtk.FlowBoxChild();
                    grid_item.child = build_session_grid_tile(session.apk_path, name);
                    attach_session_context_menu(grid_item, session.apk_path);
                    session_grid.append(grid_item);
                    if (paths_to_select.contains(session.apk_path)) {
                        grid_children_to_select.add(grid_item);
                    }
                }
            }

            if (labels_dirty) {
                registry.save();
            }

            suppress_session_selection_open = true;
            if (session_view_mode == SessionViewMode.LIST) {
                session_stack.visible_child_name = "list";
                session_list.select_row(null);
                foreach (var row in rows_to_select) {
                    session_list.select_row(row);
                }
            } else {
                session_stack.visible_child_name = "grid";
                update_session_grid_columns();
                session_grid.unselect_all();
                foreach (var child in grid_children_to_select) {
                    session_grid.select_child(child);
                }
            }
            suppress_session_selection_open = false;
        }

        private void on_get_apks_clicked() {
            var window = new GetApksWindow(this);
            window.apk_ready.connect((path) => {
                open_apk(path);
            });
            window.present();
        }

        private void on_preferences_clicked() {
            var window = new PreferencesWindow(this);
            window.present();
        }
    }
}
