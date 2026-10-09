using ApkManager.Core;

namespace ApkManager.Utils {
    public class UiUtils : Object {
        public const int SESSION_LIST_ICON_PX = 32;
        public const int SESSION_GRID_ICON_PX = 64;

        private static Gee.HashMap<string, Gdk.Paintable>? session_icon_cache = null;

        private static Gee.HashMap<string, Gdk.Paintable> get_session_icon_cache() {
            if (session_icon_cache == null) {
                session_icon_cache = new Gee.HashMap<string, Gdk.Paintable>();
            }
            return session_icon_cache;
        }

        public static void clear_session_icon_cache() {
            if (session_icon_cache != null) {
                session_icon_cache.clear();
            }
        }

        public static Gdk.Paintable? load_session_icon_paintable(string apk_path) {
            var cache = get_session_icon_cache();
            if (cache.has_key(apk_path)) {
                return cache[apk_path];
            }

            var icon_ref = ApkDisplayName.application_icon_ref(apk_path);
            if (icon_ref == null) {
                return null;
            }

            Bytes? icon = ApkIcon.load(apk_path, icon_ref);
            if (icon == null) {
                return null;
            }

            try {
                var texture = Gdk.Texture.from_bytes(icon);
                cache[apk_path] = texture;
                return texture;
            } catch (Error e) {
                warning("Failed to decode session icon for %s: %s", apk_path, e.message);
                return null;
            }
        }

        public static Gtk.Image load_session_apk_icon(string apk_path, int pixel_size) {
            var image = new Gtk.Image();
            image.pixel_size = pixel_size;
            image.halign = Gtk.Align.CENTER;
            image.valign = Gtk.Align.CENTER;

            var paintable = load_session_icon_paintable(apk_path);
            if (paintable != null) {
                image.set_from_paintable(paintable);
            } else {
                image.icon_name = "application-x-android-package";
            }
            return image;
        }
    }
}
