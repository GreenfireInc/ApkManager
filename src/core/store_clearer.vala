namespace ApkManager.Core {
    public class StoreClearResult : Object {
        public int apk_files_deleted { get; set; default = 0; }
        public int apk_files_failed { get; set; default = 0; }
        public int download_files_removed { get; set; default = 0; }
    }

    public class StoreClearer : Object {
        public static StoreClearResult clear(bool delete_installed_apks) {
            var result = new StoreClearResult();
            var install_dir = AppSettings.get_default().get_install_path();
            var registry = StoreInstallRegistry.get_default();
            var apk_paths = registry.collect_apk_paths();
            merge_store_apk_paths(apk_paths, scan_store_apk_paths(install_dir));

            result.download_files_removed = clear_downloads_cache();
            AppSettings.get_default().reset_to_defaults();
            registry.clear_all();

            if (delete_installed_apks) {
                delete_apk_files(apk_paths, result);
            }

            return result;
        }

        private static void merge_store_apk_paths(
            Gee.ArrayList<string> paths,
            Gee.ArrayList<string> extra
        ) {
            foreach (var path in extra) {
                if (!paths.contains(path)) {
                    paths.add(path);
                }
            }
        }

        private static Gee.ArrayList<string> scan_store_apk_paths(string install_dir) {
            var paths = new Gee.ArrayList<string>();
            if (!FileUtils.test(install_dir, FileTest.IS_DIR)) {
                return paths;
            }

            try {
                var dir = Dir.open(install_dir, 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_suffix(".apk") || !name.contains(".from.")) {
                        continue;
                    }
                    if (name.contains(".from.disk.")) {
                        continue;
                    }
                    var candidate = Path.build_filename(install_dir, name);
                    if (FileUtils.test(candidate, FileTest.IS_REGULAR)) {
                        paths.add(candidate);
                    }
                }
            } catch (FileError e) {
                warning("Failed to scan install folder for store APKs: %s", e.message);
            }
            return paths;
        }

        private static int clear_downloads_cache() {
            var removed = 0;
            var downloads_dir = AppPaths.downloads_dir;
            if (!FileUtils.test(downloads_dir, FileTest.IS_DIR)) {
                return removed;
            }

            try {
                var dir = Dir.open(downloads_dir, 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    var candidate = Path.build_filename(downloads_dir, name);
                    try {
                        if (FileUtils.test(candidate, FileTest.IS_REGULAR)) {
                            FileUtils.remove(candidate);
                            removed++;
                        }
                    } catch (FileError e) {
                        warning("Could not remove download cache file %s: %s", candidate, e.message);
                    }
                }
            } catch (FileError e) {
                warning("Failed to clear download cache: %s", e.message);
            }
            return removed;
        }

        private static void delete_apk_files(Gee.ArrayList<string> paths, StoreClearResult result) {
            foreach (var path in paths) {
                if (!FileUtils.test(path, FileTest.IS_REGULAR)) {
                    continue;
                }
                try {
                    FileUtils.remove(path);
                    result.apk_files_deleted++;
                } catch (FileError e) {
                    result.apk_files_failed++;
                    warning("Could not delete store APK %s: %s", path, e.message);
                }
            }
        }
    }
}
