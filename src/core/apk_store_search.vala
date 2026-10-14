using ApkManager.Utils;

namespace ApkManager.Core {
    public class ApkStoreSearch : Object {
        private const string APTOIDE_USER_AGENT = "Aptoide/9.20.6";
        private const string IZZY_BASE_URL = "https://apt.izzysoft.de/fdroid";
        private const string OPENAPK_BASE_URL = "https://www.openapk.net";

        public async Gee.List<ApkStoreResult> search_all(string query, Cancellable? cancellable = null) throws Error {
            if (query.strip() == "") {
                return new Gee.ArrayList<ApkStoreResult>();
            }

            string fdroid_html = "";
            string aptoide_json = "";
            string uptodown_html = "";
            string izzy_html = "";
            string openapk_html = "";
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
            try {
                izzy_html = yield search_izzy(query, cancellable);
            } catch (Error e) {
                failures++;
                last_error = e;
            }
            try {
                openapk_html = yield search_openapk(query, cancellable);
            } catch (Error e) {
                failures++;
                last_error = e;
            }

            if (failures == 5 && last_error != null) {
                throw last_error;
            }

            var results = new Gee.ArrayList<ApkStoreResult>();
            foreach (var item in parse_fdroid_results(fdroid_html)) {
                yield enrich_fdroid_version(item, cancellable);
                results.add(item);
            }
            foreach (var item in parse_aptoide_results(aptoide_json)) {
                results.add(item);
            }
            foreach (var item in parse_uptodown_results(uptodown_html)) {
                results.add(item);
            }
            foreach (var item in parse_izzy_results(izzy_html)) {
                results.add(item);
            }
            foreach (var item in parse_openapk_results(openapk_html)) {
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

        private async string search_openapk(string query, Cancellable? cancellable) throws Error {
            var url = "%s/search/?q=%s".printf(OPENAPK_BASE_URL, Uri.escape_string(query.strip()));
            return yield HttpClient.get_string(url, HttpClient.BROWSER_USER_AGENT);
        }

        private async string search_izzy(string query, Cancellable? cancellable) throws Error {
            var form = "searchterm=%s&doFilter=Go!".printf(Uri.escape_string(query.strip()));
            return yield HttpClient.post_form(
                "%s/index.php".printf(IZZY_BASE_URL),
                form,
                HttpClient.BROWSER_USER_AGENT
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
                    "<img[^>]*class=\"package-icon\"[^>]*src=\"([^\"]+)\"[\\s\\S]*?" +
                    "<h4 class=\"package-name\">\\s*([^<]+?)\\s*</h4>[\\s\\S]*?" +
                    "<span class=\"package-summary\">([^<]*)</span>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                // match_all() does not support MatchInfo.next(). That combination
                // is undefined and returns HTML fragments as the captured fields.
                if (!block_regex.match(html, 0, out match)) {
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
                    var version_name = "";
                    var version_date = "";
                    if (app.has_member("file")) {
                        var file = app.get_object_member("file");
                        if (file != null && file.has_member("vername")) {
                            version_name = file.get_string_member("vername");
                        }
                    }
                    if (app.has_member("updated")) {
                        version_date = yyyymmdd_from_timestamp(app.get_string_member("updated"));
                    }
                    if (name == "" || package_id == "") {
                        continue;
                    }
                    results.add(new ApkStoreResult(
                        ApkStoreSource.APTOIDE,
                        name,
                        package_id,
                        "",
                        icon_url,
                        "https://en.aptoide.com/app/%s".printf(package_id),
                        version_name,
                        version_date
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
                    "<img[^>]*class=\"app_card_img\"[^>]*src=\"([^\"]+)\"[\\s\\S]*?" +
                    "<div class=\"name\">\\s*<a href=\"([^\"]+)\" title=\"Download ([^\"]+)\">\\s*<h2>([^<]+)</h2>[\\s\\S]*?" +
                    "<div class=\"author\">([^<]*)</div>\\s*<div class=\"description\">([^<]*)</div>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!row_regex.match(html, 0, out match)) {
                    return results;
                }
                while (true) {
                    var icon_url = (match.fetch(1) ?? "").strip();
                    var page_url = (match.fetch(2) ?? "").strip();
                    var title = (match.fetch(3) ?? "").strip();
                    var heading = (match.fetch(4) ?? "").strip();
                    var author = (match.fetch(5) ?? "").strip();
                    var description = (match.fetch(6) ?? "").strip();
                    var name = heading != "" ? heading : title;
                    var summary = description != "" ? description : author;
                    if (page_url != "" && name != "") {
                        results.add(new ApkStoreResult(
                            ApkStoreSource.UPTODOWN,
                            name,
                            "",
                            summary,
                            icon_url,
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

        private Gee.List<ApkStoreResult> parse_izzy_results(string html) {
            var results = new Gee.ArrayList<ApkStoreResult>();
            if (html.strip() == "") {
                return results;
            }

            try {
                var block_regex = new Regex(
                    "<div class='approw'>\\s*" +
                    "<div class='appiconbig'><img src='([^']+)'[\\s\\S]*?" +
                    "<span class='boldname'>([^<]+)</span>[\\s\\S]*?" +
                    "<span class='minor-details'>([^/]+)/\\s*([^<]+)</span>[\\s\\S]*?" +
                    "<div class='appdetailcell'>([^<]+)</div>[\\s\\S]*?" +
                    "href='index/apk/([^']+)'",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!block_regex.match(html, 0, out match)) {
                    return results;
                }
                while (true) {
                    var icon_path = (match.fetch(1) ?? "").strip();
                    var name = (match.fetch(2) ?? "").strip();
                    var version_name = (match.fetch(3) ?? "").strip();
                    var version_date = yyyymmdd_from_timestamp((match.fetch(4) ?? "").strip());
                    var summary = (match.fetch(5) ?? "").strip();
                    var package_id = (match.fetch(6) ?? "").strip();
                    if (package_id != "" && name != "") {
                        var icon_url = icon_path.has_prefix("http")
                            ? icon_path
                            : "%s/%s".printf(IZZY_BASE_URL, icon_path);
                        results.add(new ApkStoreResult(
                            ApkStoreSource.IZZYONDROID,
                            name,
                            package_id,
                            summary,
                            icon_url,
                            "%s/index.php/index/apk/%s".printf(IZZY_BASE_URL, package_id),
                            version_name,
                            version_date
                        ));
                    }
                    if (!match.next()) {
                        break;
                    }
                }
            } catch (RegexError e) {
                warning("IzzyOnDroid search parse failed: %s", e.message);
            }

            return results;
        }

        private Gee.List<ApkStoreResult> parse_openapk_results(string html) {
            var results = new Gee.ArrayList<ApkStoreResult>();
            if (html.strip() == "") {
                return results;
            }

            try {
                var block_regex = new Regex(
                    "<a href=\"/([^/]+)/([A-Za-z0-9_.]+)/\" title=\"[^\"]*\" class=\"list-item\">\\s*" +
                    "<figure[^>]*><img src=\"([^\"]+)\"[\\s\\S]*?" +
                    "<span class=\"name\">([^<]+)</span>\\s*" +
                    "<span class=\"desc\">([^<]*)</span>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!block_regex.match(html, 0, out match)) {
                    return results;
                }
                while (true) {
                    var slug = (match.fetch(1) ?? "").strip();
                    var package_id = (match.fetch(2) ?? "").strip();
                    var icon_path = (match.fetch(3) ?? "").strip();
                    var name = (match.fetch(4) ?? "").strip();
                    var summary = (match.fetch(5) ?? "").strip();
                    if (slug != "" && package_id != "" && name != "") {
                        var icon_url = icon_path.has_prefix("http")
                            ? icon_path
                            : "%s%s".printf(OPENAPK_BASE_URL, icon_path);
                        results.add(new ApkStoreResult(
                            ApkStoreSource.OPENAPK,
                            name,
                            package_id,
                            summary,
                            icon_url,
                            "%s/%s/%s/".printf(OPENAPK_BASE_URL, slug, package_id)
                        ));
                    }
                    if (!match.next()) {
                        break;
                    }
                }
            } catch (RegexError e) {
                warning("OpenAPK search parse failed: %s", e.message);
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
            case ApkStoreSource.IZZYONDROID:
                return yield resolve_izzy_download_url(result.package_id, cancellable);
            case ApkStoreSource.OPENAPK:
                return yield resolve_openapk_download_url(result, cancellable);
            default:
                return null;
            }
        }

        public bool requires_browser_download(ApkStoreResult result) {
            return result.source == ApkStoreSource.UPTODOWN;
        }

        public static string? version_code_from_download_url(string url) {
            var basename = Path.get_basename(url);
            try {
                var regex = new Regex("_(\\d+)\\.apk$", RegexCompileFlags.CASELESS);
                MatchInfo match;
                if (regex.match(basename, 0, out match)) {
                    return match.fetch(1);
                }
            } catch (RegexError e) {
                warning("Could not parse version code from %s: %s", url, e.message);
            }
            return null;
        }

        public async bool is_already_installed(
            ApkStoreResult result,
            Cancellable? cancellable = null
        ) throws Error {
            if (result.package_id.strip() == "" || requires_browser_download(result)) {
                return false;
            }

            var download_url = yield resolve_download_url(result, cancellable);
            var version_code = installed_version_key(result, download_url);

            return StoreInstallRegistry.get_default().is_installed(
                result.source,
                result.package_id,
                version_code,
                ""
            );
        }

        public void record_installed(ApkStoreResult result, string download_url, string installed_path) {
            if (result.package_id.strip() == "" || requires_browser_download(result)) {
                return;
            }

            StoreInstallRegistry.get_default().record(new StoreInstallRecord(
                result.source,
                result.package_id,
                installed_version_key(result, download_url),
                result.version_name,
                installed_path
            ));
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

        private async string resolve_openapk_download_url(ApkStoreResult result, Cancellable? cancellable) throws Error {
            var page = result.page_url.strip();
            if (page == "") {
                throw new IOError.NOT_FOUND("OpenAPK app page missing");
            }
            if (page.has_suffix("/")) {
                page = page.substring(0, page.length - 1);
            }
            var html = yield HttpClient.get_string(page + "/apk/download", HttpClient.BROWSER_USER_AGENT);
            try {
                var serve_regex = new Regex(
                    "href=\"(/serve/\\?token=[^\"]+)\"[\\s\\S]*?<span>\\(([^)]+)\\)</span>",
                    RegexCompileFlags.DOTALL
                );
                MatchInfo match;
                if (!serve_regex.match(html, 0, out match)) {
                    throw new IOError.NOT_FOUND("OpenAPK download link missing");
                }
                var serve_path = (match.fetch(1) ?? "").strip();
                var version_name = (match.fetch(2) ?? "").strip();
                if (version_name != "") {
                    result.version_name = version_name;
                }
                if (serve_path == "") {
                    throw new IOError.NOT_FOUND("OpenAPK download link missing");
                }
                return "%s%s".printf(OPENAPK_BASE_URL, serve_path);
            } catch (RegexError e) {
                throw new IOError.FAILED("OpenAPK download parse failed: %s".printf(e.message));
            }
        }

        private static string installed_version_key(ApkStoreResult result, string download_url) {
            var from_url = version_code_from_download_url(download_url);
            if (from_url != null && from_url != "") {
                return from_url;
            }
            return result.version_name.strip();
        }

        private static string apk_download_filename(ApkStoreResult result, string download_url) {
            var filename = Path.get_basename(download_url);
            if (filename.has_suffix(".apk")) {
                return filename;
            }
            var version = result.version_name.strip().replace(" ", "");
            if (result.package_id != "" && version != "") {
                return "%s_%s.apk".printf(result.package_id, version);
            }
            if (result.package_id != "") {
                return "%s.apk".printf(result.package_id);
            }
            return "%s.apk".printf(result.name.replace(" ", "-").casefold());
        }

        private async string resolve_izzy_download_url(string package_id, Cancellable? cancellable) throws Error {
            var url = "%s/api/v1/packages/%s".printf(IZZY_BASE_URL, Uri.escape_string(package_id));
            var json_text = yield HttpClient.get_string(url, HttpClient.DEFAULT_USER_AGENT);
            var parser = new Json.Parser();
            parser.load_from_data(json_text, -1);
            var root = parser.get_root().get_object();
            if (root == null || !root.has_member("suggestedVersionCode")) {
                throw new IOError.NOT_FOUND("IzzyOnDroid package metadata missing version code");
            }
            var version_code = int.parse(root.get_string_member("suggestedVersionCode"));
            return "%s/repo/%s_%d.apk".printf(IZZY_BASE_URL, package_id, version_code);
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

        private async void enrich_fdroid_version(ApkStoreResult result, Cancellable? cancellable) {
            if (result.package_id.strip() == "") {
                return;
            }

            try {
                var url = "https://f-droid.org/api/v1/packages/%s".printf(
                    Uri.escape_string(result.package_id)
                );
                var json_text = yield HttpClient.get_string(url, HttpClient.DEFAULT_USER_AGENT);
                var parser = new Json.Parser();
                parser.load_from_data(json_text, -1);
                var root = parser.get_root().get_object();
                if (root == null || !root.has_member("suggestedVersionCode") || !root.has_member("packages")) {
                    return;
                }
                var suggested_code = root.get_int_member("suggestedVersionCode");
                var packages = root.get_array_member("packages");
                if (packages == null) {
                    return;
                }
                for (uint i = 0; i < packages.get_length(); i++) {
                    var package_info = packages.get_object_element(i);
                    if (package_info == null || !package_info.has_member("versionCode")) {
                        continue;
                    }
                    if (package_info.get_int_member("versionCode") != suggested_code) {
                        continue;
                    }
                    if (package_info.has_member("versionName")) {
                        result.version_name = package_info.get_string_member("versionName");
                    }
                    break;
                }
            } catch (Error e) {
                warning("Could not load F-Droid version for %s: %s", result.package_id, e.message);
            }
        }

        private static string yyyymmdd_from_timestamp(string value) {
            var trimmed = value.strip();
            if (trimmed.length < 10) {
                return "";
            }
            return trimmed.substring(0, 10).replace("-", "");
        }

        public async string download_apk(
            ApkStoreResult result,
            Cancellable? cancellable = null
        ) throws Error {
            var download_url = yield resolve_download_url(result, cancellable);
            if (download_url == null) {
                throw new IOError.NOT_SUPPORTED("No direct download for this source");
            }

            var filename = apk_download_filename(result, download_url);

            var destination = Path.build_filename(AppPaths.downloads_dir, filename);
            if (FileUtils.test(destination, FileTest.EXISTS)) {
                FileUtils.remove(destination);
            }

            var bytes = yield HttpClient.get_bytes(
                download_url,
                result.source == ApkStoreSource.APTOIDE ? APTOIDE_USER_AGENT : HttpClient.DEFAULT_USER_AGENT
            );
            FileUtils.set_data(destination, bytes.get_data());
            return destination;
        }

    }
}
