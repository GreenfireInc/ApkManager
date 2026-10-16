using Json;

namespace ApkManager.Core {
    public class StoreInstallStatus : GLib.Object {
        public bool has_existing { get; set; default = false; }
        public StoreInstallRecord? existing_record { get; set; }
        public string existing_path { get; set; default = ""; }
        public string new_version_code { get; set; default = ""; }
        public bool same_version { get; set; default = false; }
    }

    public class StoreInstallRecord : GLib.Object {
        public ApkStoreSource source { get; construct; }
        public string package_id { get; construct; }
        public string version_code { get; construct; }
        public string version_name { get; construct; }
        public string apk_path { get; construct; }

        public StoreInstallRecord(
            ApkStoreSource source,
            string package_id,
            string version_code,
            string version_name,
            string apk_path
        ) {
            GLib.Object(
                source: source,
                package_id: package_id,
                version_code: version_code,
                version_name: version_name,
                apk_path: apk_path
            );
        }
    }

    public class StoreInstallRegistry : GLib.Object {
        private static StoreInstallRegistry? instance;
        private Gee.ArrayList<StoreInstallRecord> records = new Gee.ArrayList<StoreInstallRecord>();

        public static StoreInstallRegistry get_default() {
            if (instance == null) {
                instance = new StoreInstallRegistry();
            }
            return instance;
        }

        construct {
            load();
            prune_missing_files();
        }

        public bool is_installed(
            ApkStoreSource source,
            string package_id,
            string version_code,
            string expected_apk_path
        ) {
            prune_missing_files();
            var normalized_package = package_id.strip();
            var normalized_version = version_code.strip();
            var normalized_path = expected_apk_path.strip();

            foreach (var record in records) {
                if (record.source != source || record.package_id != normalized_package) {
                    continue;
                }
                if (!FileUtils.test(record.apk_path, FileTest.EXISTS)) {
                    continue;
                }
                if (normalized_path != "" && record.apk_path == normalized_path) {
                    return true;
                }
                if (normalized_version != "" && record.version_code == normalized_version) {
                    return true;
                }
            }
            return false;
        }

        public StoreInstallRecord? find_by_package(ApkStoreSource source, string package_id) {
            prune_missing_files();
            var normalized_package = package_id.strip();
            foreach (var record in records) {
                if (record.source == source
                    && record.package_id == normalized_package
                    && FileUtils.test(record.apk_path, FileTest.EXISTS)) {
                    return record;
                }
            }
            return null;
        }

        public void record(StoreInstallRecord entry) {
            prune_missing_files();
            for (int i = records.size - 1; i >= 0; i--) {
                var existing = records[i];
                if (existing.source == entry.source
                    && existing.package_id == entry.package_id) {
                    records.remove_at(i);
                }
            }
            records.add(entry);
            save();
        }

        public Gee.ArrayList<string> collect_apk_paths() {
            prune_missing_files();
            var paths = new Gee.ArrayList<string>();
            foreach (var record in records) {
                if (record.apk_path.strip() != "") {
                    paths.add(record.apk_path);
                }
            }
            return paths;
        }

        public void clear_all() {
            records.clear();
            save();
        }

        private void prune_missing_files() {
            for (int i = records.size - 1; i >= 0; i--) {
                if (!FileUtils.test(records[i].apk_path, FileTest.EXISTS)) {
                    records.remove_at(i);
                }
            }
        }

        private void save() {
            var root = new Json.Builder();
            root.begin_array();
            foreach (var record in records) {
                root.begin_object();
                root.set_member_name("source").add_string_value(source_to_string(record.source));
                root.set_member_name("packageId").add_string_value(record.package_id);
                root.set_member_name("versionCode").add_string_value(record.version_code);
                root.set_member_name("versionName").add_string_value(record.version_name);
                root.set_member_name("apkPath").add_string_value(record.apk_path);
                root.end_object();
            }
            root.end_array();

            try {
                var generator = new Json.Generator();
                generator.set_root(root.get_root());
                generator.to_file(AppPaths.store_installs_file);
            } catch (Error e) {
                warning("Failed to save store installs: %s", e.message);
            }
        }

        private void load() {
            if (!FileUtils.test(AppPaths.store_installs_file, FileTest.EXISTS)) {
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_file(AppPaths.store_installs_file);
                var root = parser.get_root();
                if (root.get_node_type() != Json.NodeType.ARRAY) {
                    return;
                }

                var array = root.get_array();
                for (int i = 0; i < array.get_length(); i++) {
                    var obj = array.get_object_element(i);
                    records.add(new StoreInstallRecord(
                        parse_source(obj.get_string_member("source")),
                        obj.get_string_member("packageId"),
                        obj.get_string_member("versionCode"),
                        obj.get_string_member("versionName"),
                        obj.get_string_member("apkPath")
                    ));
                }
            } catch (Error e) {
                warning("Failed to load store installs: %s", e.message);
            }
        }

        private static string source_to_string(ApkStoreSource source) {
            switch (source) {
            case ApkStoreSource.APTOIDE:
                return "aptoide";
            case ApkStoreSource.UPTODOWN:
                return "uptodown";
            case ApkStoreSource.IZZYONDROID:
                return "izzyondroid";
            case ApkStoreSource.OPENAPK:
                return "openapk";
            case ApkStoreSource.APKMIRROR:
                return "apkmirror";
            default:
                return "fdroid";
            }
        }

        private static ApkStoreSource parse_source(string value) {
            switch (value) {
            case "aptoide":
                return ApkStoreSource.APTOIDE;
            case "uptodown":
                return ApkStoreSource.UPTODOWN;
            case "izzyondroid":
                return ApkStoreSource.IZZYONDROID;
            case "openapk":
                return ApkStoreSource.OPENAPK;
            case "apkmirror":
                return ApkStoreSource.APKMIRROR;
            default:
                return ApkStoreSource.FDROID;
            }
        }
    }
}
