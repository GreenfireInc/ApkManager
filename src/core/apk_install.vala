namespace ApkManager.Core {
    public class ApkInstall {
        public static string install(string apk_path) throws Error {
            var install_dir = AppSettings.get_default().get_install_path();
            DirUtils.create_with_parents(install_dir, 0755);

            var basename = Path.get_basename(apk_path);
            var dest = Path.build_filename(install_dir, basename);

            var src = File.new_for_path(apk_path);
            var dst = File.new_for_path(dest);
            if (src.equal(dst)) {
                return dest;
            }
            if (AppSettings.get_default().get_remove_original_on_install()) {
                src.move(dst, FileCopyFlags.OVERWRITE, null, null);
            } else {
                src.copy(dst, FileCopyFlags.OVERWRITE, null, null);
            }
            return dest;
        }
    }
}
