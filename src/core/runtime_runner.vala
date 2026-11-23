namespace ApkManager.Core {
    public errordomain RuntimeRunError {
        NOT_INSTALLED,
        FAILED
    }

    public delegate void RuntimeLateFailure(string message);

    // One Debug run. Connect to line and exited before passing it to
    // RuntimeRunner.start_atl_debug or start_lepton_debug.
    public class RuntimeDebugSession : Object {
        public signal void line(string stream, string text);
        public signal void exited(string summary);

        public RuntimeEngine engine { get; set; default = RuntimeEngine.ANDROID_TRANSLATION_LAYER; }
        public string[] command = {};
        // KEY=VALUE pairs set on top of ApkManager's own environment.
        public string[] environment = {};
        public string log_path = "";
        public Cancellable cancellable = new Cancellable();

        internal Subprocess? main = null;
        internal Subprocess? logcat = null;
        internal string lepton_context = "";
        internal int64 started_at = 0;

        public void stop() {
            cancellable.cancel();
            if (logcat != null) {
                logcat.force_exit();
            }
            if (main != null) {
                // Lepton tears its container down (and dumps logcat) on SIGTERM.
                if (engine == RuntimeEngine.LEPTON) {
                    main.send_signal(Posix.Signal.TERM);
                } else {
                    main.force_exit();
                }
            }
        }
    }

    // Lepton's launcher log for the last run, read after a failure.
    public class RuntimeLog : Object {
        public string path = "";
        public string[] lines = {};
        public string crash_path = "";
        public string[] crash_lines = {};
    }

    // Starts the APK with the runtime chosen in Preferences. Waydroid's launch
    // command returns once Android has the activity. Android Translation Layer
    // and Lepton keep running, so this returns once the process has stayed up
    // for a moment and reports a later crash through late_failure.
    public class RuntimeRunner : Object {
        private const int STARTUP_WAIT_MS = 2500;
        private const int WAYDROID_SESSION_POLLS = 15;
        // Same socket the steam-lepton launcher from the install dialog uses.
        private const string LEPTON_WESTON_SOCKET = "wayland-lepton";
        private const int WESTON_START_POLLS = 50;
        private const int STEAM_START_POLLS = 120;
        private const int LEPTON_SUMMARY_LINES = 8;
        private const string LEPTON_BOOTED = "Boot complete!";

        private static HashTable<string, int64?>? lepton_launches = null;
        private static Regex? ansi_escape = null;
        private static Regex? logcat_priority = null;

        public static async void run(
            RuntimeEngine engine,
            string apk_path,
            owned RuntimeLateFailure? late_failure
        ) throws Error {
            switch (engine) {
            case RuntimeEngine.ANDROID_TRANSLATION_LAYER:
                yield run_android_translation_layer(apk_path, (owned) late_failure);
                break;
            case RuntimeEngine.LEPTON:
                yield run_lepton(apk_path, (owned) late_failure);
                break;
            default:
                yield run_waydroid(apk_path);
                break;
            }
        }

        private static async void run_android_translation_layer(
            string apk_path,
            owned RuntimeLateFailure? late_failure
        ) throws Error {
            var program = atl_program();
            if (program == null) {
                throw new RuntimeRunError.NOT_INSTALLED("Android Translation Layer is not installed.");
            }
            yield launch_and_watch({ program, apk_path }, (launcher) => {
                // On X11, GTK inside ATL picks GLX unless this is set, and the app's GL surface stays blank.
                if (Environment.get_variable("XDG_SESSION_TYPE") == "x11") {
                    launcher.setenv("GDK_DEBUG", "gl-egl", false);
                }
            }, (owned) late_failure);
        }

        // Verbose Android logs plus ART's JNI trace, from
        // docs/research/20261121.research.apkmanager.android-translation-layer.debug-output.grok-4.7.md.
        // The process keeps running after startup, so lines are delivered as they are printed.
        public static void start_atl_debug(RuntimeDebugSession session, string apk_path) throws Error {
            var program = atl_program();
            if (program == null) {
                throw new RuntimeRunError.NOT_INSTALLED("Android Translation Layer is not installed.");
            }
            session.engine = RuntimeEngine.ANDROID_TRANSLATION_LAYER;
            session.command = { program, apk_path, "-X", "-verbose:jni" };
            string[] environment = { "ANDROID_LOG_TAGS=*:v" };
            if (Environment.get_variable("XDG_SESSION_TYPE") == "x11") {
                environment += "GDK_DEBUG=gl-egl";
            }
            session.environment = environment;
            spawn_debug(session);
        }

        // From docs/research/20261121.research.apkmanager.lepton.debug-output.claude-opus-5.5.md:
        // the launcher's output first, then the container's logcat once Android
        // has booted, then Lepton's logcat dumps after it exits.
        public static async void start_lepton_debug(RuntimeDebugSession session, string apk_path) throws Error {
            var launch = yield prepare_lepton(apk_path);
            if (session.cancellable.is_cancelled()) {
                return;
            }
            session.engine = RuntimeEngine.LEPTON;
            session.command = launch.command;
            string[] environment = launch.environment;
            environment += "LEPTON_DUMP_LOGCAT=1";
            session.environment = environment;
            session.lepton_context = launch.context;
            session.log_path = lepton_log_path(launch.context);
            spawn_debug(session);
        }

        private static void spawn_debug(RuntimeDebugSession session) throws Error {
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            launcher.set_child_setup(detach_child);
            set_environment(launcher, session.environment);
            try {
                session.main = launcher.spawnv(session.command);
            } catch (Error e) {
                throw new RuntimeRunError.FAILED(e.message);
            }
            session.started_at = get_real_time();
            if (session.lepton_context != "") {
                note_lepton_launch(session.lepton_context);
            }
            pump_debug_lines.begin(session, session.main, "stdout", "stderr");
            watch_debug_exit.begin(session);
        }

        private static void start_lepton_logcat(RuntimeDebugSession session) {
            if (session.logcat != null || session.cancellable.is_cancelled()) {
                return;
            }
            var podman = Environment.find_program_in_path("podman");
            if (podman == null) {
                return;
            }
            // Not `lepton logcat`: that asks podman for a terminal and waits on Lepton's lock.
            string[] argv = { podman, "exec", "lepton-" + session.lepton_context, "/system/bin/logcat", "-v", "threadtime" };
            try {
                session.logcat = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            } catch (Error e) {
                session.line("apkmanager", "Could not attach to Lepton's logcat: %s".printf(e.message));
                return;
            }
            session.line("apkmanager", "Attached to Android's logcat: %s".printf(string.joinv(" ", argv)));
            pump_debug_lines.begin(session, session.logcat, "logcat", "logcat");
        }

        private static async void watch_debug_exit(RuntimeDebugSession session) {
            var proc = session.main;
            try {
                yield proc.wait_async(null);
            } catch (Error e) {
            }
            if (session.logcat != null) {
                session.logcat.force_exit();
            }
            var label = AppSettings.runtime_engine_label(session.engine);
            string summary;
            if (proc.get_if_exited()) {
                summary = "%s exited with status %d".printf(label, proc.get_exit_status());
            } else {
                summary = "%s was stopped".printf(label);
            }
            if (session.engine == RuntimeEngine.LEPTON) {
                var buffers = session.logcat == null
                    ? new string[] { "crash", "main", "system" }
                    : new string[] { "crash" };
                foreach (var buffer in buffers) {
                    var path = lepton_dump_path(session.lepton_context, buffer);
                    foreach (var text in fresh_lines(path, session.started_at)) {
                        session.line("logcat-" + buffer, text);
                    }
                }
            }
            session.line("apkmanager", summary);
            session.exited(summary);
        }

        // Android's threadtime lines count by priority, anything else by keyword.
        public static bool debug_error(string text) {
            if (logcat_priority == null) {
                try {
                    logcat_priority = new Regex("^\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d\\.\\d+\\s+\\d+\\s+\\d+\\s+([VDIWEF])\\s");
                } catch (RegexError e) {
                }
            }
            if (logcat_priority != null) {
                MatchInfo match;
                if (logcat_priority.match(text, 0, out match)) {
                    var priority = match.fetch(1);
                    return priority == "E" || priority == "F";
                }
            }
            if (text.contains("libVkLayer_fossilize") || text.contains("Continuing without fossilize")) {
                return false;
            }
            return atl_debug_error(text);
        }

        // "Error: pasta failed with exit code 1:" carries its reason on the next line.
        public static bool debug_error_continues(string text) {
            return text.has_suffix(":") && debug_error(text);
        }

        public static bool atl_debug_error(string text) {
            if (text.contains("failed to utilize FUSE")) {
                return false;
            }
            if (/^[0-9]+%$/.match(text)) {
                return false;
            }
            var folded = text.down();
            return folded.contains("exception")
                || folded.contains("error")
                || folded.contains("fatal")
                || folded.contains("caused by")
                || folded.contains("unsatisfiedlink")
                || folded.contains("cannot locate symbol")
                || folded.contains("nosuch")
                || folded.contains("noclass");
        }

        private static async void pump_debug_lines(
            RuntimeDebugSession session,
            Subprocess proc,
            string stdout_name,
            string stderr_name
        ) {
            var stdout_pipe = proc.get_stdout_pipe();
            var stderr_pipe = proc.get_stderr_pipe();
            if (stderr_pipe != null) {
                pump_stream.begin(session, new DataInputStream(stderr_pipe), stderr_name);
            }
            if (stdout_pipe != null) {
                yield pump_stream(session, new DataInputStream(stdout_pipe), stdout_name);
            }
        }

        private static async void pump_stream(RuntimeDebugSession session, DataInputStream stream, string which) {
            var cancellable = session.cancellable;
            try {
                while (!cancellable.is_cancelled()) {
                    size_t length;
                    var line = yield stream.read_line_utf8_async(Priority.DEFAULT, cancellable, out length);
                    if (line == null) {
                        return;
                    }
                    foreach (var piece in strip_ansi(line).split("\r")) {
                        var text = piece.strip();
                        if (text == "") {
                            continue;
                        }
                        session.line(which, text);
                        if (session.lepton_context != "" && which == "stdout" && text.contains(LEPTON_BOOTED)) {
                            start_lepton_logcat(session);
                        }
                    }
                }
            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    session.line(which, e.message);
                }
            }
        }

        private static string strip_ansi(string text) {
            if (!text.contains("\x1b")) {
                return text;
            }
            try {
                if (ansi_escape == null) {
                    ansi_escape = new Regex("\\x1b\\[[0-9;]*[A-Za-z]");
                }
                return ansi_escape.replace(text, -1, 0, "");
            } catch (RegexError e) {
                return text;
            }
        }

        private static void set_environment(SubprocessLauncher launcher, string[] environment) {
            foreach (var pair in environment) {
                var eq = pair.index_of_char('=');
                if (eq > 0) {
                    launcher.setenv(pair.substring(0, eq), pair.substring(eq + 1), true);
                }
            }
        }

        private class LeptonLaunch {
            public string context;
            public string[] command;
            public string[] environment;
        }

        private static async LeptonLaunch prepare_lepton(string apk_path) throws Error {
            var home = Environment.get_home_dir();
            if (Path.get_dirname(apk_path) == home) {
                throw new RuntimeRunError.FAILED(
                    "Lepton cannot run an APK that sits directly in the home folder. Move it into a subfolder and try again."
                );
            }
            var tool = find_lepton();
            if (tool == null) {
                throw new RuntimeRunError.NOT_INSTALLED("Lepton is not installed.");
            }
            // Lepton draws on the WAYLAND_DISPLAY it inherits, and inherits ours,
            // not Steam's. Weston comes first so a Steam we start shares it too.
            var wayland_display = yield ensure_wayland_display();
            yield ensure_steam(wayland_display);
            var app_id = lepton_app_id(apk_path);
            var compat = Path.build_filename(tool.steam_root, "steamapps", "compatdata", app_id);
            if (DirUtils.create_with_parents(compat, 0755) != 0) {
                throw new RuntimeRunError.FAILED("Could not create %s".printf(compat));
            }
            var launch = new LeptonLaunch();
            // Lepton names the run's container and log after SteamAppId.
            launch.context = "steamlaunch-" + app_id;
            launch.command = { tool.program, "waitforexitandrun", "--", apk_path };
            launch.environment = {
                "SteamAppId=" + app_id,
                "STEAM_COMPAT_DATA_PATH=" + compat,
                "STEAM_COMPAT_CLIENT_INSTALL_PATH=" + tool.steam_root,
                "STEAM_COMPAT_INSTALL_PATH=" + Path.get_dirname(apk_path),
                "WAYLAND_DISPLAY=" + wayland_display
            };
            return launch;
        }

        private static async void run_lepton(
            string apk_path,
            owned RuntimeLateFailure? late_failure
        ) throws Error {
            var launch = yield prepare_lepton(apk_path);
            var context = launch.context;
            var environment = launch.environment;
            note_lepton_launch(context);
            // Lepton tees its output into its log file once it starts, so the
            // reason for a failure is read back from there.
            yield launch_and_watch(
                launch.command,
                (launcher) => {
                    set_environment(launcher, environment);
                },
                (owned) late_failure,
                (captured) => {
                    return lepton_failure(context, captured);
                }
            );
        }

        private static string lepton_app_id(string apk_path) {
            return steam_app_id(ApkDisplayName.package_name(apk_path) ?? Path.get_basename(apk_path));
        }

        private static void note_lepton_launch(string context) {
            if (lepton_launches == null) {
                lepton_launches = new HashTable<string, int64?>(str_hash, str_equal);
            }
            lepton_launches.insert(context, get_real_time());
        }

        // Without SteamVR, the x86_64 port logs to ~/.local/share/lepton/logs.
        private static string lepton_log_dir() {
            return Path.build_filename(Environment.get_user_data_dir(), "lepton", "logs");
        }

        private static string lepton_log_path(string context) {
            return Path.build_filename(lepton_log_dir(), "lepton-%s.log".printf(context));
        }

        private static string lepton_dump_path(string context, string buffer) {
            return Path.build_filename(lepton_log_dir(), "lepton-logcats", context, "logcat-%s.log".printf(buffer));
        }

        // The file's lines, if it was written after since (microseconds, real time).
        private static string[] fresh_lines(string path, int64 since) {
            try {
                var info = File.new_for_path(path).query_info(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                var modified = info.get_modification_date_time();
                if (modified == null || modified.to_unix() * 1000000 + modified.get_microsecond() < since - 1000000) {
                    return {};
                }
                string text;
                FileUtils.get_contents(path, out text);
                string[] lines = {};
                foreach (var raw in strip_ansi(text).split("\n")) {
                    var line = raw.strip();
                    if (line != "") {
                        lines += line;
                    }
                }
                return lines;
            } catch (Error e) {
                return {};
            }
        }

        // Lepton appends every run to the same file; this run starts at its last header.
        private static string[] lepton_last_run(string[] lines) {
            int start = 0;
            for (int i = lines.length - 1; i >= 0; i--) {
                if (lines[i].has_prefix("Lepton ") && lines[i].contains(" starting up at ")) {
                    start = i;
                    break;
                }
            }
            return lines[start:lines.length];
        }

        // For Lepton runs started by ApkManager in this session; null otherwise.
        public static RuntimeLog? runtime_log(RuntimeEngine engine, string apk_path) {
            if (engine != RuntimeEngine.LEPTON || lepton_launches == null) {
                return null;
            }
            var context = "steamlaunch-" + lepton_app_id(apk_path);
            var launched = lepton_launches.lookup(context);
            if (launched == null) {
                return null;
            }
            var log = new RuntimeLog();
            log.path = lepton_log_path(context);
            log.lines = lepton_last_run(fresh_lines(log.path, launched));
            log.crash_path = lepton_dump_path(context, "crash");
            log.crash_lines = fresh_lines(log.crash_path, launched);
            if (log.lines.length == 0 && log.crash_lines.length == 0) {
                return null;
            }
            return log;
        }

        private static bool lepton_noise(string line) {
            return line.contains("is not a running context")
                || line.has_prefix("steamlaunch-")
                || line.contains("libVkLayer_fossilize")
                || line.contains("Continuing without fossilize");
        }

        private static string lepton_failure(string context, string captured) {
            var launched = lepton_launches != null ? lepton_launches.lookup(context) : null;
            var path = lepton_log_path(context);
            var lines = launched != null ? lepton_last_run(fresh_lines(path, launched)) : new string[0];
            var picked = new GenericArray<string>();
            for (int i = 0; i < lines.length; i++) {
                var line = lines[i];
                if (lepton_noise(line)) {
                    continue;
                }
                var folded = line.down();
                var wanted = folded.contains("error") || folded.contains("failed")
                    || folded.contains("not found") || folded.contains("cannot") || folded.contains("denied");
                var continues = i > 0 && debug_error_continues(lines[i - 1]);
                if ((wanted || continues) && !picked.find_with_equal_func(line, str_equal)) {
                    picked.add(line);
                }
            }
            string[] summary = {};
            var first = int.max(0, (int) picked.length - LEPTON_SUMMARY_LINES);
            for (int i = first; i < picked.length; i++) {
                summary += picked[i];
            }
            if (launched != null) {
                string[] crash = {};
                foreach (var line in fresh_lines(lepton_dump_path(context, "crash"), launched)) {
                    if (debug_error(line)) {
                        crash += line;
                    }
                }
                if (crash.length > 0) {
                    summary += "Android crash log:";
                    foreach (var line in crash[int.max(0, crash.length - 4):crash.length]) {
                        summary += line;
                    }
                }
            }
            var text = string.joinv("\n", summary);
            if (text == "") {
                text = brief(captured);
            }
            if (text == "" && lines.length > 0) {
                text = string.joinv("\n", lines[int.max(0, lines.length - 5):lines.length]);
            }
            if (lines.length > 0) {
                text += "\n\nFull log: %s".printf(path);
            }
            return text;
        }

        // In a Wayland session, the session's display. On X11, a nested Weston
        // on LEPTON_WESTON_SOCKET, started if it isn't running yet.
        private static async string ensure_wayland_display() throws Error {
            var runtime_dir = Environment.get_user_runtime_dir();
            var session = Environment.get_variable("WAYLAND_DISPLAY");
            if (session != null && session != ""
                && FileUtils.test(Path.build_filename(runtime_dir, session), FileTest.EXISTS)) {
                return session;
            }
            var socket = Path.build_filename(runtime_dir, LEPTON_WESTON_SOCKET);
            if (FileUtils.test(socket, FileTest.EXISTS)) {
                return LEPTON_WESTON_SOCKET;
            }
            var weston = Environment.find_program_in_path("weston");
            if (weston == null) {
                throw new RuntimeRunError.FAILED(
                    "Lepton draws on Wayland, and this desktop is X11. Install Weston (re-run the Lepton install, or: sudo apt install weston), then try again."
                );
            }
            spawn_detached({
                weston, "--backend=x11", "--socket=" + LEPTON_WESTON_SOCKET, "--width=1280", "--height=800"
            });
            for (int i = 0; i < WESTON_START_POLLS; i++) {
                yield delay_ms(100);
                if (FileUtils.test(socket, FileTest.EXISTS)) {
                    return LEPTON_WESTON_SOCKET;
                }
            }
            throw new RuntimeRunError.FAILED("Weston did not start, so Lepton has no Wayland display to draw on.");
        }

        // Lepton bind-mounts ~/.steam/steam.pipe, and podman fails if it is missing.
        // The pipe can outlive Steam, so steam.pid is what says Steam is running.
        private static async void ensure_steam(string wayland_display) throws Error {
            if (steam_running()) {
                return;
            }
            var steam = first_executable({
                Environment.find_program_in_path("steam"), "/usr/games/steam", "/usr/bin/steam"
            });
            if (steam == null) {
                throw new RuntimeRunError.FAILED("Lepton needs the Steam client, and Steam is not installed.");
            }
            // Steam passes this to Lepton when an APK is started from its library.
            spawn_detached({ steam }, (launcher) => {
                launcher.setenv("WAYLAND_DISPLAY", wayland_display, true);
            });
            for (int i = 0; i < STEAM_START_POLLS; i++) {
                yield delay_ms(1000);
                if (steam_running()) {
                    return;
                }
            }
            throw new RuntimeRunError.FAILED(
                "Steam is still starting. Finish any update and sign in to Steam, then press Run again."
            );
        }

        private static bool steam_running() {
            var dot_steam = Path.build_filename(Environment.get_home_dir(), ".steam");
            if (!FileUtils.test(Path.build_filename(dot_steam, "steam.pipe"), FileTest.EXISTS)) {
                return false;
            }
            string pid;
            try {
                FileUtils.get_contents(Path.build_filename(dot_steam, "steam.pid"), out pid);
            } catch (FileError e) {
                return false;
            }
            pid = pid.strip();
            return pid != "" && FileUtils.test(Path.build_filename("/proc", pid), FileTest.IS_DIR);
        }

        private static async void run_waydroid(string apk_path) throws Error {
            var program = waydroid_program();
            if (program == null) {
                throw new RuntimeRunError.NOT_INSTALLED("Waydroid is not installed.");
            }

            var status = yield run_command({ program, "status" });
            if (status.text.down().contains("not initialized")) {
                throw new RuntimeRunError.FAILED("Waydroid is not initialized. Finish setup with waydroid init, then try again.");
            }
            if (!session_running(status.text)) {
                spawn_detached({ program, "session", "start" });
                var started = false;
                for (int i = 0; i < WAYDROID_SESSION_POLLS; i++) {
                    yield delay_ms(1000);
                    status = yield run_command({ program, "status" });
                    if (session_running(status.text)) {
                        started = true;
                        break;
                    }
                }
                if (!started) {
                    var extra = Environment.get_variable("XDG_SESSION_TYPE") == "x11"
                        ? " This session is X11. Waydroid draws on Wayland, so start it inside a Wayland compositor and try again."
                        : "";
                    throw new RuntimeRunError.FAILED(brief(status.text) + extra);
                }
            }

            var install = yield run_command({ program, "app", "install", apk_path });
            if (!install.ok && !install.text.down().contains("already installed")) {
                throw new RuntimeRunError.FAILED(
                    brief(install.text) != "" ? brief(install.text) : "Waydroid could not install the APK."
                );
            }

            var package = ApkDisplayName.package_name(apk_path);
            if (package == null || package == "") {
                throw new RuntimeRunError.FAILED("Could not read the APK package name, so Waydroid has nothing to launch.");
            }
            var launch = yield run_command({ program, "app", "launch", package });
            if (!launch.ok) {
                throw new RuntimeRunError.FAILED(
                    brief(launch.text) != "" ? brief(launch.text) : "Waydroid could not launch the APK."
                );
            }
        }

        private delegate void LaunchSetup(SubprocessLauncher launcher);
        private delegate string FailureDetail(string captured);

        private static async void launch_and_watch(
            string[] argv,
            owned LaunchSetup? setup,
            owned RuntimeLateFailure? late_failure,
            owned FailureDetail? detail = null
        ) throws Error {
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
            launcher.set_child_setup(detach_child);
            if (setup != null) {
                setup(launcher);
            }
            Subprocess proc;
            try {
                proc = launcher.spawnv(argv);
            } catch (Error e) {
                throw new RuntimeRunError.FAILED(e.message);
            }

            bool settled = false;
            string? failure = null;
            proc.communicate_utf8_async.begin(null, null, (obj, res) => {
                string? stdout_text = null;
                string? stderr_text = null;
                try {
                    proc.communicate_utf8_async.end(res, out stdout_text, out stderr_text);
                } catch (Error e) {
                    stderr_text = e.message;
                }
                if (!proc.get_successful()) {
                    var captured = (stderr_text ?? "") + "\n" + (stdout_text ?? "");
                    failure = detail != null ? detail(captured) : brief(captured);
                }
                if (!settled) {
                    settled = true;
                    launch_and_watch.callback();
                } else if (failure != null && late_failure != null) {
                    late_failure(failure);
                }
            });
            Timeout.add(STARTUP_WAIT_MS, () => {
                if (!settled) {
                    settled = true;
                    launch_and_watch.callback();
                }
                return Source.REMOVE;
            });
            yield;
            if (failure != null) {
                throw new RuntimeRunError.FAILED(failure);
            }
        }

        private static void detach_child() {
            Posix.setsid();
        }

        private class CommandResult {
            public bool ok;
            public string text;
        }

        private static async CommandResult run_command(string[] argv) throws Error {
            var result = new CommandResult();
            Subprocess proc;
            try {
                proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            } catch (Error e) {
                throw new RuntimeRunError.FAILED(e.message);
            }
            string? stdout_text = null;
            string? stderr_text = null;
            yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);
            result.ok = proc.get_successful();
            result.text = ((stdout_text ?? "") + "\n" + (stderr_text ?? "")).strip();
            return result;
        }

        // Android Translation Layer keeps each APK's app data in a folder named after the APK file.
        public static string atl_app_data_dir(string apk_path) {
            return Path.build_filename(
                Environment.get_user_data_dir(), "android_translation_layer", Path.get_basename(apk_path) + "_"
            );
        }

        // Empty when the runtime is not installed or does not report a version.
        public static async string runtime_version(RuntimeEngine engine) {
            switch (engine) {
            case RuntimeEngine.ANDROID_TRANSLATION_LAYER:
                var atl = atl_program();
                if (atl == null) {
                    return "";
                }
                var packaged = yield package_version(atl);
                return packaged != "" ? packaged : appimage_version(atl);
            case RuntimeEngine.LEPTON:
                var tool = find_lepton();
                if (tool == null) {
                    return "";
                }
                try {
                    string text;
                    FileUtils.get_contents(Path.build_filename(Path.get_dirname(tool.program), "version.txt"), out text);
                    return text.strip();
                } catch (FileError e) {
                    return "";
                }
            case RuntimeEngine.WAYDROID:
                var waydroid = waydroid_program();
                if (waydroid == null) {
                    return "";
                }
                try {
                    var result = yield run_command({ waydroid, "-V" });
                    if (result.ok && result.text != "") {
                        return result.text.split("\n")[0].strip();
                    }
                } catch (Error e) {
                }
                return yield package_version(waydroid);
            default:
                return "";
            }
        }

        // ISO 8601 local time; empty when the runtime is not installed or the date is unknown.
        public static async string runtime_build_date(RuntimeEngine engine) {
            DateTime? built = null;
            switch (engine) {
            case RuntimeEngine.ANDROID_TRANSLATION_LAYER:
                var atl = atl_program();
                if (atl == null) {
                    break;
                }
                built = atl_edge_build_date(yield runtime_version(engine));
                if (built == null) {
                    built = yield package_build_date(atl);
                }
                if (built == null) {
                    built = yield appimage_build_date(atl);
                }
                break;
            case RuntimeEngine.LEPTON:
                var tool = find_lepton();
                if (tool != null) {
                    // Lepton release archives keep version.txt's packaging time.
                    built = modified_time(Path.build_filename(Path.get_dirname(tool.program), "version.txt"));
                }
                break;
            case RuntimeEngine.WAYDROID:
                var waydroid = waydroid_program();
                if (waydroid != null) {
                    built = yield package_build_date(waydroid);
                }
                break;
            default:
                break;
            }
            return built != null ? built.to_local().format_iso8601() : "";
        }

        // Only trusted while the installed ATL is the build the manifest describes.
        private static DateTime? atl_edge_build_date(string version) {
            if (version == "") {
                return null;
            }
            try {
                var parser = new Json.Parser();
                parser.load_from_file(AppPaths.atl_edge_manifest);
                var manifest = parser.get_root().get_object();
                if (manifest.get_string_member_with_default("version", "") != version) {
                    return null;
                }
                return new DateTime.from_iso8601(manifest.get_string_member_with_default("builtAt", ""), null);
            } catch (Error e) {
                return null;
            }
        }

        // rpm records the build time; dpkg and pacman keep the packaged files' timestamps.
        private static async DateTime? package_build_date(string program) {
            var path = Posix.realpath(program) ?? program;
            try {
                if (Environment.find_program_in_path("rpm") != null) {
                    var stamp = yield run_command({ "rpm", "-qf", "--qf", "%{BUILDTIME}", path });
                    int64 seconds = 0;
                    if (stamp.ok && int64.try_parse(stamp.text, out seconds) && seconds > 0) {
                        return new DateTime.from_unix_utc(seconds);
                    }
                }
                if (Environment.find_program_in_path("dpkg-query") != null) {
                    var owner = yield run_command({ "dpkg-query", "-S", path });
                    if (owner.ok && owner.text.contains(":")) {
                        return modified_time(path);
                    }
                }
                if (Environment.find_program_in_path("pacman") != null) {
                    var owner = yield run_command({ "pacman", "-Qqo", path });
                    if (owner.ok) {
                        return modified_time(path);
                    }
                }
            } catch (Error e) {
            }
            return null;
        }

        private static HashTable<string, DateTime>? appimage_build_dates = null;

        // The image's root keeps the AppDir's time from when the AppImage was packed, which
        // the AppImage runtime exposes by mounting it. Cached per file and modification time.
        private static async DateTime? appimage_build_date(string program) {
            var path = Posix.realpath(program) ?? program;
            var stamp = modified_time(path);
            if (stamp == null) {
                return null;
            }
            var key = "%s\n%s".printf(path, stamp.to_unix().to_string());
            if (appimage_build_dates == null) {
                appimage_build_dates = new HashTable<string, DateTime>(str_hash, str_equal);
            }
            var cached = appimage_build_dates.lookup(key);
            if (cached != null) {
                return cached;
            }

            Subprocess proc;
            try {
                proc = new Subprocess.newv({ path, "--appimage-mount" }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            } catch (Error e) {
                return null;
            }
            var cancellable = new Cancellable();
            var timeout = Timeout.add_seconds(10, () => {
                cancellable.cancel();
                return Source.REMOVE;
            });
            DateTime? built = null;
            try {
                var output = new DataInputStream(proc.get_stdout_pipe());
                var mount = yield output.read_line_utf8_async(Priority.DEFAULT, cancellable);
                if (mount != null && mount.strip().has_prefix("/")) {
                    built = modified_time(mount.strip());
                }
            } catch (Error e) {
            }
            if (!cancellable.is_cancelled()) {
                Source.remove(timeout);
            }
            proc.send_signal(Posix.Signal.TERM);
            try {
                yield proc.wait_async(null);
            } catch (Error e) {
            }
            if (built != null) {
                appimage_build_dates.insert(key, built);
            }
            return built;
        }

        private static DateTime? modified_time(string path) {
            try {
                var info = File.new_for_path(path).query_info(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                return info.get_modification_date_time();
            } catch (Error e) {
                return null;
            }
        }

        // The dpkg or rpm version of the package that owns the file.
        private static async string package_version(string program) {
            var path = Posix.realpath(program) ?? program;
            try {
                if (Environment.find_program_in_path("dpkg-query") != null) {
                    var owner = yield run_command({ "dpkg-query", "-S", path });
                    if (owner.ok && owner.text.contains(":")) {
                        var package = owner.text.split("\n")[0].split(":")[0].strip();
                        var version = yield run_command({ "dpkg-query", "-W", "-f=${Version}", package });
                        if (version.ok && version.text != "") {
                            return version.text;
                        }
                    }
                }
                if (Environment.find_program_in_path("rpm") != null) {
                    var version = yield run_command({ "rpm", "-qf", "--qf", "%{VERSION}-%{RELEASE}", path });
                    if (version.ok && version.text != "" && !version.text.contains(" ")) {
                        return version.text;
                    }
                }
            } catch (Error e) {
            }
            return "";
        }

        // AppManager and appimaged record the AppImage's version in the desktop entry they write.
        private static string appimage_version(string program) {
            var path = Posix.realpath(program) ?? program;
            var dir_path = Path.build_filename(Environment.get_user_data_dir(), "applications");
            GLib.Dir dir;
            try {
                dir = Dir.open(dir_path);
            } catch (FileError e) {
                return "";
            }
            unowned string? name = null;
            while ((name = dir.read_name()) != null) {
                if (!name.has_suffix(".desktop")) {
                    continue;
                }
                var entry = new KeyFile();
                try {
                    entry.load_from_file(Path.build_filename(dir_path, name), KeyFileFlags.NONE);
                    var exec = entry.get_string("Desktop Entry", "Exec");
                    if (!exec.contains(path) || !entry.has_key("Desktop Entry", "X-AppImage-Version")) {
                        continue;
                    }
                    return entry.get_string("Desktop Entry", "X-AppImage-Version").strip();
                } catch (Error e) {
                    continue;
                }
            }
            return "";
        }

        private static void spawn_detached(string[] argv, owned LaunchSetup? setup = null) throws Error {
            try {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                launcher.set_child_setup(detach_child);
                if (setup != null) {
                    setup(launcher);
                }
                launcher.spawnv(argv);
            } catch (Error e) {
                throw new RuntimeRunError.FAILED(e.message);
            }
        }

        private static async void delay_ms(uint interval) {
            Timeout.add(interval, () => {
                delay_ms.callback();
                return Source.REMOVE;
            });
            yield;
        }

        private static bool session_running(string text) {
            foreach (var raw in text.split("\n")) {
                var line = raw.strip().down();
                if (line.has_prefix("session:") && line.contains("running")) {
                    return true;
                }
            }
            return false;
        }

        private static string brief(string text) {
            var piece = text.strip();
            var cr = piece.last_index_of_char('\r');
            if (cr >= 0) {
                piece = piece.substring(cr + 1).strip();
            }
            if (piece.length > 400) {
                piece = piece.substring(piece.length - 400);
            }
            return piece;
        }

        private static string? waydroid_program() {
            return first_executable({
                Environment.find_program_in_path("waydroid"),
                Environment.find_program_in_path("waydroid-launcher"),
                "/usr/bin/waydroid",
                "/usr/bin/waydroid-launcher",
                "/run/host/usr/bin/waydroid",
                "/run/host/usr/bin/waydroid-launcher"
            });
        }

        private static string? atl_program() {
            var found = first_executable({
                Environment.find_program_in_path("android-translation-layer"),
                "/usr/local/bin/android-translation-layer",
                "/usr/bin/android-translation-layer",
                "/run/host/usr/bin/android-translation-layer"
            });
            if (found != null) {
                return found;
            }
            var home = Environment.get_home_dir();
            string[] dirs = {
                Path.build_filename(home, "Applications"),
                Path.build_filename(home, ".local", "bin"),
                Path.build_filename(home, "Downloads")
            };
            foreach (var dir in dirs) {
                GLib.Dir handle;
                try {
                    handle = Dir.open(dir);
                } catch (FileError e) {
                    continue;
                }
                unowned string? name = null;
                while ((name = handle.read_name()) != null) {
                    var folded = name.down();
                    if (!folded.contains("android_translation_layer")
                        && !folded.contains("android translation layer")) {
                        continue;
                    }
                    var full = Path.build_filename(dir, name);
                    if (FileUtils.test(full, FileTest.IS_EXECUTABLE)) {
                        return full;
                    }
                }
            }
            return null;
        }

        private class LeptonTool {
            public string program;
            public string steam_root;
        }

        private static LeptonTool? find_lepton() {
            var home = Environment.get_home_dir();
            string[] roots = {
                Path.build_filename(home, ".local", "share", "Steam"),
                Path.build_filename(home, ".steam", "steam"),
                Path.build_filename(home, "snap", "steam", "common", ".local", "share", "Steam"),
                Path.build_filename(home, ".snap", "data", "steam", "common", ".local", "share", "Steam"),
                Path.build_filename(home, ".var", "app", "com.valvesoftware.Steam", ".local", "share", "Steam"),
                Path.build_filename(home, ".var", "app", "com.valvesoftware.Steam", "data", "Steam")
            };
            foreach (var root in roots) {
                var tool = lepton_tool_in(root, root);
                if (tool != null) {
                    return tool;
                }
            }
            var data_root = Path.build_filename(home, ".local", "share", "Steam");
            foreach (var dir in new string[] {
                "/usr/share/steam/compatibilitytools.d",
                "/usr/local/share/steam/compatibilitytools.d"
            }) {
                var tool = lepton_tool_in(dir, data_root);
                if (tool != null) {
                    return tool;
                }
            }
            foreach (var root in roots) {
                var tool = lepton_in_libraries(Path.build_filename(root, "steamapps", "libraryfolders.vdf"));
                if (tool != null) {
                    return tool;
                }
            }
            return null;
        }

        private static LeptonTool? lepton_tool_in(string root, string steam_root) {
            var official = Path.build_filename(root, "steamapps", "common", "Lepton", "lepton");
            if (FileUtils.test(Path.build_filename(root, "steamapps", "appmanifest_3029110.acf"), FileTest.EXISTS)
                && FileUtils.test(official, FileTest.EXISTS)) {
                var tool = new LeptonTool();
                tool.program = official;
                tool.steam_root = steam_root;
                return tool;
            }
            var port = Path.build_filename(root, "compatibilitytools.d", "lepton-x86_64", "lepton");
            if (FileUtils.test(port, FileTest.EXISTS)) {
                var tool = new LeptonTool();
                tool.program = port;
                tool.steam_root = steam_root;
                return tool;
            }
            var nested = Path.build_filename(root, "lepton-x86_64", "lepton");
            if (FileUtils.test(nested, FileTest.EXISTS)) {
                var tool = new LeptonTool();
                tool.program = nested;
                tool.steam_root = steam_root;
                return tool;
            }
            return null;
        }

        private static LeptonTool? lepton_in_libraries(string vdf_path) {
            string contents;
            try {
                if (!FileUtils.get_contents(vdf_path, out contents)) {
                    return null;
                }
            } catch (FileError e) {
                return null;
            }
            int cursor = 0;
            while (true) {
                var at = contents.index_of("\"path\"", cursor);
                if (at < 0) {
                    return null;
                }
                cursor = at + 6;
                var library = next_quoted(contents, ref cursor);
                if (library == null) {
                    continue;
                }
                var tool = lepton_tool_in(library, library);
                if (tool != null) {
                    return tool;
                }
            }
        }

        private static string? next_quoted(string text, ref int cursor) {
            var start = text.index_of_char('"', cursor);
            if (start < 0) {
                return null;
            }
            var end = text.index_of_char('"', start + 1);
            if (end < 0) {
                return null;
            }
            cursor = end + 1;
            return text.substring(start + 1, end - start - 1);
        }

        private static string steam_app_id(string key) {
            var checksum = new Checksum(ChecksumType.SHA256);
            checksum.update(key.data, key.length);
            var hex = checksum.get_string();
            uint32 mixed = 0;
            for (int i = 0; i < 8 && i < hex.length; i++) {
                mixed = (mixed << 4) | hex_value(hex[i]);
            }
            uint32 id = 2800000000u + (mixed % 70000000u);
            return id.to_string();
        }

        private static uint32 hex_value(unichar c) {
            if (c >= '0' && c <= '9') {
                return (uint32) (c - '0');
            }
            if (c >= 'a' && c <= 'f') {
                return (uint32) (c - 'a' + 10);
            }
            if (c >= 'A' && c <= 'F') {
                return (uint32) (c - 'A' + 10);
            }
            return 0;
        }

        private static string? first_executable(string?[] candidates) {
            foreach (var candidate in candidates) {
                if (candidate != null && candidate != "" && FileUtils.test(candidate, FileTest.IS_EXECUTABLE)) {
                    return candidate;
                }
            }
            return null;
        }
    }
}
