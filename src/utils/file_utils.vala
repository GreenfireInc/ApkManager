namespace ApkManager.Utils {
    public class FileUtilsHelper {
        public static string format_bytes(int64 bytes) {
            if (bytes < 1024) {
                return "%lld B".printf(bytes);
            }
            if (bytes < 1024 * 1024) {
                return "%.1f KiB".printf(bytes / 1024.0);
            }
            if (bytes < 1024 * 1024 * 1024) {
                return "%.1f MiB".printf(bytes / (1024.0 * 1024.0));
            }
            return "%.2f GiB".printf(bytes / (1024.0 * 1024.0 * 1024.0));
        }

        public static void remove_tree_if_exists(string path) {
            if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
                return;
            }
            try {
                var file = File.new_for_path(path);
                file.trash(null);
            } catch (Error e) {
                warning("Failed to remove %s: %s", path, e.message);
            }
        }

        public static bool show_in_file_manager(string path) {
            if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
                warning("Cannot reveal missing file: %s", path);
                return false;
            }

            var uri = File.new_for_path(path).get_uri();
            try {
                var builder = new VariantBuilder(new VariantType("(ass)"));
                builder.add("^as", new string[] { uri });
                builder.add("s", "");
                var connection = Bus.get_sync(BusType.SESSION, null);
                connection.call_sync(
                    "org.freedesktop.FileManager1",
                    "/org/freedesktop/FileManager1",
                    "org.freedesktop.FileManager1",
                    "ShowItems",
                    builder.end(),
                    new VariantType("()"),
                    DBusCallFlags.NONE,
                    -1,
                    null
                );
                return true;
            } catch (Error e) {
                warning("FileManager1.ShowItems failed for %s: %s", path, e.message);
            }

            try {
                var parent = File.new_for_path(path).get_parent();
                if (parent != null && AppInfo.launch_default_for_uri(parent.get_uri(), null)) {
                    return true;
                }
            } catch (Error e) {
                warning("Could not open folder for %s: %s", path, e.message);
            }

            return false;
        }
    }
}
