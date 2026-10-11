namespace ApkManager.Core {
    public enum FileManagerIconMode {
        ANDROID_LOGO,
        EXTRACT_APK
    }

    public enum RuntimeEngine {
        WAYDROID
    }

    public enum PreferredRepository {
        FDROID,
        APTOIDE
    }

    public class AppSettings : Object {
        private static AppSettings? instance;
        private Settings settings;

        public static AppSettings get_default() {
            if (instance == null) {
                instance = new AppSettings();
            }
            return instance;
        }

        construct {
            settings = new Settings(APPLICATION_ID);
        }

        public string get_install_path() {
            var path = settings.get_string("install-path").strip();
            if (path == "") {
                return default_install_path();
            }
            return expand_home(path);
        }

        public void set_install_path(string path) {
            settings.set_string("install-path", path.strip());
        }

        public bool get_remove_original_on_install() {
            return settings.get_boolean("remove-original-on-install");
        }

        public void set_remove_original_on_install(bool enabled) {
            settings.set_boolean("remove-original-on-install", enabled);
        }

        public FileManagerIconMode get_file_manager_icon_mode() {
            return parse_file_manager_icon_mode(settings.get_string("file-manager-icon-mode"));
        }

        public void set_file_manager_icon_mode(FileManagerIconMode mode) {
            settings.set_string("file-manager-icon-mode", file_manager_icon_mode_to_string(mode));
        }

        public RuntimeEngine get_runtime_engine() {
            return parse_runtime_engine(settings.get_string("runtime-engine"));
        }

        public void set_runtime_engine(RuntimeEngine engine) {
            settings.set_string("runtime-engine", runtime_engine_to_string(engine));
        }

        public PreferredRepository get_preferred_repository() {
            return parse_preferred_repository(settings.get_string("preferred-repository"));
        }

        public void set_preferred_repository(PreferredRepository repository) {
            settings.set_string("preferred-repository", preferred_repository_to_string(repository));
        }

        public bool get_check_for_updates() {
            return settings.get_boolean("check-for-updates");
        }

        public void set_check_for_updates(bool enabled) {
            settings.set_boolean("check-for-updates", enabled);
        }

        public static string default_install_path() {
            return Path.build_filename(Environment.get_home_dir(), "Applications", "android");
        }

        public static string expand_home(string path) {
            if (path.has_prefix("~/")) {
                return Path.build_filename(Environment.get_home_dir(), path.substring(2));
            }
            return path;
        }

        public static FileManagerIconMode parse_file_manager_icon_mode(string value) {
            if (value == "extract-apk") {
                return FileManagerIconMode.EXTRACT_APK;
            }
            return FileManagerIconMode.ANDROID_LOGO;
        }

        public static string file_manager_icon_mode_to_string(FileManagerIconMode mode) {
            switch (mode) {
            case FileManagerIconMode.EXTRACT_APK:
                return "extract-apk";
            default:
                return "android-logo";
            }
        }

        public static RuntimeEngine parse_runtime_engine(string value) {
            return RuntimeEngine.WAYDROID;
        }

        public static string runtime_engine_to_string(RuntimeEngine engine) {
            return "waydroid";
        }

        public static PreferredRepository parse_preferred_repository(string value) {
            if (value == "aptoide") {
                return PreferredRepository.APTOIDE;
            }
            return PreferredRepository.FDROID;
        }

        public static string preferred_repository_to_string(PreferredRepository repository) {
            switch (repository) {
            case PreferredRepository.APTOIDE:
                return "aptoide";
            default:
                return "fdroid";
            }
        }
    }
}
