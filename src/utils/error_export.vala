using ApkManager.Core;

namespace ApkManager.Utils {
    // JSON exports named YYYYMMDD.<application>.<runtime>.<kind>.HHMM.json
    // (local time, 24-hour), e.g. 20261121.pubg-mobile.lepton.error.2033.json.
    public class ErrorExport : Object {
        public static string filename(string apk_path, RuntimeEngine engine, string kind) {
            var now = new DateTime.now_local();
            return "%s.%s.%s.%s.%s.json".printf(
                now.format("%Y%m%d"),
                application_slug(apk_path),
                AppSettings.runtime_engine_to_string(engine),
                kind,
                now.format("%H%M")
            );
        }

        public static async string error_json(string apk_path, RuntimeEngine engine, string title, string message) {
            var root = new Json.Builder();
            root.begin_object();
            root.set_member_name("exportedAt").add_string_value(new DateTime.now_local().format_iso8601());
            yield append_report_info(root);

            root.set_member_name("application");
            root.begin_object();
            root.set_member_name("name").add_string_value(ApkDisplayName.resolve(apk_path) ?? Path.get_basename(apk_path));
            root.set_member_name("package").add_string_value(ApkDisplayName.package_name(apk_path) ?? "");
            root.set_member_name("apk").add_string_value(apk_path);
            root.end_object();

            yield append_runtime(root, engine);

            root.set_member_name("error");
            root.begin_object();
            root.set_member_name("title").add_string_value(title);
            root.set_member_name("message").add_string_value(message);
            root.end_object();

            root.end_object();
            var generator = new Json.Generator();
            generator.pretty = true;
            generator.set_root(root.get_root());
            return generator.to_data(null);
        }

        public static async void append_runtime(Json.Builder root, RuntimeEngine engine) {
            var version = yield RuntimeRunner.runtime_version(engine);
            root.set_member_name("runtime");
            root.begin_object();
            root.set_member_name("id").add_string_value(AppSettings.runtime_engine_to_string(engine));
            root.set_member_name("name").add_string_value(AppSettings.runtime_engine_label(engine));
            root.set_member_name("version").add_string_value(version);
            root.end_object();
        }

        // Throws IOError.CANCELLED when the user closes the file chooser.
        public static async void save(Gtk.Window parent, string title, string filename, string json) throws Error {
            var dialog = new Gtk.FileDialog();
            dialog.title = title;
            dialog.initial_name = filename;
            var downloads = File.new_for_path(Path.build_filename(Environment.get_home_dir(), "Downloads"));
            if (downloads.query_exists()) {
                dialog.initial_folder = downloads;
            }
            var file = yield dialog.save(parent, null);
            var text = hide_home(json);
            uint8[] contents = new uint8[text.length];
            Memory.copy(contents, text.data, text.length);
            string? etag = null;
            yield file.replace_contents_async(contents, null, false, FileCreateFlags.REPLACE_DESTINATION, null, out etag);
        }

        // Only whole home paths are replaced, so /home/corey2 survives when home is /home/corey.
        public static string hide_home(string text) {
            var home = Environment.get_home_dir();
            if (home == "" || home == "/") {
                return text;
            }
            try {
                var pattern = new Regex(Regex.escape_string(home) + "(?=[/\"'\\s:;,)]|$)");
                return pattern.replace(text, -1, 0, "~");
            } catch (RegexError e) {
                return text.replace(home + "/", "~/");
            }
        }

        // Lowercase ASCII letters, digits and hyphens, so the dots in the
        // filename stay field separators.
        private static string application_slug(string apk_path) {
            var slug = slugify(ApkDisplayName.resolve(apk_path) ?? "");
            if (slug == "") {
                slug = slugify(ApkDisplayName.package_name(apk_path) ?? "");
            }
            if (slug == "") {
                var basename = Path.get_basename(apk_path);
                if (basename.down().has_suffix(".apk")) {
                    basename = basename.substring(0, basename.length - 4);
                }
                slug = slugify(basename);
            }
            return slug != "" ? slug : "application";
        }

        private static string slugify(string text) {
            var slug = new StringBuilder();
            bool pending_dash = false;
            foreach (var c in text.down().to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
                    if (pending_dash && slug.len > 0) {
                        slug.append_c('-');
                    }
                    slug.append_c(c);
                    pending_dash = false;
                } else {
                    pending_dash = true;
                }
            }
            return slug.str;
        }

