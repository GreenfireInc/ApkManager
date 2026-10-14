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
        private bool selected_already_installed = false;
        private Cancellable? search_cancellable;
        private Cancellable? download_cancellable;
        private Cancellable? install_check_cancellable;

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
            header.title_widget = new Adw.WindowTitle("Get APKs", "Search F-Droid, Aptoide, IzzyOnDroid, OpenAPK, and Uptodown");
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
            filter_store.append(new StoreSourceFilterItem("All Sources"));
            filter_store.append(new StoreSourceFilterItem("Aptoide", "appRepo.aptoide.svg"));
            filter_store.append(new StoreSourceFilterItem("F-Droid", "appRepo.fdroid.svg"));
            filter_store.append(new StoreSourceFilterItem("IzzyOnDroid", "appRepo.Izzy.svg"));
            filter_store.append(new StoreSourceFilterItem("OpenAPK", "appRepo.openapk.svg"));
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
                description = "Enter an app name and search F-Droid, Aptoide, IzzyOnDroid, OpenAPK, and Uptodown."
            });
            results_list.row_selected.connect(on_row_selected);
            results_list.row_activated.connect(on_row_activated);
            scrolled.child = results_list;
            root.append(scrolled);

            download_progress = new Gtk.ProgressBar();
            download_progress.visible = false;
            root.append(download_progress);

            download_button = new Gtk.Button.with_label("Download and install");
            download_button.sensitive = false;
            download_button.add_css_class("suggested-action");
            download_button.clicked.connect(on_download_clicked);
            root.append(download_button);
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
            status_label.set_text("Searching F-Droid, Aptoide, IzzyOnDroid, OpenAPK, and Uptodown…");
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

        private bool apply_repository_icon(Gtk.Image image, ApkStoreResult result) {
            var basename = result.repository_icon_basename;
            if (basename == "") {
                return false;
            }
            return apply_store_icon(image, new StoreSourceFilterItem(result.source_label, basename));
        }

        private void on_source_filter_changed() {
            populate_results();
        }

        private ApkStoreSource? active_source_filter() {
            switch (source_filter.get_selected()) {
            case 1:
                return ApkStoreSource.APTOIDE;
            case 2:
                return ApkStoreSource.FDROID;
            case 3:
                return ApkStoreSource.IZZYONDROID;
            case 4:
                return ApkStoreSource.OPENAPK;
            case 5:
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

            var title_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            title_row.hexpand = true;

            var title = new Gtk.Label(result.name);
            title.xalign = 0;
            title.add_css_class("title-4");
            title_row.append(title);

            if (result.version_suffix != "") {
                var version_label = new Gtk.Label(result.version_suffix);
                version_label.xalign = 0;
                version_label.valign = Gtk.Align.BASELINE;
                version_label.add_css_class("caption");
                version_label.add_css_class("dim-label");
                title_row.append(version_label);
            }

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

            if (active_source_filter() == null) {
                var source_column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
                source_column.halign = Gtk.Align.END;
                source_column.valign = Gtk.Align.CENTER;
                source_column.margin_start = 8;

                var source_icon = new Gtk.Image();
                source_icon.set_pixel_size(20);
                source_icon.halign = Gtk.Align.CENTER;
                if (!apply_repository_icon(source_icon, result)) {
                    source_icon.set_from_icon_name("view-grid-symbolic");
                }
                source_column.append(source_icon);

                var source_label = new Gtk.Label(result.source_label);
                source_label.add_css_class("caption");
                source_label.add_css_class("dim-label");
                source_label.halign = Gtk.Align.CENTER;
                source_column.append(source_label);

                box.append(source_column);
            }

            row.child = box;
            return row;
        }

        private async void load_icon_async(string url, Gtk.Image image) {
            try {
                var bytes = yield HttpClient.get_bytes(url, HttpClient.BROWSER_USER_AGENT);
                if (!HttpClient.looks_like_image(bytes)) {
                    warning("Store icon URL returned non-image data: %s", url);
                    return;
                }
                var texture = Gdk.Texture.from_bytes(bytes);
                image.set_from_paintable(texture);
            } catch (Error e) {
                warning("Failed to load store icon: %s", e.message);
            }
        }

        private void on_row_selected(Gtk.ListBoxRow? row) {
            if (install_check_cancellable != null) {
                install_check_cancellable.cancel();
            }

            if (row == null) {
                selected_result = null;
                selected_already_installed = false;
                download_button.sensitive = false;
                return;
            }

            selected_result = row.get_data<ApkStoreResult>("result");
            selected_already_installed = false;
            update_download_button_for_selection();

            if (selected_result == null || store_search.requires_browser_download(selected_result)) {
                return;
            }

            install_check_cancellable = new Cancellable();
            check_selected_install_state.begin(selected_result, install_check_cancellable);
        }

        private void update_download_button_for_selection() {
            if (selected_result == null) {
                download_button.sensitive = false;
                return;
            }

            if (selected_already_installed) {
                download_button.sensitive = false;
                download_button.label = "Already installed";
                return;
            }

            download_button.sensitive = true;
            if (store_search.requires_browser_download(selected_result)) {
                download_button.label = "Open in browser";
            } else {
                download_button.label = "Download and install";
            }
        }

        private async void check_selected_install_state(ApkStoreResult result, Cancellable cancellable) {
            bool installed = false;
            Error? error = null;
            try {
                installed = yield store_search.is_already_installed(result, cancellable);
            } catch (Error e) {
                error = e;
            }

            if (cancellable.is_cancelled() || selected_result != result) {
                return;
            }

            selected_already_installed = installed;
            update_download_button_for_selection();

            if (error != null) {
                warning("Could not check install state for %s: %s", result.package_id, error.message);
                return;
            }

            if (installed) {
                status_label.set_text(
                    "%s is already installed from %s.".printf(result.name, result.source_label)
                );
            }
        }

        private void on_row_activated(Gtk.ListBoxRow row) {
            on_download_clicked();
        }

        private void on_download_clicked() {
            if (selected_result == null) {
                return;
            }

            if (selected_already_installed) {
                status_label.set_text(
                    "%s is already installed from %s.".printf(
                        selected_result.name,
                        selected_result.source_label
                    )
                );
                return;
            }

            var result = selected_result;
            var browser_download = store_search.requires_browser_download(result);
            var dialog = new GetApkConfirmDialog(
                result.name,
                AppSettings.get_default().get_install_path(),
                selected_row_icon(),
                browser_download
            );
            dialog.confirmed.connect(() => {
                if (browser_download) {
                    open_browser_download(result);
                    return;
                }
                start_download(result);
            });
            dialog.present(this);
        }

        private Gdk.Paintable? selected_row_icon() {
            var row = results_list.get_selected_row();
            if (row == null) {
                return null;
            }
            var box = row.child as Gtk.Box;
            if (box == null) {
                return null;
            }
            var image = box.get_first_child() as Gtk.Image;
            return image != null ? image.paintable : null;
        }

        private void start_download(ApkStoreResult result) {
            if (download_cancellable != null) {
                download_cancellable.cancel();
            }
            download_cancellable = new Cancellable();
            download_progress.visible = true;
            download_progress.pulse();
            download_button.sensitive = false;
            status_label.set_text("Downloading %s…".printf(result.name));

            run_download.begin(result, download_cancellable);
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
            string? download_url = null;
            bool already_installed = false;
            Error? error = null;
            try {
                already_installed = yield store_search.is_already_installed(result, cancellable);
                if (!already_installed) {
                    download_url = yield store_search.resolve_download_url(result, cancellable);
                    path = yield store_search.download_apk(result, cancellable);
                }
            } catch (Error e) {
                error = e;
            }

            if (cancellable.is_cancelled()) {
                return;
            }

            download_progress.visible = false;
            update_download_button_for_selection();

            if (already_installed) {
                selected_already_installed = true;
                update_download_button_for_selection();
                status_label.set_text(
                    "%s is already installed from %s.".printf(result.name, result.source_label)
                );
                return;
            }

            if (error != null) {
                status_label.set_text("Download failed: %s".printf(error.message));
                return;
            }

            status_label.set_text("Installing %s…".printf(result.name));
            string? installed_path = null;
            try {
                installed_path = yield install_downloaded_async(
                    path,
                    result.package_id,
                    result.source_label
                );
            } catch (Error e) {
                status_label.set_text("Downloaded, but install failed: %s".printf(e.message));
                return;
            }

            if (download_url != null) {
                store_search.record_installed(result, download_url, installed_path);
            }

            status_label.set_text("Installed to %s".printf(installed_path));
            apk_ready(installed_path);
            close();
        }

        private async string install_downloaded_async(
            string path,
            string package_id,
            string source_label
        ) throws Error {
            string? result = null;
            Error? error = null;
            new Thread<void>("apk-get-install", () => {
                try {
                    result = ApkInstall.install(path, package_id, source_label);
                } catch (Error e) {
                    error = e;
                }
                Idle.add(install_downloaded_async.callback);
            });
            yield;
            if (error != null) {
                throw error;
            }
            return result;
        }
    }
}
