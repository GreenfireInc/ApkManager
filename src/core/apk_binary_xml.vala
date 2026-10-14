namespace ApkManager.Core {
    public class ApkBinaryXml : Object {
        private const uint16 RES_XML_TYPE = 0x0003;
        private const uint16 RES_STRING_POOL_TYPE = 0x0001;
        private const uint16 RES_XML_RESOURCE_MAP_TYPE = 0x0180;
        private const uint16 RES_XML_START_ELEMENT_TYPE = 0x0102;
        private const uint16 RES_XML_END_ELEMENT_TYPE = 0x0103;

        private const int TYPE_REFERENCE = 0x01;
        private const int TYPE_STRING = 0x03;
        private const int TYPE_FLOAT = 0x04;
        private const int TYPE_DIMENSION = 0x05;
        private const int TYPE_INT_COLOR = 0x1c;

        public class Attribute {
            public string name;
            public uint8 value_type;
            public uint32 value_raw;
            public string? value_string;
            public uint32? reference_id;
            public double? float_value;
            public uint32? color_value;
        }

        public class Element {
            public string name;
            public Gee.ArrayList<Attribute> attributes = new Gee.ArrayList<Attribute>();
            public Gee.ArrayList<Element> children = new Gee.ArrayList<Element>();
        }

        public static Element? parse(uint8[] data) {
            if (data.length < 8 || read_u16(data, 0) != RES_XML_TYPE) {
                return null;
            }
            var doc = new ApkBinaryXml(data);
            return doc.parse_document();
        }

        private uint8[] data;
        private string[] pool = new string[0];
        private uint32[] attr_ids = new uint32[0];

        private ApkBinaryXml(uint8[] data) {
            this.data = data;
        }

        private Element? parse_document() {
            int off = 8;
            if (off + 8 > data.length || read_u16(data, off) != RES_STRING_POOL_TYPE) {
                return null;
            }
            read_string_pool(off);
            off += (int) read_u32(data, off + 4);

            if (off + 8 <= data.length && read_u16(data, off) == RES_XML_RESOURCE_MAP_TYPE) {
                read_resource_map(off);
                off += (int) read_u32(data, off + 4);
            }

            Element? root = null;
            var stack = new Gee.ArrayList<Element>();
            while (off + 8 <= data.length) {
                uint16 typ = read_u16(data, off);
                int size = (int) read_u32(data, off + 4);
                if (size < 8 || off + size > data.length) {
                    break;
                }
                if (typ == RES_XML_START_ELEMENT_TYPE) {
                    var element = read_element(off);
                    if (element == null) {
                        return null;
                    }
                    if (stack.size > 0) {
                        stack[stack.size - 1].children.add(element);
                    } else {
                        root = element;
                    }
                    stack.add(element);
                } else if (typ == RES_XML_END_ELEMENT_TYPE) {
                    if (stack.size > 0) {
                        stack.remove_at(stack.size - 1);
                    }
                }
                off += size;
            }
            return root;
        }

        private void read_string_pool(int off) {
            if (off + 28 > data.length) {
                return;
            }
            int header = read_u16(data, off + 2);
            uint32 count = read_u32(data, off + 8);
            uint32 flags = read_u32(data, off + 16);
            uint32 strings_start = read_u32(data, off + 20);
            bool utf8 = (flags & 0x100) != 0;
            pool = new string[count];
            int strings_at = off + (int) strings_start;
            for (uint i = 0; i < count; i++) {
                int rel_at = off + header + (int) i * 4;
                if (rel_at + 4 > data.length) {
                    pool[i] = "";
                    continue;
                }
                int pos = strings_at + (int) read_u32(data, rel_at);
                pool[i] = utf8 ? read_utf8(pos) : read_utf16(pos);
            }
        }

        private void read_resource_map(int off) {
            int header = read_u16(data, off + 2);
            int chunk_size = (int) read_u32(data, off + 4);
            int count = (chunk_size - header) / 4;
            if (count <= 0) {
                return;
            }
            attr_ids = new uint32[count];
            for (int i = 0; i < count; i++) {
                attr_ids[i] = read_u32(data, off + header + i * 4);
            }
        }

        private Element? read_element(int off) {
            if (off + 36 > data.length) {
                return null;
            }
            uint32 name_idx = read_u32(data, off + 20);
            if (name_idx >= pool.length) {
                return null;
            }
            var element = new Element();
            element.name = pool[name_idx];

            int header = read_u16(data, off + 2);
            int attr_start = read_u16(data, off + 24);
            int attr_size = read_u16(data, off + 26);
            int attr_count = read_u16(data, off + 28);
            int attrs_off = off + header + attr_start;
            for (int i = 0; i < attr_count; i++) {
                int ao = attrs_off + i * attr_size;
                if (ao + 20 > data.length) {
                    break;
                }
                var attr = new Attribute();
                uint32 name_ref = read_u32(data, ao + 4);
                uint32 raw_string = read_u32(data, ao + 8);
                attr.value_type = data[ao + 15];
                attr.value_raw = read_u32(data, ao + 16);
                attr.name = resolve_attr_name(name_ref);
                decode_attribute_value(attr, raw_string);
                element.attributes.add(attr);
            }
            return element;
        }

        private string resolve_attr_name(uint32 name_ref) {
            if (name_ref >= 0x01010000) {
                var mapped = android_attr_name(name_ref);
                if (mapped != null) {
                    return mapped;
                }
            }
            if (name_ref < attr_ids.length) {
                var mapped = android_attr_name(attr_ids[name_ref]);
                if (mapped != null) {
                    return mapped;
                }
            }
            if (name_ref < pool.length) {
                return pool[name_ref];
            }
            return "0x%08x".printf(name_ref);
        }

        private void decode_attribute_value(Attribute attr, uint32 raw_string) {
            if (attr.value_type == TYPE_STRING && attr.value_raw < pool.length) {
                attr.value_string = pool[attr.value_raw];
            } else if (attr.value_type == TYPE_STRING && raw_string < pool.length) {
                attr.value_string = pool[raw_string];
            } else if (attr.value_type == TYPE_REFERENCE) {
                attr.reference_id = attr.value_raw;
            } else if (attr.value_type == TYPE_FLOAT) {
                attr.float_value = uint32_to_float(attr.value_raw);
            } else if (attr.value_type == TYPE_DIMENSION) {
                attr.float_value = (double) (attr.value_raw >> 8);
            } else if (attr.value_type == TYPE_INT_COLOR) {
                attr.color_value = attr.value_raw;
            }
        }

        private static string? android_attr_name(uint32 id) {
            switch (id) {
            case 0x01010005: return "height";
            case 0x01010009: return "width";
            case 0x010100d4: return "background";
            case 0x01010199: return "drawable";
            case 0x010101a5: return "pathData";
            case 0x010101ed: return "fillColor";
            case 0x0101052c: return "foreground";
            case 0x0101057c: return "viewportWidth";
            case 0x0101057d: return "viewportHeight";
            default: return null;
            }
        }

        private static double uint32_to_float(uint32 value) {
            float result = 0;
            uint32* ptr = (uint32*) &result;
            *ptr = value;
            return (double) result;
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
            int n = (int) read_u16(data, pos);
            int p = pos + 2;
            if ((n & 0x8000) != 0) {
                if (p + 2 > data.length) {
                    return "";
                }
                n = ((n & 0x7fff) << 16) | (int) read_u16(data, p);
                p += 2;
            }
            int bytes = n * 2;
            if (n < 0 || p + bytes > data.length) {
                return "";
            }
            var chars = new uint16[n];
            for (int i = 0; i < n; i++) {
                chars[i] = read_u16(data, p + i * 2);
            }
            return utf16_to_utf8(chars);
        }

        private static string utf16_to_utf8(uint16[] chars) {
            var builder = new StringBuilder();
            for (int i = 0; i < chars.length; i++) {
                unichar c = chars[i];
                if (c >= 0xD800 && c <= 0xDBFF && i + 1 < chars.length) {
                    unichar low = chars[i + 1];
                    if (low >= 0xDC00 && low <= 0xDFFF) {
                        c = (unichar) (0x10000 + ((c - 0xD800) << 10) + (low - 0xDC00));
                        i++;
                    }
                }
                builder.append_unichar(c);
            }
            return builder.str;
        }

        private static uint16 read_u16(uint8[] buf, int off) {
            return (uint16) (buf[off] | (buf[off + 1] << 8));
        }

        private static uint32 read_u32(uint8[] buf, int off) {
            return (uint32) buf[off]
                | ((uint32) buf[off + 1] << 8)
                | ((uint32) buf[off + 2] << 16)
                | ((uint32) buf[off + 3] << 24);
        }

        public static uint32? reference_attribute(ApkBinaryXml.Element element, string name) {
            foreach (var attr in element.attributes) {
                if (attr.name == name && attr.reference_id != null) {
                    return attr.reference_id;
                }
            }
            return null;
        }

        public static string? string_attribute(ApkBinaryXml.Element element, string name) {
            foreach (var attr in element.attributes) {
                if (attr.name == name && attr.value_string != null) {
                    return attr.value_string;
                }
            }
            return null;
        }

        public static double float_attribute(ApkBinaryXml.Element element, string name, double fallback) {
            foreach (var attr in element.attributes) {
                if (attr.name == name && attr.float_value != null) {
                    return attr.float_value;
                }
            }
            return fallback;
        }

        public static uint32? color_attribute(ApkBinaryXml.Element element, string name) {
            foreach (var attr in element.attributes) {
                if (attr.name == name && attr.color_value != null) {
                    return attr.color_value;
                }
            }
            return null;
        }
    }
}
