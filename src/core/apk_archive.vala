using Archive;

namespace ApkManager.Core {
    public class ArchiveEntryInfo : Object {
        public string path { get; construct; }
        public int64 compressed_size { get; construct; }
        public int64 uncompressed_size { get; construct; }
        public bool is_directory { get; construct; }

        public ArchiveEntryInfo(string path, int64 compressed_size, int64 uncompressed_size, bool is_directory) {
            Object(
                path: path,
                compressed_size: compressed_size,
                uncompressed_size: uncompressed_size,
                is_directory: is_directory
            );
        }
    }

    public class ApkArchive : Object {
        public static bool is_apk_path(string path) {
            return path.has_suffix(".apk") || path.has_suffix(".APK");
        }

        public static Gee.ArrayList<ArchiveEntryInfo> list_entries(string apk_path) throws Error {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                throw new IOError.FAILED("APK file not found: %s".printf(apk_path));
            }

            var entries = new Gee.ArrayList<ArchiveEntryInfo>();
            Archive.Read reader = new Archive.Read();
            reader.support_filter_all();
            reader.support_format_all();

            if (reader.open_filename(apk_path, 10240) != Archive.Result.OK) {
                throw new IOError.FAILED("Failed to open APK archive: %s".printf(apk_path));
            }

            unowned Archive.Entry entry;
            while (reader.next_header(out entry) == Archive.Result.OK) {
                var name = entry.pathname();
                if (name == "" || !is_safe_archive_path(name)) {
                    continue;
                }

                var size = entry.size();
                entries.add(new ArchiveEntryInfo(
                    name,
                    size,
                    size,
                    entry.filetype() == Archive.FileType.IFDIR
                ));
            }

            reader.close();
            return entries;
        }

        public static Bytes? read_entry(string apk_path, string entry_name) throws Error {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR) || !is_safe_archive_path(entry_name)) {
                return null;
            }

            Archive.Read reader = new Archive.Read();
            reader.support_filter_all();
            reader.support_format_all();
            if (reader.open_filename(apk_path, 10240) != Archive.Result.OK) {
                return null;
            }

            unowned Archive.Entry entry;
            while (reader.next_header(out entry) == Archive.Result.OK) {
                if (entry.pathname() != entry_name) {
                    reader.read_data_skip();
                    continue;
                }
                var size = entry.size();
                // Large apps (Netflix, TikTok) ship resources.arsc well past 8 MiB.
                // The icon id cannot be resolved without that table.
                if (size <= 0 || size > 64 * 1024 * 1024) {
                    reader.close();
                    return null;
                }
                var bytes = new ByteArray.sized((uint) size);
                uint8[] chunk = new uint8[65536];
                while (true) {
                    ssize_t n = reader.read_data(chunk);
                    if (n <= 0) {
                        break;
                    }
                    bytes.append(chunk[0:n]);
                }
                reader.close();
                return ByteArray.free_to_bytes((owned) bytes);
            }

            reader.close();
            return null;
        }

        public static string entry_type_label(string path, bool is_directory) {
            if (is_directory) {
                return "directory";
            }

            var lower_path = path.casefold();
            var file_name = Path.get_basename(lower_path);

            if (file_name.has_suffix(".dex")) {
                return "dex";
            }
            if (file_name == "resources.arsc") {
                return "resource";
            }
            if (file_name.has_suffix(".so")) {
                return "native";
            }
            if (path_has_image_extension(file_name)) {
                return "image";
            }
            if (path_has_text_extension(file_name)) {
                return "text";
            }
            if (path_has_font_extension(file_name)) {
                return "font";
            }
            if (path_has_audio_extension(file_name)) {
                return "audio";
            }
            if (path_has_video_extension(file_name)) {
                return "video";
            }
            if (path_has_archive_extension(file_name)) {
                return "archive";
            }
            if (path_has_signature_extension(file_name, lower_path)) {
                return "signature";
            }
            if (lower_path.has_prefix("res/")) {
                return "resource";
            }
            if (lower_path.has_prefix("assets/")) {
                return "asset";
            }
            return "binary";
        }

        private static bool path_has_image_extension(string file_name) {
            return file_name.has_suffix(".png")
                || file_name.has_suffix(".9.png")
                || file_name.has_suffix(".jpg")
                || file_name.has_suffix(".jpeg")
                || file_name.has_suffix(".webp")
                || file_name.has_suffix(".gif")
                || file_name.has_suffix(".bmp")
                || file_name.has_suffix(".svg");
        }

        private static bool path_has_text_extension(string file_name) {
            return file_name.has_suffix(".xml")
                || file_name.has_suffix(".txt")
                || file_name.has_suffix(".json")
                || file_name.has_suffix(".html")
                || file_name.has_suffix(".htm")
                || file_name.has_suffix(".css")
                || file_name.has_suffix(".js")
                || file_name.has_suffix(".yaml")
                || file_name.has_suffix(".yml")
                || file_name.has_suffix(".properties")
                || file_name.has_suffix(".csv")
                || file_name.has_suffix(".md")
                || file_name.has_suffix(".kotlin_module")
                || file_name.has_suffix(".proto")
                || file_name.has_suffix(".conf")
                || file_name.has_suffix(".cfg")
                || file_name.has_suffix(".ini");
        }

        private static bool path_has_font_extension(string file_name) {
            return file_name.has_suffix(".ttf")
                || file_name.has_suffix(".otf")
                || file_name.has_suffix(".ttc");
        }

        private static bool path_has_audio_extension(string file_name) {
            return file_name.has_suffix(".ogg")
                || file_name.has_suffix(".mp3")
                || file_name.has_suffix(".wav")
                || file_name.has_suffix(".m4a");
        }

        private static bool path_has_video_extension(string file_name) {
            return file_name.has_suffix(".mp4")
                || file_name.has_suffix(".webm")
                || file_name.has_suffix(".mkv");
        }

        private static bool path_has_archive_extension(string file_name) {
            return file_name.has_suffix(".zip")
                || file_name.has_suffix(".jar")
                || file_name.has_suffix(".gz")
                || file_name.has_suffix(".bz2")
                || file_name.has_suffix(".xz")
                || file_name.has_suffix(".tar");
        }

        private static bool path_has_signature_extension(string file_name, string lower_path) {
            if (!lower_path.has_prefix("meta-inf/")) {
                return false;
            }
            return file_name.has_suffix(".rsa")
                || file_name.has_suffix(".dsa")
                || file_name.has_suffix(".ec")
                || file_name.has_suffix(".sf")
                || file_name.has_suffix(".mf");
        }

        public static bool is_safe_archive_path(string name) {
            if (name.has_prefix("/") || name.has_prefix("\\")) {
                return false;
            }
            // Reject ".." as its own path segment. A substring search for ".."
            // also matches unrelated names, and a search for "\0" matches every
            // Vala string because the needle is empty.
            if (name == ".." || name.has_prefix("../") || name.has_suffix("/..") || name.contains("/../")) {
                return false;
            }
            return true;
        }

        public static string? compute_sha256(string file_path) {
            try {
                var file = File.new_for_path(file_path);
                var stream = file.read(null);
                var checksum = new GLib.Checksum(GLib.ChecksumType.SHA256);

                uint8[] buffer = new uint8[8192];
                while (true) {
                    size_t bytes_read;
                    stream.read_all(buffer, out bytes_read, null);
                    if (bytes_read == 0) {
                        break;
                    }
                    checksum.update(buffer, bytes_read);
                }

                return checksum.get_string();
            } catch (Error e) {
                warning("Failed to hash %s: %s", file_path, e.message);
                return null;
            }
        }
    }
}
