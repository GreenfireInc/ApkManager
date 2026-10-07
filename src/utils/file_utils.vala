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
    }
}
