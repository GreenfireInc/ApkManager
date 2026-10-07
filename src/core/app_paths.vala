namespace ApkManager.Core {
    public class AppPaths {
        public static string data_dir {
            owned get {
                var dir = Path.build_filename(Environment.get_user_data_dir(), DATA_DIRNAME);
                DirUtils.create_with_parents(dir, 0700);
                return dir;
            }
        }

        public static string cache_dir {
            owned get {
                var dir = Path.build_filename(Environment.get_user_cache_dir(), DATA_DIRNAME);
                DirUtils.create_with_parents(dir, 0700);
                return dir;
            }
        }

        public static string sessions_file {
            owned get {
                return Path.build_filename(data_dir, SESSIONS_FILENAME);
            }
        }

        public static string decoded_root {
            owned get {
                var dir = Path.build_filename(cache_dir, DECODED_DIRNAME);
                DirUtils.create_with_parents(dir, 0700);
                return dir;
            }
        }

        public static string frameworks_dir {
            owned get {
                var dir = Path.build_filename(cache_dir, FRAMEWORKS_DIRNAME);
                DirUtils.create_with_parents(dir, 0700);
                return dir;
            }
        }

        public static string apktool_jar_path {
            owned get {
                var env = Environment.get_variable("APK_MANAGER_APKTOOL_JAR");
                if (env != null && env.strip() != "" && FileUtils.test(env.strip(), FileTest.EXISTS)) {
                    return env.strip();
                }

                var installed = Path.build_filename(get_install_prefix(), "lib", "apk-manager", APKTOOL_JAR_NAME);
                if (FileUtils.test(installed, FileTest.EXISTS)) {
                    return installed;
                }

                // Development fallback: build directory output from fetch-apktool.sh
                var build_fallback = Path.build_filename(Environment.get_current_dir(), "build", "apktool.jar");
                if (FileUtils.test(build_fallback, FileTest.EXISTS)) {
                    return build_fallback;
                }

                return installed;
            }
        }

        public static string decoded_dir_for_key(string cache_key) {
            owned get {
                return Path.build_filename(decoded_root, cache_key);
            }
        }

        public static string partial_decode_dir(string cache_key) {
            owned get {
                return "%s.partial-%d".printf(decoded_dir_for_key(cache_key), Posix.getpid());
            }
        }

        private static string get_install_prefix() {
            var prefix = Environment.get_variable("APK_MANAGER_PREFIX");
            if (prefix != null && prefix.strip() != "") {
                return prefix.strip();
            }
            return "/usr/local";
        }
    }
}
