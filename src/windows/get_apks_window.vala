using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    public class GetApksWindow : Adw.Window {
        public signal void apk_ready(string apk_path);

        private ApkStoreSearch store_search = new ApkStoreSearch();
        private Gtk.SearchEntry search_entry;
        private Gtk.Button search_button;
        private Gtk.Spinner search_spinner;
        private Gtk.Label status_label;
        private Gtk.ListBox results_list;
        private Gtk.ProgressBar download_progress;
        private Gtk.Button download_button;
        private Gtk.DropDown source_filter;
        private Gee.ArrayList<ApkStoreResult> results = new Gee.ArrayList<ApkStoreResult>();
        private ApkStoreResult? selected_result;
        private Cancellable? search_cancellable;
        private Cancellable? download_cancellable;

        public GetApksWindow(Gtk.Window parent) {
            Object(
                transient_for: parent,
                modal: true,
                title: "Get APKs",
                default_width: 720,
                default_height: 560,
                destroy_with_parent: true
            );
            build_ui();
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            header.title_widget = new Adw.WindowTitle("Get APKs", "Search F-Droid, Aptoide, and Uptodown");
            toolbar.add_top_bar(header);

            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            root.margin_top = 12;
            root.margin_bottom = 12;
            root.margin_start = 12;
            root.margin_end = 12;
            root.spacing = 12;
            toolbar.content = root;

            var search_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            search_entry = new Gtk.SearchEntry();
            search_entry.placeholder_text = "Search apps…";
            search_entry.hexpand = true;
            search_entry.search_changed.connect(on_search_changed);
            search_entry.activate.connect(on_search_clicked);
            search_row.append(search_entry);

            search_button = new Gtk.Button.with_label("Search");
            search_button.add_css_class("suggested-action");
            search_button.clicked.connect(on_search_clicked);
            search_row.append(search_button);

            search_spinner = new Gtk.Spinner();
            search_spinner.visible = false;
            search_row.append(search_spinner);
            root.append(search_row);

            var filter_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var filter_label = new Gtk.Label("Show");
            filter_label.add_css_class("dim-label");
            filter_row.append(filter_label);

            var filter_store = new GLib.ListStore(typeof(StoreSourceFilterItem));
            filter_store.append(new StoreSourceFilterItem("All sources"));
            filter_store.append(new StoreSourceFilterItem("F-Droid", "appRepo.fdroid.svg"));
            filter_store.append(new StoreSourceFilterItem("Aptoide", "appRepo.aptoide.svg"));
            filter_store.append(new StoreSourceFilterItem("Uptodown", "appRepo.uptodown.svg"));

            source_filter = new Gtk.DropDown(
                filter_store,
                new Gtk.PropertyExpression(typeof(StoreSourceFilterItem), null, "label")
            );
            source_filter.factory = create_source_filter_factory();
            source_filter.list_factory = create_source_filter_factory();
            source_filter.notify["selected"].connect(on_source_filter_changed);
            filter_row.append(source_filter);
            root.append(filter_row);
            apply_preferred_repository_filter();

            status_label = new Gtk.Label("Search for Android apps to download.");
            status_label.xalign = 0;
            status_label.wrap = true;
            status_label.add_css_class("dim-label");
            root.append(status_label);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.set_vexpand(true);
            scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

            results_list = new Gtk.ListBox();
            results_list.selection_mode = Gtk.SelectionMode.SINGLE;
            results_list.set_placeholder(new Adw.StatusPage() {
                icon_name = "system-search-symbolic",
                title = "No results yet",
                description = "Enter an app name and search F-Droid, Aptoide, and Uptodown."
            });
            results_list.row_selected.connect(on_row_selected);
            results_list.row_activated.connect(on_row_activated);
            scrolled.child = results_list;
            root.append(scrolled);

            download_progress = new Gtk.ProgressBar();
            download_progress.visible = false;
            root.append(download_progress);

            download_button = new Gtk.Button.with_label("Download");
            download_button.sensitive = false;
            download_button.add_css_class("suggested-action");
            download_button.clicked.connect(on_download_clicked);
            root.append(download_button);
        }

        private void apply_preferred_repository_filter() {
            uint selected = 0;
            switch (AppSettings.get_default().get_preferred_repository()) {
            case PreferredRepository.FDROID:
                selected = 1;
                break;
            case PreferredRepository.APTOIDE:
                selected = 2;
                break;
            }
            source_filter.selected = selected;
        }

        private void on_search_changed() {
            download_button.sensitive = false;
            selected_result = null;
        }

        private void on_search_clicked() {
            var query = search_entry.get_text().strip();
            if (query == "") {
                status_label.set_text("Enter a search term first.");
                return;
            }

            if (search_cancellable != null) {
                search_cancellable.cancel();
            }
            search_cancellable = new Cancellable();
            search_spinner.visible = true;
            search_spinner.start();
            search_button.sensitive = false;
            download_button.sensitive = false;
            status_label.set_text("Searching F-Droid, Aptoide, and Uptodown…");
            clear_results();

            run_search.begin(query, search_cancellable);
        }

        private async void run_search(string query, Cancellable cancellable) {
            Gee.List<ApkStoreResult>? found = null;
            Error? error = null;
            try {
                found = yield store_search.search_all(query, cancellable);
            } catch (Error e) {
                error = e;
            }

            if (cancellable.is_cancelled()) {
                return;
            }

            search_spinner.stop();
            search_spinner.visible = false;
            search_button.sensitive = true;

            if (error != null) {
                status_label.set_text("Search failed: %s".printf(error.message));
                return;
            }

            results.clear();
            foreach (var item in found) {
                results.add(item);
            }
            populate_results();

            if (results.size == 0) {
                status_label.set_text("No apps matched “%s”.".printf(query));
            } else {
                status_label.set_text("Found %d result(s) for “%s”.".printf(results.size, query));
            }
        }

        private Gtk.SignalListItemFactory create_source_filter_factory() {
            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect(on_source_filter_item_setup);
            factory.bind.connect(on_source_filter_item_bind);
            return factory;
        }

        private void on_source_filter_item_setup(Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var image = new Gtk.Image();
            image.set_pixel_size(20);
            var label = new Gtk.Label("");
            label.xalign = 0;
            box.append(image);
            box.append(label);
            list_item.set_child(box);
        }

        private void on_source_filter_item_bind(Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item = (StoreSourceFilterItem) list_item.get_item();
            var box = (Gtk.Box) list_item.get_child();
            var image = (Gtk.Image) box.get_first_child();
            var label = (Gtk.Label) box.get_last_child();

            label.label = item.label;
            if (!apply_store_icon(image, item)) {
                image.set_from_icon_name("view-grid-symbolic");
            }
        }

        private bool apply_store_icon(Gtk.Image image, StoreSourceFilterItem item) {
            var resource = item.icon_resource;
            if (resource != null) {
                try {
                    var bytes = GLib.resources_lookup_data(resource, ResourceLookupFlags.NONE);
                    image.set_from_paintable(Gdk.Texture.from_bytes(bytes));
                    return true;
                } catch (Error e) {
                    warning("Could not load store icon %s: %s", resource, e.message);
                }
            }

            var icon_path = item.icon_path;
            if (icon_path != null && FileUtils.test(icon_path, FileTest.EXISTS)) {
                try {
                    image.set_from_paintable(Gdk.Texture.from_filename(icon_path));
                    return true;
                } catch (Error e) {
                    warning("Could not load store icon file %s: %s", icon_path, e.message);
                }
            }
            return false;
        }

        private void on_source_filter_changed() {
            populate_results();
        }

        private ApkStoreSource? active_source_filter() {
            switch (source_filter.get_selected()) {
            case 1:
                return ApkStoreSource.FDROID;
            case 2:
                return ApkStoreSource.APTOIDE;
            case 3:
                return ApkStoreSource.UPTODOWN;
            default:
                return null;
            }
        }

        private void clear_results() {
            Gtk.Widget? child = results_list.get_first_child();
            while (child != null) {
                results_list.remove(child);
                child = results_list.get_first_child();
            }
            selected_result = null;
        }

        private void populate_results() {
            clear_results();
            var filter = active_source_filter();

            foreach (var result in results) {
                if (filter != null && result.source != filter) {
                    continue;
                }
                results_list.append(build_result_row(result));
            }
        }

        private Gtk.ListBoxRow build_result_row(ApkStoreResult result) {
            var row = new Gtk.ListBoxRow();
            row.set_data("result", result);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 8;
            box.margin_end = 8;

            var icon = new Gtk.Image.from_icon_name("application-x-android-package");
            icon.set_pixel_size(48);
            if (result.icon_url != "") {
                load_icon_async.begin(result.icon_url, icon);
            }
            box.append(icon);

            var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            text_box.hexpand = true;

            var title_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var title = new Gtk.Label(result.name);
            title.xalign = 0;
            title.hexpand = true;
            title.add_css_class("title-4");
            title_row.append(title);

            var source_badge = new Gtk.Label(result.source_label);
            source_badge.add_css_class("caption");
            source_badge.add_css_class("dim-label");
            title_row.append(source_badge);
            text_box.append(title_row);

            var subtitle_parts = new Gee.ArrayList<string>();
            if (result.package_id != "") {
                subtitle_parts.add(result.package_id);
            }
            if (result.summary != "") {
                subtitle_parts.add(result.summary);
            }
            if (subtitle_parts.size == 0) {
                subtitle_parts.add(result.page_url);
            }

            var subtitle = new Gtk.Label(string.joinv(" • ", subtitle_parts.to_array()));
            subtitle.xalign = 0;
            subtitle.wrap = true;
            subtitle.add_css_class("dim-label");
            text_box.append(subtitle);

            box.append(text_box);
            row.child = box;
            return row;
        }

        private async void load_icon_async(string url, Gtk.Image image) {
            try {
                var bytes = yield HttpClient.get_bytes(url);
                var texture = Gdk.Texture.from_bytes(bytes);
                image.set_from_paintable(texture);
            } catch (Error e) {
                warning("Failed to load store icon: %s", e.message);
            }
        }

        private void on_row_selected(Gtk.ListBoxRow? row) {
            if (row == null) {
                selected_result = null;
                download_button.sensitive = false;
                return;
            }
            selected_result = row.get_data<ApkStoreResult>("result");
            download_button.sensitive = selected_result != null;
            if (selected_result != null && store_search.requires_browser_download(selected_result)) {
                download_button.label = "Open in browser";
            } else {
                download_button.label = "Download";
            }
        }

        private void on_row_activated(Gtk.ListBoxRow row) {
            on_download_clicked();
        }

        private void on_download_clicked() {
            if (selected_result == null) {
                return;
            }

            if (store_search.requires_browser_download(selected_result)) {
                open_browser_download(selected_result);
                return;
            }

            if (download_cancellable != null) {
                download_cancellable.cancel();
            }
            download_cancellable = new Cancellable();
            download_progress.visible = true;
            download_progress.pulse();
            download_button.sensitive = false;
            status_label.set_text("Downloading %s…".printf(selected_result.name));

            run_download.begin(selected_result, download_cancellable);
        }

        private void open_browser_download(ApkStoreResult result) {
            var url = store_search.browser_download_url(result);
            try {
                GLib.AppInfo.launch_default_for_uri(url, null);
                status_label.set_text(
                    "Opened Uptodown download page in your browser. Save the APK, then open it in ApkManager."
                );
            } catch (Error e) {
                status_label.set_text("Could not open browser: %s".printf(e.message));
            }
        }

        private async void run_download(ApkStoreResult result, Cancellable cancellable) {
            string? path = null;
            Error? error = null;
            try {
                path = yield store_search.download_apk(result, cancellable);
            } catch (Error e) {
                error = e;
            }

            if (cancellable.is_cancelled()) {
                return;
            }

            download_progress.visible = false;
            download_button.sensitive = true;

            if (error != null) {
                status_label.set_text("Download failed: %s".printf(error.message));
                return;
            }

            status_label.set_text("Downloaded to %s".printf(path));
            apk_ready(path);
            close();
        }
    }
}
