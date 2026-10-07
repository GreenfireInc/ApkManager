namespace ApkManager.Core {
    public class ApkIcon : Object {
        private const uint32 NO_ENTRY = 0xffffffffu;
        private const int TYPE_REFERENCE = 0x01;
        private const int TYPE_STRING = 0x03;

        public static Bytes? load(string apk_path, string icon_ref) {
            uint32 id;
            if (!parse_resource_id(icon_ref, out id)) {
                return null;
            }
            try {
                Bytes? table = ApkArchive.read_entry(apk_path, "resources.arsc");
                if (table == null) {
                    return null;
                }
                var path = new ResourceTable(table.get_data()).best_image_path(id);
                if (path == null) {
                    return null;
                }
                return ApkArchive.read_entry(apk_path, path);
            } catch (Error e) {
                warning("Failed to load APK icon: %s", e.message);
                return null;
            }
        }

        private static bool parse_resource_id(string icon_ref, out uint32 id) {
            id = 0;
            var text = icon_ref.strip();
            if (text.has_prefix("@")) {
                text = text.substring(1);
            }
            if (text == "") {
                return false;
            }
            int radix = 10;
            if (text.has_prefix("0x") || text.has_prefix("0X")) {
                radix = 16;
                text = text.substring(2);
            }
            uint32 value = 0;
            bool any = false;
            foreach (uint8 ch in text.data) {
                if (ch == 0) {
                    break;
                }
                int digit;
                if (ch >= '0' && ch <= '9') {
                    digit = ch - '0';
                } else if (ch >= 'a' && ch <= 'f') {
                    digit = ch - 'a' + 10;
                } else if (ch >= 'A' && ch <= 'F') {
                    digit = ch - 'A' + 10;
                } else {
                    return false;
                }
                if (digit >= radix) {
                    return false;
                }
                any = true;
                value = value * radix + digit;
            }
            id = value;
            return any;
        }

        private class ResourceTable {
            private uint8[] data;
            private string[] pool;

            public ResourceTable(uint8[] data) {
                this.data = data;
                this.pool = new string[0];
                if (data.length >= 12 && u16(0) == 0x0002) {
                    int pool_off = u16(2);
                    this.pool = read_pool(pool_off);
                }
            }

            public string? best_image_path(uint32 resource_id) {
                var seen = new Gee.HashSet<uint32>();
                return resolve(resource_id, seen);
            }

            private string? resolve(uint32 resource_id, Gee.HashSet<uint32> seen) {
                if (resource_id == 0 || seen.contains(resource_id)) {
                    return null;
                }
                seen.add(resource_id);
                uint8 type_id = (uint8) ((resource_id >> 16) & 0xff);
                uint16 entry_index = (uint16) (resource_id & 0xffff);
                if (data.length < 12) {
                    return null;
                }

                string? best_path = null;
                int best_score = -1;
                int pool_off = u16(2);
                int pool_size = (int) u32(pool_off + 4);
                consider_chunk(pool_off + pool_size, data.length, type_id, entry_index, seen, ref best_path, ref best_score);
                return best_path;
            }

            private void consider_chunk(int start, int end, uint8 type_id, uint16 entry_index, Gee.HashSet<uint32> seen, ref string? best_path, ref int best_score) {
                int off = start;
                while (off + 8 <= end && off + 8 <= data.length) {
                    uint16 typ = u16(off);
                    int header = u16(off + 2);
                    int size = (int) u32(off + 4);
                    if (header < 8 || size < header || off + size > data.length) {
                        return;
                    }
                    if (typ == 0x0200) {
                        consider_chunk(off + header, off + size, type_id, entry_index, seen, ref best_path, ref best_score);
                    } else if (typ == 0x0201 && data[off + 8] == type_id) {
                        note_type(off, header, entry_index, seen, ref best_path, ref best_score);
                    }
                    off += size;
                }
            }

            private void note_type(int off, int header, uint16 entry_index, Gee.HashSet<uint32> seen, ref string? best_path, ref int best_score) {
                uint8 flags = data[off + 9];
                uint32 entry_count = u32(off + 12);
                uint32 entries_start = u32(off + 16);
                uint32 config_size = u32(off + 20);
                int density = 0;
                if (config_size >= 16 && off + 36 <= data.length) {
                    density = u16(off + 34);
                }

                uint32 entry_offset = NO_ENTRY;
                if ((flags & 0x01) != 0) {
                    for (uint i = 0; i < entry_count; i++) {
                        int pos = off + header + (int) i * 4;
                        if (pos + 4 > data.length) {
                            return;
                        }
                        if (u16(pos) == entry_index) {
                            entry_offset = (uint32) u16(pos + 2) * 4;
                            break;
                        }
                    }
                } else if (entry_index < entry_count) {
                    int pos = off + header + entry_index * 4;
                    if (pos + 4 > data.length) {
                        return;
                    }
                    entry_offset = u32(pos);
                }
                if (entry_offset == NO_ENTRY) {
                    return;
                }

                int ent = off + (int) entries_start + (int) entry_offset;
                if (ent + 8 > data.length) {
                    return;
                }
                int entry_size = u16(ent);
                uint16 entry_flags = u16(ent + 2);
                if ((entry_flags & 0x0001) != 0 || entry_size < 8) {
                    return;
                }
                int value = ent + entry_size;
                if (value + 8 > data.length) {
                    return;
                }
                uint8 data_type = data[value + 3];
                uint32 data_value = u32(value + 4);
                if (data_type == TYPE_REFERENCE) {
                    var nested = resolve(data_value, seen);
                    int score = score_path(nested, density);
                    if (nested != null && score > best_score) {
                        best_score = score;
                        best_path = nested;
                    }
                    return;
                }
                if (data_type != TYPE_STRING || data_value >= pool.length) {
                    return;
                }
                var path = pool[data_value];
                int score = score_path(path, density);
                if (score > best_score) {
                    best_score = score;
                    best_path = path;
                }
            }

            private static int score_path(string? path, int density) {
                if (path == null) {
                    return -1;
                }
                var lower = path.down();
                if (!(lower.has_suffix(".png") || lower.has_suffix(".webp") || lower.has_suffix(".jpg") || lower.has_suffix(".jpeg"))) {
                    return -1;
                }
                if (density >= 65534) {
                    return 1;
                }
                if (density <= 0) {
                    return 2;
                }
                return density;
            }

            private string[] read_pool(int off) {
                if (off + 28 > data.length || u16(off) != 0x0001) {
                    return new string[0];
                }
                int header = u16(off + 2);
                uint32 count = u32(off + 8);
                uint32 flags = u32(off + 16);
                uint32 strings_start = u32(off + 20);
                bool utf8 = (flags & 0x100) != 0;
                var result = new string[count];
                int strings_at = off + (int) strings_start;
                for (uint i = 0; i < count; i++) {
                    int rel_at = off + header + (int) i * 4;
                    if (rel_at + 4 > data.length) {
                        result[i] = "";
                        continue;
                    }
                    int pos = strings_at + (int) u32(rel_at);
                    result[i] = utf8 ? read_utf8(pos) : read_utf16(pos);
                }
                return result;
            }

            private string read_utf8(int pos) {
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

            private string read_utf16(int pos) {
                if (pos + 2 > data.length) {
                    return "";
                }
                int n = u16(pos);
                int p = pos + 2;
                if ((n & 0x8000) != 0) {
                    if (p + 2 > data.length) {
                        return "";
                    }
                    n = ((n & 0x7fff) << 16) | u16(p);
                    p += 2;
                }
                int bytes = n * 2;
                if (n < 0 || p + bytes > data.length) {
                    return "";
                }
                var chars = new uint16[n];
                for (int i = 0; i < n; i++) {
                    chars[i] = u16(p + i * 2);
                }
                return ((string) chars).dup();
            }

            private uint16 u16(int off) {
                return (uint16) (data[off] | (data[off + 1] << 8));
            }

            private uint32 u32(int off) {
                return (uint32) data[off]
                    | ((uint32) data[off + 1] << 8)
                    | ((uint32) data[off + 2] << 16)
                    | ((uint32) data[off + 3] << 24);
            }
        }
    }
}
