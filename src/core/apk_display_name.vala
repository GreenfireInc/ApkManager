namespace ApkManager.Core {
    public class ApkDisplayName : Object {
        private const uint32 RES_XML_TYPE = 0x00080003;
        private const uint16 CHUNK_STRING_POOL = 0x0001;
        private const uint16 RES_XML_RESOURCE_MAP = 0x0180;
        private const uint16 RES_XML_START_ELEMENT = 0x0102;
        private const uint8 TYPE_REFERENCE = 0x01;
        private const uint8 TYPE_STRING = 0x03;

        public static string for_session(DecodeSession session) {
            var basename = Path.get_basename(session.apk_path);
            if (session.label != null && session.label != "" && session.label != basename) {
                return session.label;
            }

            var resolved = resolve(session.apk_path);
            if (resolved != null && resolved != "") {
                session.label = resolved;
                return resolved;
            }
            return basename;
        }

        public static string? resolve(string apk_path) {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                return null;
            }

            var from_cache = try_decoded_manifest_cache(apk_path);
            if (from_cache != null && from_cache != "") {
                return from_cache;
            }

            return read_label_from_manifest_xml(apk_path);
        }

        public static string? application_icon_ref(string apk_path) {
            if (!FileUtils.test(apk_path, FileTest.IS_REGULAR)) {
                return null;
            }

            var hash = ApkArchive.compute_sha256(apk_path);
            if (hash != null) {
                var cache_dir = AppPaths.decoded_dir_for_key("%s-manifest".printf(hash));
                if (FileUtils.test(cache_dir, FileTest.IS_DIR)) {
                    try {
                        var meta = ApkMetadata.from_decode_dir(cache_dir);
                        if (meta.icon_ref != "") {
                            return meta.icon_ref;
                        }
                    } catch (Error e) {
                        // fall through to binary manifest
                    }
                }
            }

            try {
                Bytes? manifest = ApkArchive.read_entry(apk_path, "AndroidManifest.xml");
                if (manifest == null) {
                    return null;
                }
                string? label;
                string? icon_ref;
                parse_application_attrs(apk_path, manifest.get_data(), out label, out icon_ref);
                return icon_ref;
            } catch (Error e) {
                warning("Failed to read manifest for icon: %s", e.message);
                return null;
            }
        }

        private static string? try_decoded_manifest_cache(string apk_path) {
            var hash = ApkArchive.compute_sha256(apk_path);
            if (hash == null) {
                return null;
            }
            var cache_dir = AppPaths.decoded_dir_for_key("%s-manifest".printf(hash));
            if (!FileUtils.test(cache_dir, FileTest.IS_DIR)) {
                return null;
            }
            try {
                var meta = ApkMetadata.from_decode_dir(cache_dir);
                if (meta.app_label != "") {
                    return meta.app_label;
                }
                if (meta.label_ref != "") {
                    return ApkIcon.resolve_label_ref(apk_path, meta.label_ref);
                }
            } catch (Error e) {
                return null;
            }
            return null;
        }

        private static string? read_label_from_manifest_xml(string apk_path) {
            try {
                Bytes? manifest = ApkArchive.read_entry(apk_path, "AndroidManifest.xml");
                if (manifest == null) {
                    return null;
                }
                string? label;
                string? icon_ref;
                parse_application_attrs(apk_path, manifest.get_data(), out label, out icon_ref);
                return label;
            } catch (Error e) {
                warning("Failed to read manifest for display name: %s", e.message);
                return null;
            }
        }

        private static void parse_application_attrs(string apk_path, uint8[] data, out string? label, out string? icon_ref) {
            label = null;
            icon_ref = null;
            if (data.length < 8 || u32(data, 0) != RES_XML_TYPE) {
                return;
            }

            int off = 8;
            if (off + 8 > data.length || u16(data, off) != CHUNK_STRING_POOL) {
                return;
            }

            string[] pool;
            off = read_string_pool(data, off, out pool);
            if (off < 0 || pool.length == 0) {
                return;
            }

            if (off + 8 <= data.length && u16(data, off) == RES_XML_RESOURCE_MAP) {
                off += (int) u32(data, off + 4);
            }

            while (off + 8 <= data.length) {
                uint16 typ = u16(data, off);
                int size = (int) u32(data, off + 4);
                if (size < 8 || off + size > data.length) {
                    break;
                }

                if (typ == RES_XML_START_ELEMENT) {
                    int name_index = (int) u32(data, off + 20);
                    if (name_index >= 0 && name_index < pool.length && pool[name_index] == "application") {
                        uint16 attr_count = u16(data, off + 28);
                        int attr_size = u16(data, off + 26);
                        int attrs_off = off + 36;
                        for (int i = 0; i < attr_count; i++) {
                            int a = attrs_off + i * attr_size;
                            if (a + 20 > data.length) {
                                break;
                            }
                            int name_idx = (int) u32(data, a + 4);
                            if (name_idx < 0 || name_idx >= pool.length) {
                                continue;
                            }
                            var attr_name = pool[name_idx];
                            uint8 value_type = data[a + 15];
                            uint32 value_data = u32(data, a + 16);
                            if (attr_name == "label" && label == null) {
                                if (value_type == TYPE_STRING && value_data < pool.length) {
                                    label = pool[value_data];
                                } else if (value_type == TYPE_REFERENCE) {
                                    label = ApkIcon.resolve_label_id(apk_path, value_data);
                                }
                            } else if (attr_name == "icon" && icon_ref == null && value_type == TYPE_REFERENCE) {
                                icon_ref = "@%u".printf(value_data);
                            }
                        }
                    }
                }
                off += size;
            }
        }

        private static int read_string_pool(uint8[] data, int off, out string[] pool) {
            pool = new string[0];
            if (off + 28 > data.length || u16(data, off) != CHUNK_STRING_POOL) {
                return -1;
            }

            int header = u16(data, off + 2);
            uint32 count = u32(data, off + 8);
            uint32 flags = u32(data, off + 16);
            uint32 strings_start = u32(data, off + 20);
            int chunk_size = (int) u32(data, off + 4);
            bool utf8 = (flags & 0x100) != 0;
            pool = new string[count];
            int strings_at = off + (int) strings_start;

            for (uint i = 0; i < count; i++) {
                int rel_at = off + header + (int) i * 4;
                if (rel_at + 4 > data.length) {
                    pool[i] = "";
                    continue;
                }
                int pos = strings_at + (int) u32(data, rel_at);
                pool[i] = utf8 ? read_utf8(data, pos) : read_utf16(data, pos);
            }
            return off + chunk_size;
        }

        private static string read_utf8(uint8[] data, int pos) {
            if (pos + 2 >= data.length) {
                return "";
            }
            int p = pos;
            if ((data[p] & 0x80) != 0) {
                p += 2;
            } else {
                p += 1;
            }
            if (p >= data.length) {
                return "";
            }
            int len = data[p];
            p += 1;
            if ((len & 0x80) != 0) {
                if (p >= data.length) {
                    return "";
                }
                len = ((len & 0x7f) << 8) | data[p];
                p += 1;
            }
            if (len < 0 || p + len > data.length) {
                return "";
            }
            return ((string) data[p:p + len]).dup();
        }

        private static string read_utf16(uint8[] data, int pos) {
            if (pos + 2 > data.length) {
                return "";
            }
            int n = u16(data, pos);
            int p = pos + 2;
            if ((n & 0x8000) != 0) {
                if (p + 2 > data.length) {
                    return "";
                }
                n = ((n & 0x7fff) << 16) | u16(data, p);
                p += 2;
            }
            int bytes = n * 2;
            if (n < 0 || p + bytes > data.length) {
                return "";
            }
            var chars = new uint16[n];
            for (int i = 0; i < n; i++) {
                chars[i] = u16(data, p + i * 2);
            }
            return ((string) chars).dup();
        }

        private static uint16 u16(uint8[] data, int off) {
            return (uint16) (data[off] | (data[off + 1] << 8));
        }

        private static uint32 u32(uint8[] data, int off) {
            return (uint32) data[off]
                | ((uint32) data[off + 1] << 8)
                | ((uint32) data[off + 2] << 16)
                | ((uint32) data[off + 3] << 24);
        }
    }
}
