namespace ApkManager.Core {
    public enum ApktoolPhase {
        IDLE,
        STARTING,
        DECODING_CODE,
        DECODING_RESOURCES,
        COPYING_FILES,
        FINISHING,
        COMPLETE,
        FAILED
    }

    public class ApktoolRunner : Object {
        public signal void phase_changed(ApktoolPhase phase, string message);
        public signal void finished(bool success, string? error_message);

        private Subprocess? current_proc = null;
        private Cancellable? cancellable = null;

        public bool java_available {
            get {
                return Environment.find_program_in_path("java") != null;
            }
        }

        public async bool decode_async(string apk_path, string output_dir, DecodeMode mode, int jobs = DEFAULT_DECODE_JOBS) {
            if (!java_available) {
                finished(false, "Java runtime not found. Install a JRE 17 or newer.");
                return false;
            }

            if (!FileUtils.test(AppPaths.apktool_jar_path, FileTest.EXISTS)) {
                finished(false, "Apktool JAR not found at %s".printf(AppPaths.apktool_jar_path));
                return false;
            }

            cancellable = new Cancellable();
            phase_changed(ApktoolPhase.STARTING, "Starting Apktool…");

            var args = new Gee.ArrayList<string>();
            args.add("java");
            args.add("-Xmx%dM".printf(DEFAULT_JAVA_HEAP_MB));
            args.add("-Dfile.encoding=utf-8");
            args.add("-Djdk.util.zip.disableZip64ExtraFieldValidation=true");
            args.add("-Djdk.nio.zipfs.allowDotZipEntry=true");
            args.add("-jar");
            args.add(AppPaths.apktool_jar_path);
            args.add("d");
            args.add("-f");
            args.add("-j");
            args.add(jobs.to_string());
            args.add("-p");
            args.add(AppPaths.frameworks_dir);
            if (mode == DecodeMode.MANIFEST_ONLY) {
                args.add("-s");
                args.add("--only-manifest");
            }
            args.add("-o");
            args.add(output_dir);
            args.add(apk_path);
            var argv = args.to_array();

            try {
                DirUtils.create_with_parents(output_dir, 0700);
                current_proc = new Subprocess.newv(
                    argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
                );

                var stdout = new DataInputStream(current_proc.get_stdout_pipe());

                while (true) {
                    try {
                        string? line = yield stdout.read_line_utf8_async(Priority.DEFAULT, cancellable);
                        if (line == null) {
                            break;
                        }
                        inspect_line(line);
                    } catch (IOError e) {
                        if (cancellable != null && cancellable.is_cancelled()) {
                            break;
                        }
                        throw e;
                    }
                }

                if (cancellable != null && cancellable.is_cancelled()) {
                    phase_changed(ApktoolPhase.FAILED, "Decode cancelled");
                    finished(false, "Decode cancelled");
                    return false;
                }

                try {
                    yield current_proc.wait_check_async(cancellable);
                } catch (Error e) {
                    phase_changed(ApktoolPhase.FAILED, "Apktool failed");
                    finished(false, e.message);
                    return false;
                }

                phase_changed(ApktoolPhase.COMPLETE, "Decode complete");
                finished(true, null);
                return true;
            } catch (Error e) {
                phase_changed(ApktoolPhase.FAILED, e.message);
                finished(false, e.message);
                return false;
            } finally {
                cleanup_subprocess();
            }
        }

        public void cancel() {
            if (cancellable != null && !cancellable.is_cancelled()) {
                cancellable.cancel();
            }
            if (current_proc != null) {
                try {
                    current_proc.force_exit();
                } catch (Error e) {
                    warning("Failed to cancel Apktool: %s", e.message);
                }
            }
        }

        private void inspect_line(string line) {
            if ("Using Apktool" in line) {
                phase_changed(ApktoolPhase.STARTING, line);
            } else if ("Baksmaling" in line) {
                phase_changed(ApktoolPhase.DECODING_CODE, line);
            } else if ("Decoding" in line || "Copying raw resources" in line) {
                phase_changed(ApktoolPhase.DECODING_RESOURCES, line);
            } else if ("Copying assets" in line || "Copying lib" in line || "Copying original" in line) {
                phase_changed(ApktoolPhase.COPYING_FILES, line);
            } else if ("Copying unknown files" in line) {
                phase_changed(ApktoolPhase.FINISHING, line);
            }
        }

        private void cleanup_subprocess() {
            current_proc = null;
            cancellable = null;
        }
    }
}
