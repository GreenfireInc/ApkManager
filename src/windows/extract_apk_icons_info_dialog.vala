namespace ApkManager.Windows {
    public class ExtractApkIconsInfoDialog : Adw.Dialog {
        public signal void confirmed();
        public signal void cancelled();

        public ExtractApkIconsInfoDialog() {
            title = "Enable APK icon extraction?";
            content_width = 400;
            content_height = -1;
            follows_content_size = true;
            presentation_mode = Adw.DialogPresentationMode.FLOATING;
            build_ui();
        }

        private void build_ui() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 20;
            box.margin_bottom = 20;
            box.margin_start = 18;
            box.margin_end = 18;

            var heading = new Gtk.Label("Set up file manager APK icons");
            heading.add_css_class("title-2");
            heading.wrap = true;
            heading.justify = Gtk.Justification.CENTER;
            heading.halign = Gtk.Align.CENTER;
            box.append(heading);

            var icon = new Gtk.Image.from_icon_name("application-x-android-package");
            icon.pixel_size = 72;
            icon.halign = Gtk.Align.CENTER;
            icon.margin_top = 4;
            icon.margin_bottom = 4;
            box.append(icon);

            var intro = new Gtk.Label(
                "ApkManager is about to configure your file manager so each .apk file can show its own app icon instead of a generic Android logo."
            );
            intro.wrap = true;
            intro.max_width_chars = 42;
            intro.width_request = 360;
            intro.justify = Gtk.Justification.CENTER;
            intro.halign = Gtk.Align.CENTER;
            intro.add_css_class("heading");
            box.append(intro);

            var thumbnailer = new Gtk.Label(
                "A small thumbnailer entry is installed under ~/.local/share/thumbnailers/. When you browse APK files, your file manager (such as Nemo on Cinnamon) calls ApkManager to extract the icon from each package on the fly and render it in icon view."
            );
            thumbnailer.wrap = true;
            thumbnailer.max_width_chars = 42;
            thumbnailer.width_request = 360;
            thumbnailer.justify = Gtk.Justification.CENTER;
            thumbnailer.halign = Gtk.Align.CENTER;
            thumbnailer.add_css_class("dim-label");
            box.append(thumbnailer);

            var comparison = new Gtk.Label(
                "This works like icoextract, which pulls icons out of Windows .exe files so Linux file managers can display them. ApkManager does the same job for Android APK archives."
            );
            comparison.wrap = true;
            comparison.max_width_chars = 42;
            comparison.width_request = 360;
            comparison.justify = Gtk.Justification.CENTER;
            comparison.halign = Gtk.Align.CENTER;
            comparison.add_css_class("dim-label");
            box.append(comparison);

            var link = new Gtk.LinkButton.with_label(
                "https://github.com/jlu5/icoextract",
                "icoextract — Windows .exe icon thumbnailer"
            );
            link.halign = Gtk.Align.CENTER;
            link.margin_top = 4;
            box.append(link);

            var fallback = new Gtk.Label(
                "If an APK has no usable icon, the Android logo from ApkManager is used as a fallback. You may need to clear ~/.cache/thumbnails/ and reopen your file manager to refresh existing APK icons."
            );
            fallback.wrap = true;
            fallback.max_width_chars = 42;
            fallback.width_request = 360;
            fallback.justify = Gtk.Justification.CENTER;
            fallback.halign = Gtk.Align.CENTER;
            fallback.add_css_class("caption");
            box.append(fallback);

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            actions.margin_top = 8;

            var enable_button = new Gtk.Button.with_label("Enable extraction");
            enable_button.hexpand = true;
            enable_button.add_css_class("suggested-action");
            enable_button.clicked.connect(() => {
                confirmed();
                close();
            });
            actions.append(enable_button);

            var cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.hexpand = true;
            cancel_button.clicked.connect(() => {
                cancelled();
                close();
            });
            actions.append(cancel_button);
            box.append(actions);

            child = box;
            default_widget = enable_button;
        }
    }
}
