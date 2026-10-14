namespace ApkManager.Core {
    public class ApkInstallFilename : Object {
        public const string DISK_SOURCE = "disk";

        public static string install_basename(
            string apk_path,
            string? package_hint = null,
            string? source_label = null
        ) {
            var package = package_hint != null ? package_hint.strip() : "";
            if (package == "") {
                package = ApkDisplayName.package_name(apk_path) ?? "";
            }
            if (package == "") {
                var fallback = Path.get_basename(apk_path);
                if (fallback.has_suffix(".apk")) {
                    package = fallback.substring(0, fallback.length - 4);
                } else if (fallback.has_suffix(".APK")) {
                    package = fallback.substring(0, fallback.length - 4);
                } else {
                    package = fallback;
                }
            }

            var source = sanitize_source(source_label ?? DISK_SOURCE);
            var arch = detect_architecture(apk_path);
            return "%s.from.%s.%s.apk".printf(package, source, arch);
        }

        public static string expected_installed_path(
            string apk_path,
            string? package_hint = null,
            string? source_label = null
        ) {
            return Path.build_filename(
                AppSettings.get_default().get_install_path(),
                install_basename(apk_path, package_hint, source_label)
            );
        }

        public static bool find_store_install(
            string package_id,
            string source_label,
            out string? found_path
        ) {
            found_path = null;
            var package = package_id.strip();
            if (package == "") {
                return false;
            }

            var install_dir = AppSettings.get_default().get_install_path();
            if (!FileUtils.test(install_dir, FileTest.IS_DIR)) {
                return false;
            }

            var prefix = "%s.from.%s.".printf(package, sanitize_source(source_label));
            try {
                var dir = Dir.open(install_dir, 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_prefix(prefix) || !name.has_suffix(".apk")) {
                        continue;
                    }
                    var candidate = Path.build_filename(install_dir, name);
                    if (FileUtils.test(candidate, FileTest.IS_REGULAR)) {
                        found_path = candidate;
                        return true;
                    }
                }
            } catch (FileError e) {
                warning("Failed to scan install folder for %s: %s", package, e.message);
            }
            return false;
        }

        public static string sanitize_source(string source) {
            var normalized = source.strip();
            if (normalized == "") {
                return DISK_SOURCE;
            }
            return normalized.replace("/", "-").replace("\\", "-");
        }

        public static string detect_architecture(string apk_path) {
            try {
                var entries = ApkArchive.list_entries(apk_path);
                var abis = new Gee.HashSet<string>();
                foreach (var entry in entries) {
                    if (entry.is_directory || !entry.path.has_prefix("lib/")) {
                        continue;
                    }
                    var parts = entry.path.split("/");
                    if (parts.length >= 2 && parts[1] != "") {
                        abis.add(parts[1]);
                    }
                }

                if (abis.size == 0) {
                    return "universal";
                }
                if (abis.size > 1) {
                    return "universal";
                }

                foreach (var abi in abis) {
                    return abi_folder_to_label(abi);
                }
            } catch (Error e) {
                warning("Failed to detect APK architecture for %s: %s", apk_path, e.message);
            }
            return "unknown";
        }

        private static string abi_folder_to_label(string folder) {
            switch (folder) {
            case "arm64-v8a":
                return "arm64";
            case "armeabi-v7a":
                return "armv7";
            case "armeabi":
                return "arm";
            case "x86_64":
                return "x86_64";
            case "x86":
                return "x86";
            default:
                return folder;
            }
        }
    }
}
