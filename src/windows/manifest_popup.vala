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
            identity.add(row("File", meta.apk_file_name != "" ? meta.apk_file_name : Path.get_basename(apk_path)));
            identity.add(row("Size", file_size(apk_path)));
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
