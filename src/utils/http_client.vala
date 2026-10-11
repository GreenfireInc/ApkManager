namespace ApkManager.Utils {
    public class HttpClient : Object {
        public const string DEFAULT_USER_AGENT = "ApkManager/0.1 (+https://github.com/ApkManager)";
        public const string BROWSER_USER_AGENT =
            "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0";

        public static async string get_string(string url, string? user_agent = DEFAULT_USER_AGENT) throws Error {
            var bytes = yield run_curl({ "-fsSL", "--max-time", "45", url }, user_agent, null);
            return (string) bytes.get_data();
        }

        public static async Bytes get_bytes(string url, string? user_agent = DEFAULT_USER_AGENT) throws Error {
            return yield run_curl({ "-fsSL", "--max-time", "45", url }, user_agent, null);
        }

        public static async string get_string_with_query(
            string base_url,
            Gee.Map<string, string> query,
            string? user_agent = DEFAULT_USER_AGENT
        ) throws Error {
            var builder = new StringBuilder(base_url);
            builder.append(base_url.contains("?") ? "&" : "?");
            bool first = true;
            foreach (var entry in query.entries) {
                if (!first) {
                    builder.append("&");
                }
                first = false;
                builder.append(Uri.escape_string(entry.key));
                builder.append("=");
                builder.append(Uri.escape_string(entry.value));
            }
            return yield get_string(builder.str, user_agent);
        }

        public static bool looks_like_image(Bytes bytes) {
            if (bytes.length < 4) {
                return false;
            }
            var data = bytes.get_data();
            if (data[0] == 0x89 && data[1] == (uint8) 'P' && data[2] == (uint8) 'N' && data[3] == (uint8) 'G') {
                return true;
            }
            if (data[0] == 0xFF && data[1] == 0xD8) {
                return true;
            }
            if (data[0] == (uint8) 'G' && data[1] == (uint8) 'I' && data[2] == (uint8) 'F') {
                return true;
            }
            if (bytes.length >= 12
                && data[0] == (uint8) 'R' && data[1] == (uint8) 'I' && data[2] == (uint8) 'F' && data[3] == (uint8) 'F'
                && data[8] == (uint8) 'W' && data[9] == (uint8) 'E' && data[10] == (uint8) 'B' && data[11] == (uint8) 'P') {
                return true;
            }
            return false;
        }

        private static async Bytes run_curl(
            owned string[] curl_args,
            string? user_agent,
            string? post_body
        ) throws Error {
            // Vala string[] is NULL-terminated. Gee.ArrayList.to_array() is not,
            // and g_subprocess_newv() walks argv with g_strdupv() until NULL.
            var argv = new string[] { "curl" };
            foreach (var arg in curl_args) {
                argv += arg;
            }
            if (user_agent != null && user_agent.strip() != "") {
                argv += "-A";
                argv += user_agent;
            }
            if (post_body != null) {
                argv += "-X";
                argv += "POST";
                argv += "-H";
                argv += "Content-Type: application/x-www-form-urlencoded";
                argv += "--data-raw";
                argv += post_body;
            }

            var proc = new Subprocess.newv(
                argv,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );

            Bytes? stdout_buf = null;
            Bytes? stderr_buf = null;
            yield proc.communicate_async(null, null, out stdout_buf, out stderr_buf);

            if (!proc.get_successful()) {
                var detail = "curl failed";
                if (stderr_buf != null && stderr_buf.length > 0) {
                    detail = (string) stderr_buf.get_data();
                }
                throw new IOError.FAILED("%s (exit %d)".printf(detail.strip(), proc.get_exit_status()));
            }

            return stdout_buf ?? new Bytes({});
        }
    }
}
