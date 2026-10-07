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
        private Gee.ArrayList<string> output_tail = new Gee.ArrayList<string>();

        public bool java_available {
            get {
                return Environment.find_program_in_path("java") != null;
            }
        }

        public async bool decode_async(string apk_path, string output_dir, DecodeMode mode) {
            if (!java_available) {
                finished(false, "Java runtime not found. Install a JRE 17 or newer.");
                return false;
            }

            if (!FileUtils.test(AppPaths.apktool_jar_path, FileTest.EXISTS)) {
                finished(false, "Apktool JAR not found at %s".printf(AppPaths.apktool_jar_path));
                return false;
            }

            cancellable = new Cancellable();
            output_tail.clear();
            phase_changed(ApktoolPhase.STARTING, "Starting Apktool…");

            // Pinned Apktool 2.9.3 does not implement -j/--jobs or --only-manifest.
            // Quick manifest uses -s -r --force-manifest (skip smali and resources,
            // still decode AndroidManifest.xml).
            //
            // Build a Vala string[], not Gee.ArrayList.to_array(). g_subprocess_newv()
            // requires a NULL-terminated argv. Gee's to_array() is length-prefixed only,
            // so g_strdupv() reads past the end and segfaults.
            var argv = new string[] {
                "java",
                "-Xmx%dM".printf(DEFAULT_JAVA_HEAP_MB),
                "-Dfile.encoding=utf-8",
                "-Djdk.util.zip.disableZip64ExtraFieldValidation=true",
                "-Djdk.nio.zipfs.allowDotZipEntry=true",
                "-jar",
                AppPaths.apktool_jar_path,
                "d",
                "-f",
                "-p",
                AppPaths.frameworks_dir
            };
            if (mode == DecodeMode.MANIFEST_ONLY) {
                argv += "-s";
                argv += "-r";
                argv += "--force-manifest";
            }
            argv += "-o";
            argv += output_dir;
            argv += apk_path;

            try {
                DirUtils.create_with_parents(output_dir, 0700);
                current_proc = new Subprocess.newv(
                    argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE
                );

                var stdout = new DataInputStream(current_proc.get_stdout_pipe());
                // The pipe is owned by the Subprocess. Closing it from this
                // wrapper frees the same fd twice when the process is destroyed.
                stdout.close_base_stream = false;

                while (true) {
                    try {
                        string? line = yield stdout.read_line_utf8_async(Priority.DEFAULT, cancellable);
                        if (line == null) {
                            break;
                        }
                        remember_line(line);
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
                    var message = apktool_error_summary(e.message);
                    phase_changed(ApktoolPhase.FAILED, message);
                    finished(false, message);
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

        private void remember_line(string line) {
            var trimmed = line.strip();
            if (trimmed == "") {
                return;
            }
            output_tail.add(trimmed);
            while (output_tail.size > 40) {
                output_tail.remove_at(0);
            }
        }

        // GLib reports a non-zero exit as "Child process exited with code N"
        // and does not include the program's own stderr. Prefer Apktool's text.
        private string apktool_error_summary(string fallback) {
            string? unrecognized = null;
            string? exception_line = null;
            string? caused_line = null;
            foreach (var line in output_tail) {
                if (line.has_prefix("Unrecognized option:")) {
                    unrecognized = line;
                } else if (line.has_prefix("Exception in thread") || line.has_prefix("java.lang.")) {
                    exception_line = line;
                } else if (line.has_prefix("Caused by:")) {
                    caused_line = line;
                }
            }

            if (unrecognized != null) {
                return unrecognized;
            }
            if (exception_line != null) {
                var msg = exception_line.replace("Exception in thread \"main\" ", "");
                if (caused_line != null) {
                    return "%s (%s)".printf(msg, caused_line.replace("Caused by: ", ""));
                }
                return msg;
            }
            if (output_tail.size > 0) {
                return output_tail.get(output_tail.size - 1);
            }
            return fallback;
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
