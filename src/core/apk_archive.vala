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
                if (size <= 0 || size > 8 * 1024 * 1024) {
                    reader.close();
                    return null;
                }
                var bytes = new ByteArray.sized((uint) size);
                uint8[] chunk = new uint8[8192];
                while (true) {
                    ssize_t n = reader.read_data(chunk);
                    if (n <= 0) {
                        break;
                    }
                    uint8[] piece = new uint8[n];
                    for (int i = 0; i < n; i++) {
                        piece[i] = chunk[i];
                    }
                    bytes.append(piece);
                }
                reader.close();
                return ByteArray.free_to_bytes((owned) bytes);
            }

            reader.close();
            return null;
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
