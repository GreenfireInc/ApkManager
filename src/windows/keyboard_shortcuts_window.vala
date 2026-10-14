namespace ApkManager.Windows {
    public class KeyboardShortcutsWindow : Adw.Window {
        public KeyboardShortcutsWindow(Gtk.Window parent) {
            Object(
                transient_for: parent,
                modal: true,
                title: "Keyboard Shortcuts",
                default_width: 520,
                default_height: 520,
                destroy_with_parent: true
            );
            build_ui();
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            content = toolbar;

            var header = new Adw.HeaderBar();
            header.title_widget = new Adw.WindowTitle("Keyboard Shortcuts", "Navigate ApkManager from the keyboard");
            toolbar.add_top_bar(header);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

            var page = new Adw.PreferencesPage();

            var general = new Adw.PreferencesGroup();
            general.title = "General";
            general.description = "Application-wide shortcuts available from the main window.";
            add_shortcut(general, "Get APKs", "Search stores and download packages", "<Primary><Shift>g");
            add_shortcut(general, "Preferences", "Open application settings", "<Primary>comma");
            add_shortcut(general, "Keyboard shortcuts", "Show this help window", "<Primary>question");
            add_shortcut(general, "Quit", "Close ApkManager", "<Primary>q");
            page.add(general);

            var sessions = new Adw.PreferencesGroup();
            sessions.title = "Recent APKs";
            sessions.description = "Sidebar session list and grid.";
            add_shortcut(sessions, "Focus search", "Filter recent APKs by name", "<Primary>f");
            add_shortcut(sessions, "Open APK", "Load the selected session in the main pane", "Return");
            add_shortcut(sessions, "Toggle multi-select", "Add or remove a session from the selection", null, "Ctrl+Click");
            add_shortcut(sessions, "Select a range", "Select every session between two clicks", null, "Shift+Click");
            add_shortcut(sessions, "Context menu", "Remove from recents or delete APK files", "Shift<F10>");
            page.add(sessions);

            var details = new Adw.PreferencesGroup();
            details.title = "APK details";
            details.description = "While inspecting an open package.";
            add_shortcut(details, "Switch detail tab", "Move between Files and Properties", null, "Click tab");
            add_shortcut(details, "Cancel decode", "Stop a running Quick Manifest or Full Decode job", "Escape");
            page.add(details);

            var dialogs = new Adw.PreferencesGroup();
            dialogs.title = "Dialogs";
            dialogs.description = "Install, Get APKs, Verify, and other modal windows.";
            add_shortcut(dialogs, "Close dialog", "Dismiss the front-most modal window", "Escape");
            add_shortcut(dialogs, "Activate default button", "Confirm or run the primary action", "Return");
            page.add(dialogs);

            scrolled.child = page;
            toolbar.content = scrolled;
        }

        private void add_shortcut(
            Adw.PreferencesGroup group,
            string title,
            string subtitle,
            string? accelerator,
            string? manual_label = null
        ) {
            var row = new Adw.ActionRow();
            row.title = title;
            row.subtitle = subtitle;
            if (accelerator != null) {
                var keys = new Gtk.ShortcutLabel(accelerator);
                row.add_suffix(keys);
            } else if (manual_label != null) {
                var keys = new Gtk.Label(manual_label);
                keys.add_css_class("dim-label");
                row.add_suffix(keys);
            }
            group.add(row);
        }
    }
}
