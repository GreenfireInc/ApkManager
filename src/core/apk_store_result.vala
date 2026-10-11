namespace ApkManager.Core {
    public enum ApkStoreSource {
        FDROID,
        APTOIDE,
        UPTODOWN
    }

    public class ApkStoreResult : Object {
        public ApkStoreSource source { get; construct; }
        public string name { get; construct; }
        public string package_id { get; construct; }
        public string summary { get; construct; }
        public string icon_url { get; construct; }
        public string page_url { get; construct; }
        public string version_name { get; construct set; default = ""; }
        public string version_date { get; construct set; default = ""; }

        public ApkStoreResult(
            ApkStoreSource source,
            string name,
            string package_id,
            string summary,
            string icon_url,
            string page_url,
            string version_name = "",
            string version_date = ""
        ) {
            Object(
                source: source,
                name: name,
                package_id: package_id,
                summary: summary,
                icon_url: icon_url,
                page_url: page_url,
                version_name: version_name,
                version_date: version_date
            );
        }

        public string version_suffix {
            owned get {
                if (version_name.strip() == "") {
                    return "";
                }
                if (version_date.strip() != "") {
                    return "(v.%s;%s)".printf(version_name.strip(), version_date.strip());
                }
                return "(v.%s)".printf(version_name.strip());
            }
        }

        public string source_label {
            get {
                switch (source) {
                case ApkStoreSource.FDROID:
                    return "F-Droid";
                case ApkStoreSource.APTOIDE:
                    return "Aptoide";
                case ApkStoreSource.UPTODOWN:
                    return "Uptodown";
                default:
                    return "Unknown";
                }
            }
        }

        public string repository_icon_basename {
            get {
                switch (source) {
                case ApkStoreSource.FDROID:
                    return "appRepo.fdroid.svg";
                case ApkStoreSource.APTOIDE:
                    return "appRepo.aptoide.svg";
                case ApkStoreSource.UPTODOWN:
                    return "appRepo.uptodown.svg";
                default:
                    return "";
                }
            }
        }
    }

    public class StoreSourceFilterItem : Object {
        public string label { get; construct; }
        public string? icon_basename { get; construct set; }

        public StoreSourceFilterItem(string label, string? icon_basename = null) {
            Object(label: label, icon_basename: icon_basename);
        }

        public string? icon_path {
            owned get {
                if (icon_basename == null || icon_basename.strip() == "") {
                    return null;
                }
                return AppPaths.store_repository_icon(icon_basename);
            }
        }

        public string? icon_resource {
            owned get {
                if (icon_basename == null || icon_basename.strip() == "") {
                    return null;
                }
                return "/com/github/ApkManager/icons/storesRepositories/%s".printf(icon_basename);
            }
        }
    }
}
