using ApkManager.Core;

namespace ApkManager.Windows {
    public class PreferencesWindow : Adw.PreferencesWindow {
        private AppSettings settings;
        private Adw.EntryRow install_path_row;
        private Adw.SwitchRow remove_original_row;
        private Adw.ComboRow file_manager_icon_row;
        private Adw.ComboRow runtime_engine_row;
        private Adw.ComboRow preferred_repository_row;
        private Adw.SwitchRow update_checks_row;
        private bool loading;

        public PreferencesWindow(Gtk.Window parent) {
            Object(
                transient_for: parent,
                modal: true,
                title: "Preferences",
                default_width: 560,
                default_height: 520,
                destroy_with_parent: true
            );
            settings = AppSettings.get_default();
            build_ui();
            load_from_settings();
        }

        private void build_ui() {
            var page = new Adw.PreferencesPage();
            page.title = "General";
            page.icon_name = "preferences-system-symbolic";

            var install_group = new Adw.PreferencesGroup();
            install_group.title = "Installation";
            install_group.description = "Where APK packages are installed on your system.";

            install_path_row = new Adw.EntryRow();
            install_path_row.title = "Install path";
            install_path_row.changed.connect(on_install_path_changed);

            var browse_button = new Gtk.Button.from_icon_name("folder-open-symbolic");
            browse_button.tooltip_text = "Choose folder";
            browse_button.add_css_class("flat");
            browse_button.clicked.connect(on_browse_install_path);
            install_path_row.add_suffix(browse_button);
            install_group.add(install_path_row);

            remove_original_row = new Adw.SwitchRow();
            remove_original_row.title = "Remove original after install";
            remove_original_row.subtitle = "Move the APK into the install folder instead of leaving a copy";
            remove_original_row.notify["active"].connect(on_remove_original_changed);
            install_group.add(remove_original_row);

            file_manager_icon_row = new Adw.ComboRow();
            file_manager_icon_row.title = "File manager icons";
            file_manager_icon_row.subtitle = "Use the Android logo or extract each app's icon from its APK";
            file_manager_icon_row.model = new Gtk.StringList(new string[] {
                "Android logo",
                "Extract from APK"
            });
            file_manager_icon_row.notify["selected"].connect(on_file_manager_icon_changed);
            install_group.add(file_manager_icon_row);
            page.add(install_group);

            var runtime_group = new Adw.PreferencesGroup();
            runtime_group.title = "Runtime";
            runtime_group.description = "Android container used to run installed apps.";

            runtime_engine_row = new Adw.ComboRow();
            runtime_engine_row.title = "Runtime engine";
            runtime_engine_row.model = new Gtk.StringList(new string[] { "Waydroid" });
            runtime_engine_row.notify["selected"].connect(on_runtime_engine_changed);
            runtime_group.add(runtime_engine_row);
            page.add(runtime_group);

            var store_group = new Adw.PreferencesGroup();
            store_group.title = "Stores";
            store_group.description = "Default source when searching for APKs.";

            preferred_repository_row = new Adw.ComboRow();
            preferred_repository_row.title = "Preferred repository";
            preferred_repository_row.model = new Gtk.StringList(new string[] {
                "F-Droid",
                "Aptoide"
            });
            preferred_repository_row.notify["selected"].connect(on_preferred_repository_changed);
            store_group.add(preferred_repository_row);
            page.add(store_group);

            var updates_group = new Adw.PreferencesGroup();
            updates_group.title = "Updates";

            update_checks_row = new Adw.SwitchRow();
            update_checks_row.title = "Update checks";
            update_checks_row.subtitle = "Periodically check for ApkManager updates";
            update_checks_row.notify["active"].connect(on_update_checks_changed);
            updates_group.add(update_checks_row);
            page.add(updates_group);

            add(page);
        }

        private void load_from_settings() {
            loading = true;

            install_path_row.text = settings.get_install_path();
            remove_original_row.active = settings.get_remove_original_on_install();

            switch (settings.get_file_manager_icon_mode()) {
            case FileManagerIconMode.EXTRACT_APK:
                file_manager_icon_row.selected = 1;
                break;
            default:
                file_manager_icon_row.selected = 0;
                break;
            }

            runtime_engine_row.selected = 0;

            switch (settings.get_preferred_repository()) {
            case PreferredRepository.APTOIDE:
                preferred_repository_row.selected = 1;
                break;
            default:
                preferred_repository_row.selected = 0;
                break;
            }

            update_checks_row.active = settings.get_check_for_updates();

            loading = false;
        }

        private void on_install_path_changed() {
            if (loading) {
                return;
            }
            settings.set_install_path(install_path_row.text);
        }

        private void on_remove_original_changed() {
            if (loading) {
                return;
            }
            settings.set_remove_original_on_install(remove_original_row.active);
        }

        private void on_browse_install_path() {
            browse_install_path_async.begin();
        }

        private async void browse_install_path_async() {
            var dialog = new Gtk.FileDialog();
            dialog.title = "Choose install folder";

            var current = settings.get_install_path();
            if (current != "") {
                var folder = File.new_for_path(current);
                if (folder.query_exists()) {
                    dialog.set_initial_folder(folder);
                }
            }

            try {
                var folder = yield dialog.select_folder(this, null);
                var path = folder.get_path();
                if (path == null) {
                    return;
                }
                loading = true;
                install_path_row.text = path;
                settings.set_install_path(path);
                loading = false;
            } catch (Error e) {
                // User cancelled or the folder could not be opened.
            }
        }

        private void on_file_manager_icon_changed() {
            if (loading) {
                return;
            }
            var mode = file_manager_icon_row.selected == 1
                ? FileManagerIconMode.EXTRACT_APK
                : FileManagerIconMode.ANDROID_LOGO;
            settings.set_file_manager_icon_mode(mode);
        }

        private void on_runtime_engine_changed() {
            if (loading) {
                return;
            }
            settings.set_runtime_engine(RuntimeEngine.WAYDROID);
        }

        private void on_preferred_repository_changed() {
            if (loading) {
                return;
            }
            var repository = preferred_repository_row.selected == 1
                ? PreferredRepository.APTOIDE
                : PreferredRepository.FDROID;
            settings.set_preferred_repository(repository);
        }

        private void on_update_checks_changed() {
            if (loading) {
                return;
            }
            settings.set_check_for_updates(update_checks_row.active);
        }
    }
}
