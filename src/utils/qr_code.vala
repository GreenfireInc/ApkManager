namespace ApkManager.Utils {
    /**
     * QR Code (Model 2) encoder limited to byte mode, error correction level H,
     * and versions 1–10 (up to 119 bytes). Level H leaves room for a logo drawn
     * over the centre of the symbol. Structure follows Project Nayuki's
     * qrcodegen reference implementation.
     */
    public class QrCode {
        private const int MAX_VERSION = 10;
        private const int[] ECC_CODEWORDS_PER_BLOCK_H = { -1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28 };
        private const int[] NUM_ECC_BLOCKS_H = { -1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8 };
        private const int FORMAT_BITS_H = 2;

        private const int PENALTY_N1 = 3;
        private const int PENALTY_N2 = 3;
        private const int PENALTY_N3 = 40;
        private const int PENALTY_N4 = 10;

        public int version { get; private set; }
        public int size { get; private set; }

        private bool[,] modules;
        private bool[,] is_function;

        public static QrCode? encode_text(string text) {
            unowned uint8[] bytes = text.data;
            for (int ver = 1; ver <= MAX_VERSION; ver++) {
                int used_bits = 4 + char_count_bits(ver) + bytes.length * 8;
                if (used_bits <= num_data_codewords(ver) * 8) {
                    return new QrCode(ver, bytes);
                }
            }
            return null;
        }

        public bool get_module(int x, int y) {
            return x >= 0 && x < size && y >= 0 && y < size && modules[y, x];
        }

        private QrCode(int ver, uint8[] text_bytes) {
            version = ver;
            size = ver * 4 + 17;
            modules = new bool[size, size];
            is_function = new bool[size, size];

            int capacity = num_data_codewords(ver) * 8;
            var data = new uint8[capacity / 8];
            int bit_len = 0;
            append_bits(data, ref bit_len, 4, 4);
            append_bits(data, ref bit_len, text_bytes.length, char_count_bits(ver));
            foreach (var b in text_bytes) {
                append_bits(data, ref bit_len, b, 8);
            }
            bit_len += int.min(4, capacity - bit_len);
            bit_len = (bit_len + 7) / 8 * 8;
            uint8 pad = 0xEC;
            while (bit_len < capacity) {
                append_bits(data, ref bit_len, pad, 8);
                pad = pad == 0xEC ? 0x11 : 0xEC;
            }

            draw_function_patterns();
            draw_codewords(add_ecc_and_interleave(data));

            int best_mask = 0;
            int min_penalty = int.MAX;
            for (int mask = 0; mask < 8; mask++) {
                apply_mask(mask);
                draw_format_bits(mask);
                int penalty = penalty_score();
                if (penalty < min_penalty) {
                    best_mask = mask;
                    min_penalty = penalty;
                }
                apply_mask(mask);
            }
            apply_mask(best_mask);
            draw_format_bits(best_mask);
        }

        private static void append_bits(uint8[] buf, ref int bit_len, uint value, int count) {
            for (int i = count - 1; i >= 0; i--) {
                if (((value >> i) & 1) != 0) {
                    buf[bit_len >> 3] |= (uint8) (0x80 >> (bit_len & 7));
                }
                bit_len++;
            }
        }

        private static int char_count_bits(int ver) {
            return ver <= 9 ? 8 : 16;
        }

        private static int num_raw_data_modules(int ver) {
            int result = (16 * ver + 128) * ver + 64;
            if (ver >= 2) {
                int num_align = ver / 7 + 2;
                result -= (25 * num_align - 10) * num_align - 55;
                if (ver >= 7) {
                    result -= 36;
                }
            }
            return result;
        }

        private static int num_data_codewords(int ver) {
            return num_raw_data_modules(ver) / 8
                - ECC_CODEWORDS_PER_BLOCK_H[ver] * NUM_ECC_BLOCKS_H[ver];
        }

        private void set_function_module(int x, int y, bool dark) {
            modules[y, x] = dark;
            is_function[y, x] = true;
        }

        private void draw_function_patterns() {
            for (int i = 0; i < size; i++) {
                set_function_module(6, i, i % 2 == 0);
                set_function_module(i, 6, i % 2 == 0);
            }

            draw_finder_pattern(3, 3);
            draw_finder_pattern(size - 4, 3);
            draw_finder_pattern(3, size - 4);

            var align = alignment_pattern_positions();
            int num_align = align.length;
            for (int i = 0; i < num_align; i++) {
                for (int j = 0; j < num_align; j++) {
                    bool overlaps_finder = (i == 0 && j == 0)
                        || (i == 0 && j == num_align - 1)
                        || (i == num_align - 1 && j == 0);
                    if (!overlaps_finder) {
                        draw_alignment_pattern(align[i], align[j]);
                    }
                }
            }

            draw_format_bits(0);
            draw_version();
        }

        private int[] alignment_pattern_positions() {
            if (version == 1) {
                return new int[0];
            }
            int num_align = version / 7 + 2;
            int step = (version * 4 + num_align * 2 + 1) / (num_align * 2 - 2) * 2;
            var result = new int[num_align];
            result[0] = 6;
            int pos = size - 7;
            for (int i = num_align - 1; i >= 1; i--) {
                result[i] = pos;
                pos -= step;
            }
            return result;
        }

        private void draw_finder_pattern(int x, int y) {
            for (int dy = -4; dy <= 4; dy++) {
                for (int dx = -4; dx <= 4; dx++) {
                    int dist = int.max(abs_int(dx), abs_int(dy));
                    int xx = x + dx;
                    int yy = y + dy;
                    if (xx >= 0 && xx < size && yy >= 0 && yy < size) {
                        set_function_module(xx, yy, dist != 2 && dist != 4);
                    }
                }
            }
        }

        private void draw_alignment_pattern(int x, int y) {
            for (int dy = -2; dy <= 2; dy++) {
                for (int dx = -2; dx <= 2; dx++) {
                    set_function_module(x + dx, y + dy, int.max(abs_int(dx), abs_int(dy)) != 1);
                }
            }
        }

        private void draw_format_bits(int mask) {
            int data = (FORMAT_BITS_H << 3) | mask;
            int rem = data;
            for (int i = 0; i < 10; i++) {
                rem = (rem << 1) ^ ((rem >> 9) * 0x537);
            }
            int bits = ((data << 10) | rem) ^ 0x5412;

            for (int i = 0; i <= 5; i++) {
                set_function_module(8, i, get_bit(bits, i));
            }
            set_function_module(8, 7, get_bit(bits, 6));
            set_function_module(8, 8, get_bit(bits, 7));
            set_function_module(7, 8, get_bit(bits, 8));
            for (int i = 9; i < 15; i++) {
                set_function_module(14 - i, 8, get_bit(bits, i));
            }

            for (int i = 0; i < 8; i++) {
                set_function_module(size - 1 - i, 8, get_bit(bits, i));
            }
            for (int i = 8; i < 15; i++) {
                set_function_module(8, size - 15 + i, get_bit(bits, i));
            }
            set_function_module(8, size - 8, true);
        }

        private void draw_version() {
            if (version < 7) {
                return;
            }
            int rem = version;
            for (int i = 0; i < 12; i++) {
                rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
            }
            int bits = (version << 12) | rem;
            for (int i = 0; i < 18; i++) {
                bool bit = get_bit(bits, i);
                int a = size - 11 + i % 3;
                int b = i / 3;
                set_function_module(a, b, bit);
                set_function_module(b, a, bit);
            }
        }

        private uint8[] add_ecc_and_interleave(uint8[] data) {
            int num_blocks = NUM_ECC_BLOCKS_H[version];
            int block_ecc_len = ECC_CODEWORDS_PER_BLOCK_H[version];
            int raw_codewords = num_raw_data_modules(version) / 8;
            int num_short_blocks = num_blocks - raw_codewords % num_blocks;
            int short_block_len = raw_codewords / num_blocks;
            int block_stride = short_block_len + 1;

            var divisor = reed_solomon_divisor(block_ecc_len);
            var blocks = new uint8[num_blocks, block_stride];
            int k = 0;
            for (int i = 0; i < num_blocks; i++) {
                int dat_len = short_block_len - block_ecc_len + (i < num_short_blocks ? 0 : 1);
                uint8[] dat = data[k:k + dat_len];
                k += dat_len;
                var ecc = reed_solomon_remainder(dat, divisor);
                for (int j = 0; j < dat_len; j++) {
                    blocks[i, j] = dat[j];
                }
                for (int j = 0; j < block_ecc_len; j++) {
                    blocks[i, block_stride - block_ecc_len + j] = ecc[j];
                }
            }

            var result = new uint8[raw_codewords];
            int n = 0;
            for (int i = 0; i < block_stride; i++) {
                for (int j = 0; j < num_blocks; j++) {
                    if (i != short_block_len - block_ecc_len || j >= num_short_blocks) {
                        result[n++] = blocks[j, i];
                    }
                }
            }
            return result;
        }

        private static uint8[] reed_solomon_divisor(int degree) {
            var result = new uint8[degree];
            result[degree - 1] = 1;
            uint8 root = 1;
            for (int i = 0; i < degree; i++) {
                for (int j = 0; j < degree; j++) {
                    result[j] = gf_multiply(result[j], root);
                    if (j + 1 < degree) {
                        result[j] = (uint8) (result[j] ^ result[j + 1]);
                    }
                }
                root = gf_multiply(root, 0x02);
            }
            return result;
        }

        private static uint8[] reed_solomon_remainder(uint8[] data, uint8[] divisor) {
            var result = new uint8[divisor.length];
            foreach (var b in data) {
                uint8 factor = (uint8) (b ^ result[0]);
                for (int i = 0; i < result.length - 1; i++) {
                    result[i] = result[i + 1];
                }
                result[result.length - 1] = 0;
                for (int i = 0; i < result.length; i++) {
                    result[i] = (uint8) (result[i] ^ gf_multiply(divisor[i], factor));
                }
            }
            return result;
        }

        private static uint8 gf_multiply(uint8 x, uint8 y) {
            int z = 0;
            for (int i = 7; i >= 0; i--) {
                z = (z << 1) ^ ((z >> 7) * 0x11D);
                z ^= ((y >> i) & 1) * x;
            }
            return (uint8) z;
        }

        private void draw_codewords(uint8[] data) {
            int i = 0;
            int total_bits = data.length * 8;
            for (int right = size - 1; right >= 1; right -= 2) {
                if (right == 6) {
                    right = 5;
                }
                bool upward = ((right + 1) & 2) == 0;
                for (int vert = 0; vert < size; vert++) {
                    for (int j = 0; j < 2; j++) {
                        int x = right - j;
                        int y = upward ? size - 1 - vert : vert;
                        if (!is_function[y, x] && i < total_bits) {
                            modules[y, x] = get_bit(data[i >> 3], 7 - (i & 7));
                            i++;
                        }
                    }
                }
            }
        }

        private void apply_mask(int mask) {
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    bool invert;
                    switch (mask) {
                    case 0: invert = (x + y) % 2 == 0; break;
                    case 1: invert = y % 2 == 0; break;
                    case 2: invert = x % 3 == 0; break;
                    case 3: invert = (x + y) % 3 == 0; break;
                    case 4: invert = (x / 3 + y / 2) % 2 == 0; break;
                    case 5: invert = x * y % 2 + x * y % 3 == 0; break;
                    case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0; break;
                    default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0; break;
                    }
                    if (invert && !is_function[y, x]) {
                        modules[y, x] = !modules[y, x];
                    }
                }
            }
        }

        private int penalty_score() {
            int result = 0;
            var history = new int[7];

            for (int y = 0; y < size; y++) {
                bool run_color = false;
                int run_len = 0;
                clear_history(history);
                for (int x = 0; x < size; x++) {
                    result += score_run_step(modules[y, x], ref run_color, ref run_len, history);
                }
                result += finder_penalty_terminate_and_count(run_color, run_len, history) * PENALTY_N3;
            }

            for (int x = 0; x < size; x++) {
                bool run_color = false;
                int run_len = 0;
                clear_history(history);
                for (int y = 0; y < size; y++) {
                    result += score_run_step(modules[y, x], ref run_color, ref run_len, history);
                }
                result += finder_penalty_terminate_and_count(run_color, run_len, history) * PENALTY_N3;
            }

            for (int y = 0; y < size - 1; y++) {
                for (int x = 0; x < size - 1; x++) {
                    bool color = modules[y, x];
                    if (color == modules[y, x + 1] && color == modules[y + 1, x] && color == modules[y + 1, x + 1]) {
                        result += PENALTY_N2;
                    }
                }
            }

            int dark = 0;
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    if (modules[y, x]) {
                        dark++;
                    }
                }
            }
            int total = size * size;
            int k = (abs_int(dark * 20 - total * 10) + total - 1) / total - 1;
            result += k * PENALTY_N4;
            return result;
        }

        private int score_run_step(bool color, ref bool run_color, ref int run_len, int[] history) {
            int result = 0;
            if (color == run_color) {
                run_len++;
                if (run_len == 5) {
                    result += PENALTY_N1;
                } else if (run_len > 5) {
                    result++;
                }
            } else {
                finder_penalty_add_history(run_len, history);
                if (!run_color) {
                    result += finder_penalty_count_patterns(history) * PENALTY_N3;
                }
                run_color = color;
                run_len = 1;
            }
            return result;
        }

        private static void clear_history(int[] history) {
            for (int i = 0; i < history.length; i++) {
                history[i] = 0;
            }
        }

        private int finder_penalty_count_patterns(int[] h) {
            int n = h[1];
            bool core = n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n;
            return (core && h[0] >= n * 4 && h[6] >= n ? 1 : 0)
                + (core && h[6] >= n * 4 && h[0] >= n ? 1 : 0);
        }

        private int finder_penalty_terminate_and_count(bool run_color, int run_len, int[] history) {
            if (run_color) {
                finder_penalty_add_history(run_len, history);
                run_len = 0;
            }
            run_len += size;
            finder_penalty_add_history(run_len, history);
            return finder_penalty_count_patterns(history);
        }

        private void finder_penalty_add_history(int run_len, int[] history) {
            if (history[0] == 0) {
                run_len += size;
            }
            for (int i = history.length - 1; i >= 1; i--) {
                history[i] = history[i - 1];
            }
            history[0] = run_len;
        }

        private static bool get_bit(int value, int i) {
            return ((value >> i) & 1) != 0;
        }

        private static int abs_int(int value) {
            return value < 0 ? -value : value;
        }
    }
}
