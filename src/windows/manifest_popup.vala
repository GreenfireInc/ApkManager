using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    public class ManifestPopup : Adw.Window {
        private const int MAX_PERMISSION_ROWS = 24;

        public ManifestPopup(Gtk.Window parent, string apk_path, ApkMetadata meta) {
            Object(
                transient_for: parent,
                modal: true,
                title: "APK metadata",
                default_width: 520,
                default_height: 640,
                destroy_with_parent: true
            );
            build_ui(apk_path, meta);
        }

        private void build_ui(string apk_path, ApkMetadata meta) {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            var heading = meta.display_name(apk_path);
            var sub = meta.version_line();
            header.title_widget = new Adw.WindowTitle(heading, sub != "" ? sub : meta.package_name);
            toolbar.add_top_bar(header);

            toolbar.content = build_properties_view(apk_path, meta);
        }

        public static Gtk.Widget build_properties_view(string apk_path, ApkMetadata meta) {
            var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            var page = new Adw.PreferencesPage();
            page.vexpand = true;
            body.append(page);

            var identity = new Adw.PreferencesGroup();
            identity.title = "Application";
            identity.add(row("Package", meta.package_name));
            identity.add(row("Version", meta.version_line()));
            identity.add(file_row(
                apk_path,
                meta.apk_file_name != "" ? meta.apk_file_name : Path.get_basename(apk_path)
            ));
            identity.add(row("Size", file_size(apk_path)));
            identity.add(app_data_row(apk_path, meta.display_name(apk_path)));
            page.add(identity);

            var sdk = new Adw.PreferencesGroup();
            sdk.title = "SDK";
            sdk.add(row("Minimum", meta.min_sdk));
            sdk.add(row("Target", meta.target_sdk));
            sdk.add(row("Compile", meta.compile_sdk));
            page.add(sdk);

            var perms = new Adw.PreferencesGroup();
            perms.title = "Permissions";
            perms.description = "%u declared".printf(meta.permissions.size);
            uint shown = 0;
            foreach (var name in meta.permissions) {
                if (shown >= MAX_PERMISSION_ROWS) {
                    break;
                }
                var perm = new Adw.ActionRow();
                perm.title = name;
                perm.title_selectable = true;
                perms.add(perm);
                shown++;
            }
            if (meta.permissions.size > shown) {
                var more = new Adw.ActionRow();
                more.title = "And %u more".printf(meta.permissions.size - shown);
                perms.add(more);
            }
            page.add(perms);

            return body;
        }

        private static Adw.ActionRow row(string title, string value) {
            var item = new Adw.ActionRow();
            item.title = title;
            item.subtitle = value != "" ? value : "—";
            item.subtitle_selectable = true;
            return item;
        }

        private static Adw.ActionRow file_row(string apk_path, string display_name) {
            var item = new Adw.ActionRow();
            item.title = "File";
            item.subtitle = display_name != "" ? display_name : "—";
            item.subtitle_selectable = true;
            item.activatable = true;
            item.add_suffix(new Gtk.Image.from_icon_name("folder-open-symbolic"));
            item.activated.connect(() => {
                FileUtilsHelper.show_in_file_manager(apk_path);
            });
            return item;
        }

        private static Adw.ActionRow app_data_row(string apk_path, string app_name) {
            var dir = RuntimeRunner.atl_app_data_dir(apk_path);
            var item = new Adw.ActionRow();
            item.title = "App data";
            item.subtitle_selectable = true;

            var open_button = new Gtk.Button.from_icon_name("folder-open-symbolic");
            open_button.tooltip_text = "Open in the file manager";
            open_button.valign = Gtk.Align.CENTER;
            open_button.add_css_class("flat");
            open_button.clicked.connect(() => {
                try {
                    AppInfo.launch_default_for_uri(File.new_for_path(dir).get_uri(), null);
                } catch (Error e) {
                    warning("Could not open %s: %s", dir, e.message);
                }
            });

            var reset_button = new Gtk.Button.from_icon_name("user-trash-symbolic");
            reset_button.tooltip_text = "Reset: delete this app's data";
            reset_button.valign = Gtk.Align.CENTER;
            reset_button.add_css_class("flat");

            item.add_suffix(open_button);
            item.add_suffix(reset_button);

            update_app_data_row(item, open_button, reset_button, dir);

            reset_button.clicked.connect(() => {
                var dialog = new Adw.AlertDialog(
                    "Reset %s?".printf(app_name),
                    "This deletes %s, including the app's settings, databases and files. The next run starts fresh. Close the app first if it is running.".printf(dir)
                );
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("reset", "Delete App Data");
                dialog.set_response_appearance("reset", Adw.ResponseAppearance.DESTRUCTIVE);
                dialog.default_response = "cancel";
                dialog.close_response = "cancel";
                dialog.response.connect((response) => {
                    if (response != "reset") {
                        return;
                    }
                    try {
                        FileUtilsHelper.delete_tree(dir);
                    } catch (Error e) {
                        var failed = new Adw.AlertDialog("Could not delete the app data", e.message);
                        failed.add_response("close", "Close");
                        failed.present(item);
                    }
                    update_app_data_row(item, open_button, reset_button, dir);
                });
                dialog.present(item);
            });
            return item;
        }

        private static void update_app_data_row(
            Adw.ActionRow item,
            Gtk.Button open_button,
            Gtk.Button reset_button,
            string dir
        ) {
            var exists = FileUtils.test(dir, FileTest.IS_DIR);
            item.subtitle = exists
                ? dir
                : "%s (created when the app first runs in Android Translation Layer)".printf(dir);
            open_button.sensitive = exists;
            reset_button.sensitive = exists;
        }

        private static string file_size(string apk_path) {
            try {
                var file = File.new_for_path(apk_path);
                var info = file.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE, null);
                return FileUtilsHelper.format_bytes(info.get_size());
            } catch (Error e) {
                return "—";
            }
        }
    }
}
