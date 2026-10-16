namespace ApkManager.Core {
    public class FileManagerIcons : Object {
        private const string MIME_TYPE = "application/vnd.android.package-archive";
        private const string MIME_ICON_NAME = "application-vnd.android.package-archive";
        private const string THUMBNAILER_BASENAME = "com.github.ApkManager.thumbnailer";

        public static int? handle_thumbnail_cli(string[] args) {
            for (int i = 1; i < args.length; i++) {
                if (args[i] != "--generate-thumbnail") {
                    continue;
                }
                if (i + 3 >= args.length) {
                    warning("Thumbnailer usage: --generate-thumbnail INPUT OUTPUT SIZE");
                    return 1;
                }

                var input = args[i + 1];
                var output = args[i + 2];
                int size = 128;
                if (!int.try_parse(args[i + 3], out size) || size <= 0) {
                    warning("Invalid thumbnail size: %s", args[i + 3]);
                    return 1;
                }

                var path = path_from_thumbnail_arg(input);
                if (path == null) {
                    return 1;
                }

                return generate_thumbnail(path, output, size) ? 0 : 1;
            }
            return null;
        }

        public static void sync_from_settings() {
            ensure_user_mime_registration();
            install_user_mime_icon();
            install_user_thumbnailer();
            run_update_mime_database();
        }

        public static void notify_apk_changed(string apk_path) {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                return;
            }
            // Touch mtime so file managers regenerate cached thumbnails.
            try {
                var file = File.new_for_path(apk_path);
                var now = new DateTime.now_utc();
                file.set_attribute_uint64(
                    FileAttribute.TIME_MODIFIED,
                    now.to_unix(),
                    FileQueryInfoFlags.NONE,
                    null
                );
            } catch (Error e) {
                warning("Could not refresh APK thumbnail cache hint for %s: %s", apk_path, e.message);
            }
        }

        public static bool generate_thumbnail(string apk_path, string output_path, int size) {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                warning("Thumbnail input missing: %s", apk_path);
                return false;
            }

            try {
                DirUtils.create_with_parents(Path.get_dirname(output_path), 0755);
            } catch (FileError e) {
                warning("Could not create thumbnail output directory: %s", e.message);
                return false;
            }

            if (AppSettings.get_default().get_file_manager_icon_mode() == FileManagerIconMode.EXTRACT_APK) {
                var icon_ref = ApkDisplayName.application_icon_ref(apk_path);
                if (icon_ref != null) {
                    var icon_bytes = ApkIcon.load(apk_path, icon_ref);
                    if (icon_bytes != null && write_scaled_png(icon_bytes, output_path, size)) {
                        return true;
                    }
                }
            }

            return write_android_logo_png(output_path, size);
        }

        private static string? path_from_thumbnail_arg(string arg) {
            if (arg.has_prefix("file://")) {
                try {
                    return File.new_for_uri(arg).get_path();
                } catch (Error e) {
                    warning("Invalid thumbnail URI %s: %s", arg, e.message);
                    return null;
                }
            }
            return arg;
        }

        private static bool write_scaled_png(Bytes png_bytes, string output_path, int size) {
            try {
                var pixbuf = new Gdk.Pixbuf.from_bytes(
                    png_bytes,
                    Gdk.Colorspace.RGB,
                    true,
                    8,
                    0,
                    0,
                    0
                );
                var scaled = pixbuf.scale_simple(size, size, Gdk.InterpType.BILINEAR);
                scaled.save(output_path, "png");
                return true;
            } catch (Error e) {
                warning("Failed to write APK thumbnail %s: %s", output_path, e.message);
                return false;
            }
        }

        private static bool write_android_logo_png(string output_path, int size) {
            var logo_path = AppPaths.android_logo_svg();
            if (!FileUtils.test(logo_path, FileTest.IS_REGULAR)) {
                warning("Android logo SVG missing: %s", logo_path);
                return false;
            }

            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale(logo_path, size, size, true);
                pixbuf.save(output_path, "png");
                return true;
            } catch (Error e) {
                warning("Failed to write Android logo thumbnail %s: %s", output_path, e.message);
                return false;
            }
        }

        private static void ensure_user_mime_registration() {
            var mime_dir = Path.build_filename(user_data_share_dir(), "mime", "packages");
            DirUtils.create_with_parents(mime_dir, 0755);
            var dest = Path.build_filename(mime_dir, "%s.xml".printf(MIME_ICON_NAME));
            if (FileUtils.test(dest, FileTest.IS_REGULAR)) {
                return;
            }

            var xml = """<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="%s">
    <comment>Android application package</comment>
    <glob pattern="*.apk"/>
    <sub-class-of type="application/zip"/>
  </mime-type>
</mime-info>
""".printf(MIME_TYPE);

            try {
                FileUtils.set_contents(dest, xml);
            } catch (FileError e) {
                warning("Could not write MIME package %s: %s", dest, e.message);
            }
        }

        private static void install_user_mime_icon() {
            var logo_path = AppPaths.android_logo_svg();
            if (!FileUtils.test(logo_path, FileTest.IS_REGULAR)) {
                warning("Cannot install MIME icon; missing %s", logo_path);
                return;
            }

            var dest_dir = Path.build_filename(
                user_data_share_dir(),
                "icons",
                "hicolor",
                "scalable",
                "mimetypes"
            );
            DirUtils.create_with_parents(dest_dir, 0755);
            var dest = Path.build_filename(dest_dir, "%s.svg".printf(MIME_ICON_NAME));
            copy_if_changed(logo_path, dest);
        }

        private static void install_user_thumbnailer() {
            var bindir = AppPaths.apk_manager_executable();
            if (bindir == "") {
                warning("Cannot install thumbnailer; apk-manager executable not found");
                return;
            }

            var dest_dir = Path.build_filename(user_data_share_dir(), "thumbnailers");
            DirUtils.create_with_parents(dest_dir, 0755);
            var dest = Path.build_filename(dest_dir, THUMBNAILER_BASENAME);
            var contents = """[Thumbnailer Entry]
TryExec=%s
Exec=%s --generate-thumbnail %%i %%o %%s
MimeType=%s;

""".printf(bindir, bindir, MIME_TYPE);

            try {
                FileUtils.set_contents(dest, contents);
            } catch (FileError e) {
                warning("Could not write thumbnailer entry %s: %s", dest, e.message);
            }
        }

        private static void run_update_mime_database() {
            var mime_dir = Path.build_filename(user_data_share_dir(), "mime");
            if (!FileUtils.test(mime_dir, FileTest.IS_DIR)) {
                return;
            }

            try {
                var spawn = new Subprocess.newv(
                    { "update-mime-database", mime_dir },
                    SubprocessFlags.STDERR_SILENCE
                );
                spawn.wait_check(null);
            } catch (Error e) {
                warning(
                    "Could not run update-mime-database on %s: %s",
                    mime_dir,
                    e.message
                );
            }
        }

        private static void copy_if_changed(string source, string dest) {
            try {
                var src = File.new_for_path(source);
                var dst = File.new_for_path(dest);
                if (dst.query_exists()) {
                    var src_info = src.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                    var dst_info = dst.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                    if (src_info.get_size() == dst_info.get_size()) {
                        return;
                    }
                }
                src.copy(dst, FileCopyFlags.OVERWRITE, null, null);
            } catch (Error e) {
                warning("Could not copy %s to %s: %s", source, dest, e.message);
            }
        }

        private static string user_data_share_dir() {
            return Path.build_filename(Environment.get_user_data_dir(), DATA_DIRNAME);
        }
    }
}
