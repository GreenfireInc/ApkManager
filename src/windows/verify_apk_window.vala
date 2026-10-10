using ApkManager.Core;

namespace ApkManager.Windows {
    public class VerifyApkWindow : Adw.Window {
        private string apk_path;
        private Gtk.Entry hash_entry;
        private Gtk.Label result_label;
        private Gtk.Label detail_label;
        private Gtk.Spinner spinner;
        private Gtk.Button verify_button;

        public VerifyApkWindow(Gtk.Window parent, string path) {
            Object(
                transient_for: parent,
                modal: true,
                title: "Verify APK",
                default_width: 520,
                default_height: 220,
                destroy_with_parent: true
            );
            apk_path = path;
            build_ui();
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            header.title_widget = new Adw.WindowTitle(
                "Verify APK",
                Path.get_basename(apk_path)
            );
            toolbar.add_top_bar(header);

            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            root.margin_top = 12;
            root.margin_bottom = 12;
            root.margin_start = 12;
            root.margin_end = 12;
            root.valign = Gtk.Align.START;
            root.vexpand = false;
            toolbar.content = root;

            var intro = new Gtk.Label(
                "Enter the expected SHA256 digest for this APK. ApkManager will hash the file on disk and compare."
            );
            intro.xalign = 0;
            intro.wrap = true;
            intro.add_css_class("dim-label");
            root.append(intro);

            hash_entry = new Gtk.Entry();
            hash_entry.placeholder_text = "64-character SHA256 hex digest";
            hash_entry.hexpand = true;
            hash_entry.activate.connect(on_verify_clicked);
            root.append(hash_entry);

            var action_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            action_row.halign = Gtk.Align.CENTER;
            action_row.margin_bottom = 0;
            verify_button = new Gtk.Button.with_label("Verify");
            verify_button.add_css_class("suggested-action");
            verify_button.halign = Gtk.Align.CENTER;
            verify_button.clicked.connect(on_verify_clicked);
            action_row.append(verify_button);

            spinner = new Gtk.Spinner();
            spinner.visible = false;
            action_row.append(spinner);
            root.append(action_row);

            result_label = new Gtk.Label("");
            result_label.xalign = 0;
            result_label.wrap = true;
            result_label.visible = false;
            root.append(result_label);

            detail_label = new Gtk.Label("");
            detail_label.xalign = 0;
            detail_label.wrap = true;
            detail_label.selectable = true;
            detail_label.add_css_class("dim-label");
            detail_label.visible = false;
            root.append(detail_label);
        }

        private void on_verify_clicked() {
            clear_result();
            var expected = normalize_sha256(hash_entry.get_text());
            if (!is_valid_sha256(expected)) {
                show_result(
                    false,
                    "Enter a valid 64-character SHA256 hex digest.",
                    null
                );
                return;
            }

            verify_button.sensitive = false;
            hash_entry.sensitive = false;
            spinner.visible = true;
            spinner.start();
            run_verify.begin(expected);
        }

        private async void run_verify(string expected) {
            string? actual = yield compute_sha256_async(apk_path);

            spinner.stop();
            spinner.visible = false;
            verify_button.sensitive = true;
            hash_entry.sensitive = true;

            if (actual == null) {
                show_result(false, "Could not compute SHA256 for this file.", null);
                return;
            }

            actual = normalize_sha256(actual);
            if (expected == actual) {
                show_result(
                    true,
                    "SHA256 matches. The file matches the expected digest.",
                    "Computed: %s".printf(actual)
                );
            } else {
                show_result(
                    false,
                    "SHA256 does not match. The file may be corrupt, incomplete, or not the expected build.",
                    "Expected: %s\nComputed: %s".printf(expected, actual)
                );
            }
        }

        private async string? compute_sha256_async(string path) {
            string? result = null;
            new Thread<void>.try("apk-sha256", () => {
                result = ApkArchive.compute_sha256(path);
                Idle.add(compute_sha256_async.callback);
            });
            yield;
            return result;
        }

        private void clear_result() {
            result_label.visible = false;
            detail_label.visible = false;
            result_label.remove_css_class("success");
            result_label.remove_css_class("error");
        }

        private void show_result(bool success, string message, string? detail) {
            result_label.label = message;
            result_label.visible = true;
            if (success) {
                result_label.add_css_class("success");
            } else {
                result_label.add_css_class("error");
            }

            if (detail != null && detail.strip() != "") {
                detail_label.label = detail;
                detail_label.visible = true;
            } else {
                detail_label.visible = false;
            }
        }

        private static string normalize_sha256(string input) {
            var normalized = input.strip().down();
            if (normalized.has_prefix("sha256:")) {
                normalized = normalized.substring(7).strip();
            }
            return normalized;
        }

        private static bool is_valid_sha256(string value) {
            if (value.length != 64) {
                return false;
            }
            for (int i = 0; i < value.length; i++) {
                unichar c = value[i];
                if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
                    continue;
                }
                return false;
            }
            return true;
        }
    }
}
