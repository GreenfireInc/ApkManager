namespace ApkManager.Core {
    public enum DecodeMode {
        MANIFEST_ONLY,
        FULL
    }

    public enum DecodeState {
        RAW_ONLY,
        DECODING,
        DECODED,
        FAILED,
        CANCELLED
    }

    public class DecodeSession : Object {
        public string id { get; construct; }
        public string apk_path { get; construct; }
        public string? cache_dir { get; set; }
        public DecodeState state { get; set; default = DecodeState.RAW_ONLY; }
        public DecodeMode last_mode { get; set; default = DecodeMode.MANIFEST_ONLY; }
        public string? label { get; set; }
        public int64 opened_at { get; set; }

        public DecodeSession(string id, string apk_path) {
            Object(id: id, apk_path: apk_path);
            opened_at = GLib.get_real_time();
            label = Path.get_basename(apk_path);
        }

        public string cache_key(DecodeMode mode) {
            var mode_tag = mode == DecodeMode.MANIFEST_ONLY ? "manifest" : "full";
            return "%s-%s".printf(id, mode_tag);
        }
    }
}
