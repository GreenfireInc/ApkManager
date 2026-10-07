namespace ApkManager.Core {
    public class ApkMetadata : Object {
        public string package_name { get; set; default = ""; }
        public string version_name { get; set; default = ""; }
        public string version_code { get; set; default = ""; }
        public string min_sdk { get; set; default = ""; }
        public string target_sdk { get; set; default = ""; }
        public string compile_sdk { get; set; default = ""; }
        public string app_label { get; set; default = ""; }
        public string apk_file_name { get; set; default = ""; }
        public string icon_ref { get; set; default = ""; }
        public Gee.ArrayList<string> permissions = new Gee.ArrayList<string>();

        public string display_name() {
            if (app_label != "") {
                return app_label;
            }
            if (apk_file_name != "") {
                return apk_file_name;
            }
            if (package_name != "") {
                return package_name;
            }
            return "APK";
        }

        public string version_line() {
            if (version_name != "" && version_code != "") {
                return "%s (%s)".printf(version_name, version_code);
            }
            if (version_name != "") {
                return version_name;
            }
            if (version_code != "") {
                return version_code;
            }
            return "";
        }

        public static ApkMetadata from_decode_dir(string decode_dir) throws Error {
            var manifest = Path.build_filename(decode_dir, "AndroidManifest.xml");
            var yml = Path.build_filename(decode_dir, "apktool.yml");
            if (!FileUtils.test(manifest, FileTest.EXISTS) && !FileUtils.test(yml, FileTest.EXISTS)) {
                throw new IOError.NOT_FOUND("No AndroidManifest.xml or apktool.yml in %s".printf(decode_dir));
            }

            var meta = new ApkMetadata();
            if (FileUtils.test(yml, FileTest.EXISTS)) {
                meta.load_yml(yml);
            }
            if (FileUtils.test(manifest, FileTest.EXISTS)) {
                meta.load_manifest(manifest);
            }
            return meta;
        }

        private void load_yml(string path) throws Error {
            string contents;
            FileUtils.get_contents(path, out contents);
            string section = "";
            foreach (var raw in contents.split("\n")) {
                if (raw.strip() == "" || raw.has_prefix("#")) {
                    continue;
                }
                if (!raw.has_prefix(" ") && !raw.has_prefix("\t")) {
                    var split = raw.split(":", 2);
                    section = split[0].strip();
                    if (split.length == 2) {
                        assign_top_level(section, unquote(split[1]));
                    }
                    continue;
                }

                var line = raw.strip();
                if (line.has_prefix("-")) {
                    continue;
                }
                var split = line.split(":", 2);
                if (split.length < 2) {
                    continue;
                }
                assign_section(section, split[0].strip(), unquote(split[1]));
            }
        }

        private void assign_top_level(string key, string value) {
            if (key == "apkFileName" && value != "") {
                apk_file_name = value;
            }
        }

        private void assign_section(string section, string key, string value) {
            if (value == "" || value == "null") {
                return;
            }
            switch (section) {
                case "sdkInfo":
                    if (key == "minSdkVersion") {
                        min_sdk = value;
                    } else if (key == "targetSdkVersion") {
                        target_sdk = value;
                    }
                    break;
                case "versionInfo":
                    if (key == "versionName") {
                        version_name = value;
                    } else if (key == "versionCode") {
                        version_code = value;
                    }
                    break;
                case "packageInfo":
                    if (key == "renameManifestPackage" && package_name == "") {
                        package_name = value;
                    }
                    break;
            }
        }

        private void load_manifest(string path) throws Error {
            string contents;
            FileUtils.get_contents(path, out contents);
            MarkupParser parser = { start_element: on_start_element };
            var context = new MarkupParseContext(parser, 0, this, null);
            context.parse(contents, -1);
            context.end_parse();
        }

        private void on_start_element(MarkupParseContext context, string element_name, string[] attr_names, string[] attr_values) throws MarkupError {
            switch (element_name) {
                case "manifest":
                    assign_text(Field.PACKAGE, attr(attr_names, attr_values, "package"), true);
                    assign_text(Field.VERSION_NAME, attr(attr_names, attr_values, "versionName"), false);
                    assign_text(Field.VERSION_CODE, attr(attr_names, attr_values, "versionCode"), false);
                    assign_text(Field.COMPILE_SDK, attr(attr_names, attr_values, "compileSdkVersion"), false);
                    break;
                case "uses-sdk":
                    assign_text(Field.MIN_SDK, attr(attr_names, attr_values, "minSdkVersion"), false);
                    assign_text(Field.TARGET_SDK, attr(attr_names, attr_values, "targetSdkVersion"), false);
                    break;
                case "application":
                    assign_text(Field.LABEL, attr(attr_names, attr_values, "label"), false);
                    var icon = attr(attr_names, attr_values, "icon");
                    if (icon != null && icon != "") {
                        icon_ref = icon;
                    }
                    break;
                case "uses-permission":
                case "uses-permission-sdk-23":
                    var name = attr(attr_names, attr_values, "name");
                    if (name != null && name != "" && !permissions.contains(name)) {
                        permissions.add(name);
                    }
                    break;
            }
        }

        private enum Field {
            PACKAGE,
            VERSION_NAME,
            VERSION_CODE,
            MIN_SDK,
            TARGET_SDK,
            COMPILE_SDK,
            LABEL
        }

        private void assign_text(Field field, string? value, bool allow_at) {
            if (value == null || value == "") {
                return;
            }
            if (!allow_at && value.has_prefix("@")) {
                return;
            }
            switch (field) {
                case Field.PACKAGE:
                    package_name = value;
                    break;
                case Field.VERSION_NAME:
                    version_name = value;
                    break;
                case Field.VERSION_CODE:
                    version_code = value;
                    break;
                case Field.MIN_SDK:
                    min_sdk = value;
                    break;
                case Field.TARGET_SDK:
                    target_sdk = value;
                    break;
                case Field.COMPILE_SDK:
                    compile_sdk = value;
                    break;
                case Field.LABEL:
                    app_label = value;
                    break;
            }
        }

        private static string? attr(string[] names, string[] values, string key) {
            var suffix = ":" + key;
            for (int i = 0; names[i] != null; i++) {
                if (names[i] == key || names[i].has_suffix(suffix)) {
                    return values[i];
                }
            }
            return null;
        }

        private static string unquote(string raw) {
            var value = raw.strip();
            if (value.length >= 2 && value.has_prefix("'") && value.has_suffix("'")) {
                return value.substring(1, value.length - 2);
            }
            if (value.length >= 2 && value.has_prefix("\"") && value.has_suffix("\"")) {
                return value.substring(1, value.length - 2);
            }
            return value;
        }
    }
}
