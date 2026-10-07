using Json;

namespace ApkManager.Core {
    public class DecodeSessionRegistry : Object {
        private Gee.ArrayList<DecodeSession> sessions = new Gee.ArrayList<DecodeSession>();

        public DecodeSessionRegistry() {
            load();
        }

        public Gee.List<DecodeSession> get_sessions() {
            return sessions;
        }

        public DecodeSession get_or_create(string apk_path) {
            var hash = ApkArchive.compute_sha256(apk_path);
            var id = hash ?? Path.get_basename(apk_path);

            foreach (var session in sessions) {
                if (session.id == id) {
                    session.opened_at = GLib.get_real_time();
                    save();
                    return session;
                }
            }

            var created = new DecodeSession(id, apk_path);
            sessions.insert(0, created);
            save();
            return created;
        }

        public void save() {
            var root = new Json.Builder();
            root.begin_array();

            foreach (var session in sessions) {
                root.begin_object();
                root.set_member_name("id").add_string_value(session.id);
                root.set_member_name("apkPath").add_string_value(session.apk_path);
                root.set_member_name("cacheDir").add_string_value(session.cache_dir ?? "");
                root.set_member_name("state").add_int_value((int) session.state);
                root.set_member_name("lastMode").add_int_value((int) session.last_mode);
                root.set_member_name("label").add_string_value(session.label ?? "");
                root.set_member_name("openedAt").add_int_value(session.opened_at);
                root.end_object();
            }

            root.end_array();
            var node = root.get_root();

            try {
                var generator = new Json.Generator();
                generator.set_root(node);
                generator.to_file(AppPaths.sessions_file);
            } catch (Error e) {
                warning("Failed to save sessions: %s", e.message);
            }
        }

        private void load() {
            if (!FileUtils.test(AppPaths.sessions_file, FileTest.EXISTS)) {
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_file(AppPaths.sessions_file);
                var root = parser.get_root();
                if (root.get_node_type() != Json.NodeType.ARRAY) {
                    return;
                }

                var array = root.get_array();
                for (int i = 0; i < array.get_length(); i++) {
                    var obj = array.get_object_element(i);
                    var id = obj.get_string_member("id");
                    var apk_path = obj.get_string_member("apkPath");
                    var session = new DecodeSession(id, apk_path);
                    session.cache_dir = obj.get_string_member("cacheDir");
                    if (session.cache_dir == "") {
                        session.cache_dir = null;
                    }
                    session.state = (DecodeState) obj.get_int_member("state");
                    session.last_mode = (DecodeMode) obj.get_int_member("lastMode");
                    session.label = obj.get_string_member("label");
                    session.opened_at = obj.get_int_member("openedAt");
                    sessions.add(session);
                }
            } catch (Error e) {
                warning("Failed to load sessions: %s", e.message);
            }
        }
    }
}
