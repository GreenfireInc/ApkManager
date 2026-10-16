using ApkManager.Core;
using ApkManager.Windows;

namespace ApkManager {
    public class Application : Adw.Application {
        private MainWindow? main_window;
        private DecodeSessionRegistry registry;
        private static bool opt_version = false;

        private const OptionEntry[] options = {
            { "version", 0, 0, OptionArg.NONE, ref opt_version, "Display version number", null },
            { null }
        };

        public Application() {
            Object(
                application_id: Core.APPLICATION_ID,
                flags: ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE
            );
            registry = new DecodeSessionRegistry();
            add_main_option_entries(options);
            set_option_context_parameter_string("[FILE...]");
            set_option_context_summary("Android APK inspector powered by Apktool");
        }

        protected override void startup() {
            base.startup();
            FileManagerIcons.sync_from_settings();
            // Exported over D-Bus with the app, so a newer launcher can ask an
            // older primary instance to exit instead of handing its files to it.
            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => {
                quit();
            });
            add_action(quit_action);
        }

        protected override void activate() {
            ensure_main_window();
            main_window.present();
        }

        // GApplication is single-instance: every later `apk-manager foo.apk`
        // forwards the file to whichever process already owns the bus name.
        // After `meson install` that owner is usually the old executable, which
        // has been deleted on disk but keeps running old code, so new fixes never
        // show up until it is closed by hand. Replace such an owner before run().
        public static void retire_stale_instance() {
            uint32 pid;
            if (!primary_instance_pid(out pid) || pid == (uint32) Posix.getpid()) {
                return;
            }

            string? theirs = exe_of(pid);
            string? ours = exe_of((uint32) Posix.getpid());
            bool stale = theirs == null
                || theirs.has_suffix(" (deleted)")
                || (ours != null && theirs != ours);
            if (!stale) {
                return;
            }

            message("Replacing ApkManager instance %u (%s) with %s", pid, theirs ?? "unknown", ours ?? "this binary");
            ask_remote_quit();
            if (!wait_for_exit(pid, 1500)) {
                Posix.kill((Posix.pid_t) pid, Posix.Signal.TERM);
                wait_for_exit(pid, 3000);
            }
            wait_for_name_release(3000);
        }

        private static bool primary_instance_pid(out uint32 pid) {
            pid = 0;
            try {
                var bus = Bus.get_sync(BusType.SESSION);
                var reply = bus.call_sync(
                    "org.freedesktop.DBus",
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "GetConnectionUnixProcessID",
                    new Variant("(s)", Core.APPLICATION_ID),
                    new VariantType("(u)"),
                    DBusCallFlags.NONE,
                    1000
                );
                reply.get("(u)", out pid);
                return pid != 0;
            } catch (Error e) {
                // No owner, or no session bus: nothing to retire.
                return false;
            }
        }

        private static string? exe_of(uint32 pid) {
            try {
                return FileUtils.read_link("/proc/%u/exe".printf(pid));
            } catch (FileError e) {
                return null;
            }
        }

        private static void ask_remote_quit() {
            try {
                var bus = Bus.get_sync(BusType.SESSION);
                var object_path = "/" + Core.APPLICATION_ID.replace(".", "/");
                var actions = DBusActionGroup.get(bus, Core.APPLICATION_ID, object_path);
                // Older binaries have no app.quit; the call is then a no-op.
                actions.activate_action("quit", null);
                bus.flush_sync();
            } catch (Error e) {
                // fall through to SIGTERM
            }
        }

        private static bool wait_for_exit(uint32 pid, int timeout_ms) {
            var proc_dir = "/proc/%u".printf(pid);
            int waited = 0;
            while (waited < timeout_ms) {
                if (!FileUtils.test(proc_dir, FileTest.EXISTS)) {
                    return true;
                }
                Thread.usleep(50 * 1000);
                waited += 50;
            }
            return !FileUtils.test(proc_dir, FileTest.EXISTS);
        }

        private static void wait_for_name_release(int timeout_ms) {
            int waited = 0;
            uint32 pid;
            while (waited < timeout_ms && primary_instance_pid(out pid)) {
                Thread.usleep(50 * 1000);
                waited += 50;
            }
        }

        protected override void open(File[] files, string hint) {
            if (files.length == 0) {
                activate();
                return;
            }

            foreach (var file in files) {
                var path = file.get_path();
                if (path == null || !ApkArchive.is_apk_path(path)) {
                    continue;
                }
                show_open_window(path);
            }
        }

        protected override int command_line(ApplicationCommandLine command_line) {
            if (opt_version) {
                command_line.print("ApkManager %s\n", Core.APPLICATION_VERSION);
                return 0;
            }

            var args = command_line.get_arguments();
            bool opened_apk = false;
            for (int i = 1; i < args.length; i++) {
                if (ApkArchive.is_apk_path(args[i])) {
                    show_open_window(args[i]);
                    opened_apk = true;
                }
            }

            if (!opened_apk) {
                ensure_main_window();
                main_window.present();
            }
            return 0;
        }

        private void ensure_main_window() {
            if (main_window == null) {
                main_window = new MainWindow(this, registry);
            }
        }

        private void show_open_window(string apk_path) {
            ensure_main_window();
            var window = new OpenWindow(this, apk_path);
            window.inspect_requested.connect((path) => {
                main_window.open_apk(path);
            });
            window.install_requested.connect((path) => {
                main_window.open_apk(path);
            });
            window.present();
        }
    }
}
