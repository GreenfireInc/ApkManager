namespace ApkManager.Core {
    public class HostDistro : Object {
        private const string FALLBACK_ICON = "apk-manager-distro-linux";

        // Recognized families, in match order, with their badge icon names.
        private const string[] FAMILY_IDS = { "linuxmint", "ubuntu", "debian", "fedora" };
        private const string[] FAMILY_NAMES = { "Linux Mint", "Ubuntu", "Debian", "Fedora" };

        // Sandboxed builds see their runtime's /etc/os-release, not the host's.
        private const string[] OS_RELEASE_PATHS = {
            "/run/host/os-release",                       // Flatpak
            "/var/lib/snapd/hostfs/etc/os-release",       // Snap
            "/etc/os-release",
            "/usr/lib/os-release"
        };

        public string id { get; private set; default = "linux"; }
        public string pretty_name { get; private set; default = "Linux"; }
        public string version_id { get; private set; default = ""; }
        public string? family_id { get; private set; default = null; }
        public string? family_name { get; private set; default = null; }
        public bool matched_by_id_like { get; private set; default = false; }

        public string icon_name {
            owned get {
                return family_id != null ? "apk-manager-distro-%s".printf(family_id) : FALLBACK_ICON;
            }
        }

        public static HostDistro detect() {
            var distro = new HostDistro();
            var fields = read_os_release();
            if (fields == null) {
                return distro;
            }

            distro.id = (fields["ID"] ?? "linux").down();
            distro.version_id = fields["VERSION_ID"] ?? "";
            distro.pretty_name = fields["PRETTY_NAME"] ?? fields["NAME"] ?? "Linux";

            int index = family_index(distro.id);
            if (index < 0) {
                foreach (var like in (fields["ID_LIKE"] ?? "").down().split(" ")) {
                    index = family_index(like.strip());
                    if (index >= 0) {
                        distro.matched_by_id_like = true;
                        break;
                    }
                }
            }
            if (index >= 0) {
                distro.family_id = FAMILY_IDS[index];
                distro.family_name = FAMILY_NAMES[index];
            }
            return distro;
        }

        private static int family_index(string id) {
            for (int i = 0; i < FAMILY_IDS.length; i++) {
                if (FAMILY_IDS[i] == id) {
                    return i;
                }
            }
            return -1;
        }

        private static HashTable<string, string>? read_os_release() {
            foreach (var path in OS_RELEASE_PATHS) {
                string contents;
                try {
                    if (!FileUtils.get_contents(path, out contents)) {
                        continue;
                    }
                } catch (FileError e) {
                    continue;
                }
                return parse_os_release(contents);
            }
            return null;
        }

        private static HashTable<string, string> parse_os_release(string contents) {
            var fields = new HashTable<string, string>(str_hash, str_equal);
            foreach (var raw_line in contents.split("\n")) {
                var line = raw_line.strip();
                if (line == "" || line.has_prefix("#")) {
                    continue;
                }
                int eq = line.index_of_char('=');
                if (eq <= 0) {
                    continue;
                }
                var key = line.substring(0, eq).strip();
                var value = line.substring(eq + 1).strip();
                if (value.length >= 2
                    && (value.has_prefix("\"") && value.has_suffix("\"")
                        || value.has_prefix("'") && value.has_suffix("'"))) {
                    value = value.substring(1, value.length - 2);
                }
                fields[key] = value.compress();
            }
            return fields;
        }
    }
}
