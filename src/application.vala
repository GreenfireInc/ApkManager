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

        protected override void activate() {
            ensure_main_window();
            main_window.present();
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

        protected override int command_line(string[] command_line) {
            if (opt_version) {
                print("ApkManager %s\n", Core.APPLICATION_VERSION);
                return 0;
            }
            return base.command_line(command_line);
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
            window.present();
        }
    }
}