        // Adds "apkManager" and "system" members to an open JSON object. Shared
        // by the error export and the debug JSON so both carry the same report.
        public static async void append_report_info(Json.Builder root) {
            root.set_member_name("apkManager");
            root.begin_object();
            root.set_member_name("name").add_string_value(APPLICATION_NAME);
            root.set_member_name("version").add_string_value(APPLICATION_VERSION);
            root.set_member_name("repository").add_string_value(REPOSITORY_URL);
            root.end_object();

            root.set_member_name("system");
            root.begin_object();

            var distro = HostDistro.detect();
            var uts = Posix.utsname();
            root.set_member_name("linux");
            root.begin_object();
            root.set_member_name("distribution").add_string_value(distro.pretty_name);
            root.set_member_name("id").add_string_value(distro.id);
            root.set_member_name("versionId").add_string_value(distro.version_id);
            root.set_member_name("basedOn").add_string_value(
                distro.matched_by_id_like ? (distro.family_name ?? "") : ""
            );
            root.set_member_name("kernelRelease").add_string_value(uts.release);
            root.set_member_name("kernelVersion").add_string_value(uts.version);
            root.set_member_name("architecture").add_string_value(uts.machine);
            root.end_object();

            root.set_member_name("displayServer");
            root.begin_object();
            root.set_member_name("sessionType").add_string_value(env_or_empty("XDG_SESSION_TYPE"));
            root.set_member_name("display").add_string_value(env_or_empty("DISPLAY"));
            root.set_member_name("waylandDisplay").add_string_value(env_or_empty("WAYLAND_DISPLAY"));
            string vendor, release;
            yield x_server_info(out vendor, out release);
            root.set_member_name("xServerVendor").add_string_value(vendor);
            root.set_member_name("xServerVersion").add_string_value(release);
            root.end_object();

            var desktop = env_or_empty("XDG_CURRENT_DESKTOP");
            root.set_member_name("desktopEnvironment");
            root.begin_object();
            root.set_member_name("name").add_string_value(desktop);
            root.set_member_name("session").add_string_value(env_or_empty("DESKTOP_SESSION"));
            root.set_member_name("version").add_string_value(yield desktop_version(desktop));
            root.end_object();

            string java_path, java_version, java_runtime;
            yield java_info(out java_path, out java_version, out java_runtime);
            root.set_member_name("java");
            root.begin_object();
            root.set_member_name("path").add_string_value(java_path);
            root.set_member_name("version").add_string_value(java_version);
            root.set_member_name("runtime").add_string_value(java_runtime);
            root.end_object();

            root.end_object();
        }

        private static string env_or_empty(string name) {
            return Environment.get_variable(name) ?? "";
        }

        // Combined stdout and stderr, or "" if the program is missing or fails to start.
        private static async string command_output(string[] argv) {
            if (Environment.find_program_in_path(argv[0]) == null) {
                return "";
            }
            try {
                var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                string? output = null;
                yield proc.communicate_utf8_async(null, null, out output, null);
                return (output ?? "").strip();
            } catch (Error e) {
                return "";
            }
        }

        // Xorg itself refuses -version for non-console users, so ask the
        // running server through xdpyinfo (x11-utils).
        private static async void x_server_info(out string vendor, out string release) {
            vendor = "";
            release = "";
            if (env_or_empty("DISPLAY") == "") {
                return;
            }
            var info = yield command_output({ "xdpyinfo" });
            foreach (var line in info.split("\n")) {
                if (line.has_prefix("vendor string:")) {
                    vendor = line.substring("vendor string:".length).strip();
                } else if (line.has_prefix("vendor release number:")) {
                    release = line.substring("vendor release number:".length).strip();
                }
            }
            // X.Org packs 1.21.1.11 as 12101011.
            if (vendor.contains("X.Org") && release.length == 8) {
                var number = int.parse(release);
                release = "%d.%d.%d.%d".printf(
                    number / 10000000, number / 100000 % 100, number / 1000 % 100, number % 1000
                );
            }
        }

        private static async string desktop_version(string desktop) {
            var name = desktop.down();
            string[] argv;
            if (name.contains("cinnamon")) {
                argv = { "cinnamon", "--version" };
            } else if (name.contains("gnome")) {
                argv = { "gnome-shell", "--version" };
            } else if (name.contains("kde")) {
                argv = { "plasmashell", "--version" };
            } else if (name.contains("xfce")) {
                argv = { "xfce4-session", "--version" };
            } else if (name.contains("mate")) {
                argv = { "mate-session", "--version" };
            } else if (name.contains("lxqt")) {
                argv = { "lxqt-session", "--version" };
            } else {
                return "";
            }
            return (yield command_output(argv)).split("\n")[0].strip();
        }

        private static async void java_info(out string path, out string version, out string runtime) {
            path = "";
            version = "";
            runtime = "";
            var java = Environment.find_program_in_path("java");
            if (java == null) {
                return;
            }
            path = Posix.realpath(java) ?? java;
            var lines = (yield command_output({ "java", "-version" })).split("\n");
            if (lines.length > 0) {
                var first = lines[0];
                var open = first.index_of_char('"');
                var close = open >= 0 ? first.index_of_char('"', open + 1) : -1;
                version = close > open ? first.substring(open + 1, close - open - 1) : first.strip();
            }
            if (lines.length > 1) {
                runtime = lines[1].strip();
            }
        }
    }
}
