using ApkManager.Utils;

namespace ApkManager.Core {
    public class ApkStoreSearch : Object {
        private const string APTOIDE_USER_AGENT = "Aptoide/9.20.6";

        public async Gee.List<ApkStoreResult> search_all(string query, Cancellable? cancellable = null) throws Error {
            if (query.strip() == "") {
                return new Gee.ArrayList<ApkStoreResult>();
            }

            string fdroid_html = "";
            string aptoide_json = "";
            string uptodown_html = "";
            int failures = 0;
            Error? last_error = null;

            try {
                fdroid_html = yield search_fdroid(query, cancellable);
            } catch (Error e) {
                failures++;
                last_error = e;
            }
            try {
                aptoide_json = yield search_aptoide(query, cancellable);
            } catch (Error e) {
                failures++;
                last_error = e;
            }
            try {
                uptodown_html = yield search_uptodown(query, cancellable);
            } catch (Error e) {
                failures++;
                last_error = e;
            }

            if (failures == 3 && last_error != null) {
                throw last_error;
            }

            var results = new Gee.ArrayList<ApkStoreResult>();
            foreach (var item in parse_fdroid_results(fdroid_html)) {
                results.add(item);
            }
            foreach (var item in parse_aptoide_results(aptoide_json)) {
                results.add(item);
            }
            foreach (var item in parse_uptodown_results(uptodown_html)) {
                results.add(item);
            }
            return results;
        }

        private async string search_fdroid(string query, Cancellable? cancellable) throws Error {
            var url = "https://search.f-droid.org/?q=%s".printf(Uri.escape_string(query.strip()));
            return yield HttpClient.get_string(url, HttpClient.DEFAULT_USER_AGENT);
        }

        private async string search_aptoide(string query, Cancellable? cancellable) throws Error {
            var url = "https://ws2.aptoide.com/api/7/listSearchApps?query=%s&limit=20".printf(
                Uri.escape_string(query.strip())
            );
            return yield HttpClient.get_string(url, APTOIDE_USER_AGENT);
        }

        private async string search_uptodown(string query, Cancellable? cancellable) throws Error {
            var url = "https://en.uptodown.com/android/search?query=%s".printf(
                Uri.escape_string(query.strip())
            );
            return yield HttpClient.get_string(
                url,
                "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
            );
        }

        private Gee.List<ApkStoreResult> parse_fdroid_results(string html) {
            var results = new Gee.ArrayList<ApkStoreResult>();
            if (html.strip() == "") {
                return results;
            }

            try {
                var block_regex = new Regex(
                    "<a class=\"package-header\" href=\"https://f-droid.org/en/packages/([^\"]+)\">[\\s\\S]*?" +
                    "class=\"package-icon\" src=\"([^\"]+)\"[\\s\\S]*?" +
                    "<h4 class=\"package-name\">\\s*([^<]+?)\\s*</h4>[\\s\\S]*?" +
                    "<span class=\"package-summary\">([^<]*)</span>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!block_regex.match_all(html, 0, out match)) {
                    return results;
                }
                while (true) {
                    var package_id = (match.fetch(1) ?? "").strip();
                    var icon_url = (match.fetch(2) ?? "").strip();
                    var name = (match.fetch(3) ?? "").strip();
                    var summary = (match.fetch(4) ?? "").strip();
                    if (package_id != "" && name != "") {
                        results.add(new ApkStoreResult(
                            ApkStoreSource.FDROID,
                            name,
                            package_id,
                            summary,
                            icon_url,
                            "https://f-droid.org/en/packages/%s/".printf(package_id)
                        ));
                    }
                    if (!match.next()) {
                        break;
                    }
                }
            } catch (RegexError e) {
                warning("F-Droid search parse failed: %s", e.message);
            }

            return results;
        }

        private Gee.List<ApkStoreResult> parse_aptoide_results(string json_text) {
            var results = new Gee.ArrayList<ApkStoreResult>();
            if (json_text.strip() == "") {
                return results;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(json_text, -1);
                var root = parser.get_root().get_object();
                if (root == null || !root.has_member("datalist")) {
                    return results;
                }
                var datalist = root.get_object_member("datalist");
                if (datalist == null || !datalist.has_member("list")) {
                    return results;
                }
                var list = datalist.get_array_member("list");
                if (list == null) {
                    return results;
                }

                for (uint i = 0; i < list.get_length(); i++) {
                    var app = list.get_object_element(i);
                    if (app == null) {
                        continue;
                    }
                    var name = app.has_member("name") ? app.get_string_member("name") : "";
                    var package_id = app.has_member("package") ? app.get_string_member("package") : "";
                    var icon_url = app.has_member("icon") ? app.get_string_member("icon") : "";
                    if (name == "" || package_id == "") {
                        continue;
                    }
                    results.add(new ApkStoreResult(
                        ApkStoreSource.APTOIDE,
                        name,
                        package_id,
                        "",
                        icon_url,
                        "https://en.aptoide.com/app/%s".printf(package_id)
                    ));
                }
            } catch (Error e) {
                warning("Aptoide search parse failed: %s", e.message);
            }

            return results;
        }

