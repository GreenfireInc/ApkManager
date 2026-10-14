using Cairo;

namespace ApkManager.Core {
    public class ApkVectorDrawable : Object {
        private const int OUTPUT_PX = 128;

        public static Bytes? render(ApkBinaryXml.Element root) {
            if (root.name != "vector") {
                return null;
            }
            double viewport_w = ApkBinaryXml.float_attribute(root, "viewportWidth", 24.0);
            double viewport_h = ApkBinaryXml.float_attribute(root, "viewportHeight", 24.0);
            if (viewport_w <= 0 || viewport_h <= 0) {
                return null;
            }

            var surface = new ImageSurface(Format.ARGB32, OUTPUT_PX, OUTPUT_PX);
            var ctx = new Context(surface);
            ctx.save();
            ctx.scale(OUTPUT_PX / viewport_w, OUTPUT_PX / viewport_h);

            foreach (var child in root.children) {
                if (child.name != "path") {
                    continue;
                }
                var path_data = ApkBinaryXml.string_attribute(child, "pathData");
                if (path_data == null || path_data == "") {
                    continue;
                }
                if (!apply_path(ctx, path_data)) {
                    continue;
                }
                uint32 color = (uint32) 0xFF000000;
                var color_attr = ApkBinaryXml.color_attribute(child, "fillColor");
                if (color_attr != null) {
                    color = color_attr;
                }
                set_source_color(ctx, color);
                ctx.fill_preserve();
                ctx.new_path();
            }

            ctx.restore();
            return surface_to_png(surface);
        }

        private static void set_source_color(Context ctx, uint32 argb) {
            double a = ((argb >> 24) & 0xff) / 255.0;
            double r = ((argb >> 16) & 0xff) / 255.0;
            double g = ((argb >> 8) & 0xff) / 255.0;
            double b = (argb & 0xff) / 255.0;
            if (a <= 0) {
                a = 1.0;
            }
            ctx.set_source_rgba(r, g, b, a);
        }

        private static bool apply_path(Context ctx, string path_data) {
            var tokens = tokenize_path(path_data);
            if (tokens.length == 0) {
                return false;
            }

            int index = 0;
            double x = 0;
            double y = 0;
            double start_x = 0;
            double start_y = 0;
            string cmd = "";

            while (index < tokens.length) {
                string token = tokens[index];
                if (token.length == 1 && is_command(token[0])) {
                    cmd = token;
                    index++;
                    continue;
                }
                if (cmd == "") {
                    return false;
                }

                if (cmd == "M" || cmd == "m") {
                    double px = double.parse(tokens[index++]);
                    double py = double.parse(tokens[index++]);
                    if (cmd == "m") {
                        px += x;
                        py += y;
                    }
                    x = px;
                    y = py;
                    start_x = x;
                    start_y = y;
                    ctx.move_to(x, y);
                    cmd = cmd == "M" ? "L" : "l";
                    continue;
                }
                if (cmd == "L" || cmd == "l") {
                    double px = double.parse(tokens[index++]);
                    double py = double.parse(tokens[index++]);
                    if (cmd == "l") {
                        px += x;
                        py += y;
                    }
                    x = px;
                    y = py;
                    ctx.line_to(x, y);
                    continue;
                }
                if (cmd == "H" || cmd == "h") {
                    double px = double.parse(tokens[index++]);
                    if (cmd == "h") {
                        px += x;
                    }
                    x = px;
                    ctx.line_to(x, y);
                    continue;
                }
                if (cmd == "V" || cmd == "v") {
                    double py = double.parse(tokens[index++]);
                    if (cmd == "v") {
                        py += y;
                    }
                    y = py;
                    ctx.line_to(x, y);
                    continue;
                }
                if (cmd == "C" || cmd == "c") {
                    double x1 = double.parse(tokens[index++]);
                    double y1 = double.parse(tokens[index++]);
                    double x2 = double.parse(tokens[index++]);
                    double y2 = double.parse(tokens[index++]);
                    double px = double.parse(tokens[index++]);
                    double py = double.parse(tokens[index++]);
                    if (cmd == "c") {
                        x1 += x;
                        y1 += y;
                        x2 += x;
                        y2 += y;
                        px += x;
                        py += y;
                    }
                    ctx.curve_to(x1, y1, x2, y2, px, py);
                    x = px;
                    y = py;
                    continue;
                }
                if (cmd == "Z" || cmd == "z") {
                    ctx.close_path();
                    x = start_x;
                    y = start_y;
                    continue;
                }
                return false;
            }
            return true;
        }

        private static bool is_command(char ch) {
            return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
        }

        private static string[] tokenize_path(string path_data) {
            var tokens = new Gee.ArrayList<string>();
            var current = new StringBuilder();
            for (int i = 0; i < path_data.length; i++) {
                char ch = path_data[i];
                if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == ',') {
                    if (current.len > 0) {
                        tokens.add(current.str);
                        current = new StringBuilder();
                    }
                    continue;
                }
                if (is_command(ch)) {
                    if (current.len > 0) {
                        tokens.add(current.str);
                        current = new StringBuilder();
                    }
                    tokens.add(ch.to_string());
                    continue;
                }
                current.append_c(ch);
            }
            if (current.len > 0) {
                tokens.add(current.str);
            }
            return tokens.to_array();
        }

        private static Bytes? surface_to_png(ImageSurface surface) {
            string? path = null;
            try {
                FileUtils.open_tmp("apk-icon-XXXXXX.png", out path);
                surface.write_to_png(path);
                var file = File.new_for_path(path);
                string? etag;
                Bytes png = file.load_bytes(null, out etag);
                FileUtils.remove(path);
                return png;
            } catch (Error e) {
                warning("Failed to encode vector drawable PNG: %s", e.message);
                if (path != null) {
                    try {
                        FileUtils.remove(path);
                    } catch (Error ignored) {
                    }
                }
                return null;
            }
        }
    }
}
