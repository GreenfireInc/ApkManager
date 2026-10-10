namespace ApkManager.Utils {
    public class HttpClient : Object {
        public const string DEFAULT_USER_AGENT = "ApkManager/0.1 (+https://github.com/ApkManager)";

        public static async string get_string(string url, string? user_agent = DEFAULT_USER_AGENT) throws Error {
            return yield run_curl({ "-fsSL", "--max-time", "45", url }, user_agent, null);
        }

        public static async Bytes get_bytes(string url, string? user_agent = DEFAULT_USER_AGENT) throws Error {
            var text = yield get_string(url, user_agent);
            return new Bytes(text.data);
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

        private static async string run_curl(
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

            string? stdout_text = null;
            string? stderr_text = null;
            yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);

            if (!proc.get_successful()) {
                var detail = stderr_text != null && stderr_text.strip() != "" ? stderr_text.strip() : "curl failed";
                throw new IOError.FAILED("%s (exit %d)".printf(detail, proc.get_exit_status()));
            }

            return stdout_text ?? "";
        }
    }
}