        private Gee.List<ApkStoreResult> parse_uptodown_results(string html) {
            var results = new Gee.ArrayList<ApkStoreResult>();
            if (html.strip() == "") {
                return results;
            }

            try {
                var row_regex = new Regex(
                    "<div class=\"name\">\\s*<a href=\"([^\"]+)\" title=\"Download ([^\"]+)\">\\s*<h2>([^<]+)</h2>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!row_regex.match_all(html, 0, out match)) {
                    return results;
                }
                while (true) {
                    var page_url = (match.fetch(1) ?? "").strip();
                    var title = (match.fetch(2) ?? "").strip();
                    var heading = (match.fetch(3) ?? "").strip();
                    var name = heading != "" ? heading : title;
                    if (page_url != "" && name != "") {
                        results.add(new ApkStoreResult(
                            ApkStoreSource.UPTODOWN,
                            name,
                            "",
                            "",
                            "",
                            page_url
                        ));
                    }
                    if (!match.next()) {
                        break;
                    }
                }
            } catch (RegexError e) {
                warning("Uptodown search parse failed: %s", e.message);
            }

            return results;
        }

        public async string? resolve_download_url(ApkStoreResult result, Cancellable? cancellable = null) throws Error {
            switch (result.source) {
            case ApkStoreSource.FDROID:
                return yield resolve_fdroid_download_url(result.package_id, cancellable);
            case ApkStoreSource.APTOIDE:
                return yield resolve_aptoide_download_url(result.package_id, cancellable);
            case ApkStoreSource.UPTODOWN:
                return null;
            default:
                return null;
            }
        }

        public bool requires_browser_download(ApkStoreResult result) {
            return result.source == ApkStoreSource.UPTODOWN;
        }

        public string browser_download_url(ApkStoreResult result) {
            if (result.page_url.has_suffix("/")) {
                return result.page_url + "download";
            }
            return result.page_url + "/download";
        }

        private async string resolve_fdroid_download_url(string package_id, Cancellable? cancellable) throws Error {
            var url = "https://f-droid.org/api/v1/packages/%s".printf(Uri.escape_string(package_id));
            var json_text = yield HttpClient.get_string(url, HttpClient.DEFAULT_USER_AGENT);
            var parser = new Json.Parser();
            parser.load_from_data(json_text, -1);
            var root = parser.get_root().get_object();
            if (root == null || !root.has_member("suggestedVersionCode")) {
                throw new IOError.NOT_FOUND("F-Droid package metadata missing version code");
            }
            var version_code = root.get_int_member("suggestedVersionCode");
            return "https://f-droid.org/repo/%s_%d.apk".printf(package_id, (int) version_code);
        }

        private async string resolve_aptoide_download_url(string package_id, Cancellable? cancellable) throws Error {
            var url = "https://ws2.aptoide.com/api/7/getApp?package_name=%s".printf(
                Uri.escape_string(package_id)
            );
            var json_text = yield HttpClient.get_string(url, APTOIDE_USER_AGENT);
            var parser = new Json.Parser();
            parser.load_from_data(json_text, -1);
            var root = parser.get_root().get_object();
            if (root == null || !root.has_member("nodes")) {
                throw new IOError.NOT_FOUND("Aptoide app metadata missing");
            }
            var nodes = root.get_object_member("nodes");
            if (nodes == null || !nodes.has_member("meta")) {
                throw new IOError.NOT_FOUND("Aptoide app metadata missing");
            }
            var meta = nodes.get_object_member("meta");
            if (meta == null || !meta.has_member("data")) {
                throw new IOError.NOT_FOUND("Aptoide app metadata missing");
            }
            var data = meta.get_object_member("data");
            if (data == null || !data.has_member("file")) {
                throw new IOError.NOT_FOUND("Aptoide download path missing");
            }
            var file = data.get_object_member("file");
            if (file == null || !file.has_member("path")) {
                throw new IOError.NOT_FOUND("Aptoide download path missing");
            }
            return file.get_string_member("path");
        }

        public async string download_apk(
            ApkStoreResult result,
            Cancellable? cancellable = null
        ) throws Error {
            var download_url = yield resolve_download_url(result, cancellable);
            if (download_url == null) {
                throw new IOError.NOT_SUPPORTED("No direct download for this source");
            }

            var filename = Path.get_basename(download_url);
            if (!filename.has_suffix(".apk")) {
                filename = "%s.apk".printf(
                    result.package_id != "" ? result.package_id : result.name.replace(" ", "-").casefold()
                );
            }

            var destination = Path.build_filename(AppPaths.downloads_dir, filename);
            if (FileUtils.test(destination, FileTest.EXISTS)) {
                FileUtils.remove(destination);
            }

            var bytes = yield HttpClient.get_bytes(
                download_url,
                result.source == ApkStoreSource.APTOIDE ? APTOIDE_USER_AGENT : HttpClient.DEFAULT_USER_AGENT
            );
            FileUtils.set_contents(destination, (string) bytes.get_data(), bytes.length);
            return destination;
        }

    }
}
