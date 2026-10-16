namespace ApkManager.Core {
    public class ApkInstall {
        public static bool is_already_installed(string apk_path, out string? installed_path) {
            installed_path = null;
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                return false;
            }

            var expected = ApkInstallFilename.expected_installed_path(
                apk_path,
                null,
                ApkInstallFilename.DISK_SOURCE
            );

            try {
                var src = File.new_for_path(apk_path);
                var dst = File.new_for_path(expected);
                if (src.equal(dst)) {
                    installed_path = expected;
                    return true;
                }
            } catch (Error e) {
                warning("Could not compare install paths for %s: %s", apk_path, e.message);
            }

            if (FileUtils.test(expected, FileTest.IS_REGULAR)) {
                installed_path = expected;
                return true;
            }

            return false;
        }

        public static string install(
            string apk_path,
            string? package_id = null,
            string? source_label = null
        ) throws Error {
            var install_dir = AppSettings.get_default().get_install_path();
            DirUtils.create_with_parents(install_dir, 0755);

            var basename = ApkInstallFilename.install_basename(apk_path, package_id, source_label);
            var dest = Path.build_filename(install_dir, basename);

            var src = File.new_for_path(apk_path);
            var dst = File.new_for_path(dest);
            if (src.equal(dst)) {
                return dest;
            }
            if (AppSettings.get_default().get_remove_original_on_install()) {
                src.move(dst, FileCopyFlags.OVERWRITE, null, null);
            } else {
                src.copy(dst, FileCopyFlags.OVERWRITE, null, null);
            }
            FileManagerIcons.notify_apk_changed(dest);
            return dest;
        }
    }
}
