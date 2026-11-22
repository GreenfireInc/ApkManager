using ApkManager.Core;

namespace ApkManager.Windows {
    public class RuntimeInstallDialog : Adw.Dialog {
        private const int LOGO_PX = 48;
        private const int DISTRO_ICON_PX = 24;

        private struct DistroSteps {
            public string name;
            public string icon_name;
            public string note;
            public string commands;
            // ATL.edge: built from the latest upstream source instead of installing a release.
            public bool edge;
        }

        private struct RuntimeGuide {
            public RuntimeEngine engine;
            public string page_name;
            public string title;
            public string summary;
            public string requirements;
            public DistroSteps[] distros;
            public string[] link_urls;
            public string[] link_labels;
        }

        private Adw.ToastOverlay toast_overlay;
        private Gtk.Stack stack;

        public RuntimeInstallDialog(RuntimeEngine initial) {
            title = "Install a Runtime";
            content_width = 620;
            content_height = 640;
            build_ui();
            stack.visible_child_name = guide_page_name(initial);
        }

        private void build_ui() {
            stack = new Gtk.Stack();
            stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            foreach (var guide in guides()) {
                stack.add_titled(build_page(guide), guide.page_name, guide.title);
            }

            var switcher = new Gtk.StackSwitcher();
            switcher.stack = stack;

            var header = new Adw.HeaderBar();
            header.title_widget = switcher;

            var toolbar = new Adw.ToolbarView();
            toolbar.add_top_bar(header);
            toolbar.content = stack;

            toast_overlay = new Adw.ToastOverlay();
            toast_overlay.child = toolbar;
            child = toast_overlay;
        }

        private Gtk.Widget build_page(RuntimeGuide guide) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);
            box.margin_top = 18;
            box.margin_bottom = 24;
            box.margin_start = 12;
            box.margin_end = 12;

            var heading = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 14);
            var logo = new Gtk.Image();
            logo.pixel_size = LOGO_PX;
            logo.valign = Gtk.Align.START;
            PreferencesWindow.apply_runtime_engine_icon(logo, guide.engine);
            heading.append(logo);

            var heading_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            heading_text.hexpand = true;
            var name = new Gtk.Label(guide.title);
            name.add_css_class("title-2");
            name.xalign = 0;
            heading_text.append(name);
            var summary = new Gtk.Label(guide.summary);
            summary.wrap = true;
            summary.xalign = 0;
            summary.add_css_class("dim-label");
            heading_text.append(summary);
            heading.append(heading_text);
            box.append(heading);

            var requirements_group = new Adw.PreferencesGroup();
            requirements_group.title = "Requirements";
            var requirements = new Gtk.Label(guide.requirements);
            requirements.wrap = true;
            requirements.xalign = 0;
            requirements_group.add(requirements);
            box.append(requirements_group);

            var install_group = new Adw.PreferencesGroup();
            install_group.title = "Installation";
            for (int i = 0; i < guide.distros.length; i++) {
                install_group.add(build_distro_row(guide, guide.distros[i], i == 0));
            }
            box.append(install_group);

            var links_group = new Adw.PreferencesGroup();
            links_group.title = "Links";
            for (int i = 0; i < guide.link_urls.length; i++) {
                var row = new Adw.ActionRow();
                row.title = guide.link_labels[i];
                row.subtitle = guide.link_urls[i];
                row.activatable = true;
                row.add_suffix(new Gtk.Image.from_icon_name("adw-external-link-symbolic"));
                var url = guide.link_urls[i];
                row.activated.connect(() => {
                    new Gtk.UriLauncher(url).launch.begin(get_root() as Gtk.Window, null);
                });
                links_group.add(row);
            }
            box.append(links_group);

            var clamp = new Adw.Clamp();
            clamp.maximum_size = 580;
            clamp.child = box;

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled.vexpand = true;
            scrolled.child = clamp;
            return scrolled;
        }

        private bool install_in_progress = false;

        private const string ATL_APPIMAGE_NAME =
            "Android_Translation_Layer-3e686d14-anylinux-x86_64.AppImage";
        private const string ATL_APPIMAGE_URL =
            "https://github.com/pkgforge-dev/android_translation_layer-AppImage/releases/download/3e686d14%402026-09-22_1790090775/Android_Translation_Layer-3e686d14-anylinux-x86_64.AppImage";
        // A full ART and ATL build tree plus the Arch container image, with headroom.
        private const uint64 ATL_EDGE_FREE_BYTES = 25ULL * 1024 * 1024 * 1024;
        private const string APP_MANAGER_APPIMAGE_NAME =
            "AppManager-3.8.0-anylinux-x86_64.AppImage";
        private const string APP_MANAGER_APPIMAGE_URL =
            "https://github.com/kem-a/AppManager/releases/download/v3.8.0/AppManager-3.8.0-anylinux-x86_64.AppImage";
        // 600 MB tarball in ~/Downloads plus 1.5 GB unpacked, with headroom.
        private const uint64 LEPTON_FREE_BYTES = 3ULL * 1024 * 1024 * 1024;
        private const string LEPTON_X86_STEPS =
            "# x86_64: install the community port's prebuilt release\n" +
            "curl -fL --create-dirs -o ~/Downloads/lepton-x86_64-v3.0.2-x86_64.4.tar.zst \"https://github.com/Lolig4/lepton-x86/releases/download/v3.0.2-x86_64.4/lepton-x86_64-v3.0.2-x86_64.4.tar.zst\"\n" +
            "mkdir -p ~/.local/share/Steam/compatibilitytools.d\n" +
            "tar --zstd --xattrs -xf ~/Downloads/lepton-x86_64-v3.0.2-x86_64.4.tar.zst -C ~/.local/share/Steam/compatibilitytools.d/\n" +
            LEPTON_COMPAT_STEPS +
            "~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh";
        // lepton.bin targets SteamOS/Arch: it runs `setpgid` (util-linux 2.41+),
        // and its podman options need Podman 5 and a mid-2024 pasta. Ubuntu
        // 24.04 / Mint 22 ship util-linux 2.39, Podman 4.9 and passt 2024-02.
        private const string LEPTON_COMPAT_STEPS =
            "# Older util-linux and Podman: add a setpgid stand-in and skip devpts ptmxmode on Podman 4\n" +
            "cd ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64\n" +
            "mkdir -p bin\n" +
            "cat > bin/setpgid <<'EOF'\n" +
            "#!/usr/bin/env python3\n" +
            "# Stand-in for util-linux setpgid(1), which is new in util-linux 2.41.\n" +
            "import os, signal, sys\n" +
            "args = sys.argv[1:]\n" +
            "foreground = False\n" +
            "while args and args[0].startswith(\"-\"):\n" +
            "    opt = args.pop(0)\n" +
            "    if opt in (\"-f\", \"--foreground\"):\n" +
            "        foreground = True\n" +
            "    elif opt == \"--\":\n" +
            "        break\n" +
            "    else:\n" +
            "        sys.exit(\"setpgid: unknown option \" + opt)\n" +
            "if not args:\n" +
            "    sys.exit(\"usage: setpgid [--foreground] program [argument...]\")\n" +
            "# A session leader (started with setsid) already leads its own group.\n" +
            "if os.getpgrp() != os.getpid():\n" +
            "    os.setpgid(0, 0)\n" +
            "if foreground:\n" +
            "    try:\n" +
            "        tty = os.open(\"/dev/tty\", os.O_RDWR)\n" +
            "    except OSError:\n" +
            "        tty = None\n" +
            "    if tty is not None:\n" +
            "        signal.signal(signal.SIGTTOU, signal.SIG_IGN)\n" +
            "        os.tcsetpgrp(tty, os.getpgrp())\n" +
            "        signal.signal(signal.SIGTTOU, signal.SIG_DFL)\n" +
            "        os.close(tty)\n" +
            "os.execvp(args[0], args)\n" +
            "EOF\n" +
            "chmod +x bin/setpgid\n" +
            "sed -i 's|\"mode=644,ptmxmode=666\"|\"mode=644${LEPTON_DEVPTS_PTMXMODE-,ptmxmode=666}\"|' liblepton/mounting.sh\n" +
            "sed -i 's|--userns=keep-id:uid=0,gid=0|${LEPTON_USERNS_ARG---userns=keep-id:uid=0,gid=0}|g' liblepton/liblepton.sh\n" +
            "sed -i 's|PODMAN_NETWORK_OPTIONS+=\" --no-splice\"|PODMAN_NETWORK_OPTIONS+=\"${LEPTON_PASTA_NO_SPLICE- --no-splice}\"|' liblepton/networking.sh\n" +
            "cat >> lepton.conf <<'EOF'\n" +
            "\n" +
            "# setpgid(1) is new in util-linux 2.41; use the bundled stand-in where it's missing.\n" +
            "command -v setpgid >/dev/null || export PATH=\"${DIR}/bin:${PATH}\"\n" +
            "\n" +
            "# Podman 4 rejects the devpts ptmxmode option and can't start keep-id:uid=0\n" +
            "# containers; its default rootless mapping is the same (you are root inside).\n" +
            "# Without ptmxmode only adb's interactive shell loses its terminal.\n" +
            "if [[ \"$(podman --version 2>/dev/null)\" =~ version\\ [0-4]\\. ]]; then\n" +
            "    export LEPTON_DEVPTS_PTMXMODE=\"\" LEPTON_USERNS_ARG=\"\"\n" +
            "fi\n" +
            "\n" +
            "# pasta before mid-2024 (Ubuntu 24.04's passt) doesn't know --no-splice.\n" +
            "pasta --help 2>&1 | grep -q -- --no-splice || export LEPTON_PASTA_NO_SPLICE=\"\"\n" +
            "EOF\n" +
            "cd ~\n";
        // Debian-family kernels build binderfs as the binder_linux module and
        // don't load it; Fedora builds it in. Rootless Podman can't load it.
        private const string LEPTON_BINDER_STEPS =
            "# binderfs: load the binder_linux module now and at every boot\n" +
            "grep -qw binder /proc/filesystems || sudo modprobe binder_linux\n" +
            "echo binder_linux | sudo tee /etc/modules-load.d/binder.conf\n\n";
        // Lepton draws on the WAYLAND_DISPLAY it inherits from Steam, so on an
        // X11 desktop Steam has to start pointed at a nested Weston.
        private const string LEPTON_WESTON_STEPS =
            "\n\n# X11 desktops: steam-lepton opens a Weston window for Android apps and starts Steam pointed at it\n" +
            "mkdir -p ~/.local/bin ~/.local/share/applications ~/.config\n" +
            "[ -e ~/.config/weston.ini ] || printf '[core]\\nidle-time=0\\n\\n[shell]\\nlocking=false\\n' > ~/.config/weston.ini\n" +
            "cat > ~/.local/bin/steam-lepton <<'EOF'\n" +
            "#!/bin/bash\n" +
            "set -euo pipefail\n" +
            "SOCKET=wayland-lepton\n" +
            "RUNTIME=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"\n" +
            "[[ -n \"${WAYLAND_DISPLAY:-}\" ]] && exec steam \"$@\"\n" +
            "if [[ ! -S \"${RUNTIME}/${SOCKET}\" ]]; then\n" +
            "    weston --backend=x11 --socket=\"${SOCKET}\" --width=1280 --height=800 &\n" +
            "    for _ in $(seq 50); do [[ -S \"${RUNTIME}/${SOCKET}\" ]] && break; sleep 0.1; done\n" +
            "fi\n" +
            "[[ -S \"${RUNTIME}/${SOCKET}\" ]] || { echo \"Weston did not start\" >&2; exit 1; }\n" +
            "if pgrep -x steam >/dev/null; then steam -shutdown; sleep 5; fi\n" +
            "WAYLAND_DISPLAY=\"${SOCKET}\" exec steam \"$@\"\n" +
            "EOF\n" +
            "chmod +x ~/.local/bin/steam-lepton\n" +
            "cat > ~/.local/share/applications/steam-lepton.desktop <<EOF\n" +
            "[Desktop Entry]\n" +
            "Type=Application\n" +
            "Name=Steam (Lepton)\n" +
            "Comment=Steam with a Weston window for Android games\n" +
            "Exec=$HOME/.local/bin/steam-lepton\n" +
            "Icon=steam\n" +
            "Categories=Game;\n" +
            "EOF\n" +
            "echo \"Start Steam with steam-lepton, or Steam (Lepton) in the menu, to play Android games.\"";

        private Gtk.Widget build_distro_row(RuntimeGuide guide, DistroSteps steps, bool expanded) {
            var row = new Adw.ExpanderRow();
            row.title = steps.name;
            row.subtitle = steps.note;
            row.expanded = expanded;
            var icon = new Gtk.Image();
            icon.pixel_size = DISTRO_ICON_PX;
            try {
                var bytes = GLib.resources_lookup_data(
                    "/com/github/ApkManager/icons/scalable/apps/%s.svg".printf(steps.icon_name),
                    GLib.ResourceLookupFlags.NONE
                );
                icon.paintable = Gdk.Texture.from_bytes(bytes);
            } catch (Error e) {
                icon.icon_name = steps.icon_name;
            }
            row.add_prefix(icon);

            var commands = new Gtk.Label(steps.commands);
            commands.add_css_class("monospace");
            commands.selectable = true;
            commands.wrap = true;
            commands.wrap_mode = Pango.WrapMode.WORD_CHAR;
            commands.xalign = 0;
            commands.hexpand = true;

            var copy_button = new Gtk.Button.from_icon_name("edit-copy-symbolic");
            copy_button.tooltip_text = "Copy commands";
            copy_button.add_css_class("flat");
            var text = steps.commands;
            var distro = steps.name;
            copy_button.clicked.connect(() => {
                get_clipboard().set_text(text);
                toast_overlay.add_toast(new Adw.Toast("%s commands copied".printf(distro)));
            });

            var install_button = new Gtk.Button.from_icon_name("system-software-install-symbolic");
            install_button.halign = Gtk.Align.CENTER;
            install_button.margin_top = 6;
            install_button.add_css_class("flat");
            var engine = guide.engine;
            var distro_name = steps.name;
            var command_text = steps.commands;
            var edge = steps.edge;
            if (edge) {
                install_button.tooltip_text =
                    "Build Android Translation Layer from the latest upstream source in a Podman container, then install it with AppManager";
            } else if (engine == RuntimeEngine.ANDROID_TRANSLATION_LAYER) {
                install_button.tooltip_text =
                    "Install %s dependencies, download Android Translation Layer, and install it with AppManager"
                    .printf(distro_name);
            } else {
                install_button.tooltip_text = "Run these %s install commands in a terminal".printf(distro_name);
            }
            install_button.clicked.connect(() => {
                if (install_in_progress) {
                    return;
                }
                install_in_progress = true;
                install_button.sensitive = false;
                run_install.begin(engine, distro_name, command_text, edge, (obj, res) => {
                    install_in_progress = false;
                    install_button.sensitive = true;
                    try {
                        run_install.end(res);
                    } catch (Error e) {
                        toast_overlay.add_toast(new Adw.Toast(e.message));
                    }
                });
            });

            var actions = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            actions.valign = Gtk.Align.START;
            actions.append(copy_button);
            actions.append(install_button);

            var block = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            block.margin_top = 10;
            block.margin_bottom = 10;
            block.margin_start = 12;
            block.margin_end = 6;
            block.append(commands);
            block.append(actions);
            row.add_row(block);
            return row;
        }

        // Android Translation Layer: terminal for that row's package line, then
        // download the AppImage into ~/Downloads and install it with AppManager.
        // Other runtimes: open a terminal running the commands shown on the row.
        private async void run_install(RuntimeEngine engine, string distro, string commands, bool edge) throws Error {
            if (edge) {
                yield install_atl_edge();
                return;
            }
            if (engine == RuntimeEngine.ANDROID_TRANSLATION_LAYER) {
                yield install_android_translation_layer(distro, commands);
                return;
            }
            if (engine == RuntimeEngine.LEPTON) {
                yield require_free_space(LEPTON_FREE_BYTES);
            }
            toast("Opening a terminal for the %s install commands".printf(distro));
            yield open_terminal_script(commands);
        }

        private async void install_android_translation_layer(string distro, string commands) throws Error {
            var dependency = commands.split("\n", 2)[0].strip();
            toast("Opening a terminal to install %s dependencies".printf(distro));
            yield open_terminal_script(dependency);
            if (Environment.find_program_in_path("curl") == null) {
                throw new IOError.FAILED("curl is not available. Install it in the terminal, then try again.");
            }

            var downloads = Path.build_filename(Environment.get_home_dir(), "Downloads");
            DirUtils.create_with_parents(downloads, 0755);
            var appimage = Path.build_filename(downloads, ATL_APPIMAGE_NAME);
            toast("Downloading Android Translation Layer to ~/Downloads");
            yield download_file(ATL_APPIMAGE_URL, appimage);
            FileUtils.chmod(appimage, 0755);

            toast("Installing Android Translation Layer with AppManager");
            var app_manager = yield ensure_app_manager();
            var message = last_status_line(yield run_captured({ app_manager, "install", appimage }));
            toast(message != "" ? message : "Android Translation Layer installed");
        }

        // docs/strategies/20261121.strategy.apkmanager.android-translation-layer.build-appimage-from-source.claude-opus-5.5.md,
        // option B: packaging/atl-edge/build.sh in a terminal, then the AppImage it
        // leaves in ~/Downloads goes to AppManager, replacing the current ATL.
        private async void install_atl_edge() throws Error {
            var recipe = AppPaths.atl_edge_dir();
            if (recipe == null) {
                throw new IOError.NOT_FOUND("The ATL.edge build recipe is missing from this ApkManager installation.");
            }
            if (Environment.find_program_in_path("podman") == null) {
                throw new IOError.NOT_FOUND(
                    "ATL.edge builds in Podman, which is not installed. Debian, Ubuntu, Linux Mint: sudo apt install podman. Fedora: sudo dnf install podman."
                );
            }
            yield require_free_space(ATL_EDGE_FREE_BYTES);
            toast("Building ATL.edge in a terminal. The first build can take an hour or more");
            yield open_terminal_script("sh " + Shell.quote(Path.build_filename(recipe, "build.sh")));

            var cache = Path.build_filename(Environment.get_user_cache_dir(), DATA_DIRNAME, "atl-edge");
            string appimage;
            try {
                FileUtils.get_contents(Path.build_filename(cache, "last-build"), out appimage);
            } catch (FileError e) {
                throw new IOError.FAILED("The ATL.edge build did not report an AppImage.");
            }
            appimage = appimage.strip();
            if (!FileUtils.test(appimage, FileTest.IS_REGULAR)) {
                throw new IOError.FAILED("The ATL.edge AppImage is missing: %s".printf(appimage));
            }

            toast("Installing ATL.edge with AppManager");
            var app_manager = yield ensure_app_manager();
            var message = last_status_line(yield run_captured({ app_manager, "install", appimage }));
            try {
                File.new_for_path(Path.build_filename(cache, "atl-build.json")).copy(
                    File.new_for_path(AppPaths.atl_edge_manifest), FileCopyFlags.OVERWRITE
                );
            } catch (Error e) {
                warning("Could not record the ATL.edge build: %s", e.message);
            }
            toast(message != "" ? message : "ATL.edge installed");
        }

        private async string ensure_app_manager() throws Error {
            var installed = Path.build_filename(Environment.get_home_dir(), "Applications", "AppManager");
            if (FileUtils.test(installed, FileTest.IS_EXECUTABLE)) {
                return installed;
            }
            var on_path = Environment.find_program_in_path("app-manager");
            if (on_path != null) {
                return on_path;
            }

            var downloads = Path.build_filename(Environment.get_home_dir(), "Downloads");
            DirUtils.create_with_parents(downloads, 0755);
            var bootstrap = Path.build_filename(downloads, APP_MANAGER_APPIMAGE_NAME);
            toast("Downloading AppManager 3.8.0");
            yield download_file(APP_MANAGER_APPIMAGE_URL, bootstrap);
            FileUtils.chmod(bootstrap, 0755);
            toast("Installing AppManager");
            yield run_captured({ bootstrap, "install", bootstrap });
            if (!FileUtils.test(installed, FileTest.IS_EXECUTABLE)) {
                throw new IOError.FAILED("AppManager did not appear at ~/Applications/AppManager");
            }
            return installed;
        }

        private async void require_free_space(uint64 needed) throws Error {
            var home = File.new_for_path(Environment.get_home_dir());
            var info = yield home.query_filesystem_info_async(FileAttribute.FILESYSTEM_FREE, Priority.DEFAULT, null);
            var free = info.get_attribute_uint64(FileAttribute.FILESYSTEM_FREE);
            if (free < needed) {
                throw new IOError.NO_SPACE(
                    "Not enough disk space: %s free in your home folder, %s needed."
                    .printf(format_size(free), format_size(needed))
                );
            }
        }

        private async void download_file(string url, string dest) throws Error {
            var message = yield run_captured({
                "curl", "-fL", "--retry", "3", "--retry-delay", "2", "-o", dest, url
            });
            if (message != "") {
                debug("curl: %s", message);
            }
        }

        private async void open_terminal_script(string script) throws Error {
            if (Environment.find_program_in_path("gnome-terminal") == null) {
                throw new IOError.NOT_FOUND("GNOME Terminal is not installed, so these commands cannot be run from here.");
            }
            // The status file is how the app learns dnf/apt's result. gnome-terminal
            // --wait returns when the window closes, not the command's exit code.
            // The subshell stops at the first failing line, so later steps never
            // run on a missing build; the terminal otherwise inherits our cwd.
            var status_path = Path.build_filename(Environment.get_tmp_dir(), "apk-manager-runtime-install.status");
            FileUtils.remove(status_path);
            var held = "cd ~\n(\nset -eo pipefail\n" + script +
                "\n)\nstatus=$?\necho \"$status\" > " + status_path +
                "\necho\nif [ \"$status\" -eq 0 ]; then echo Done.; else echo \"The command failed ($status).\"; fi\n" +
                "echo \"Press Enter to close.\"\nread\n";
            var proc = new Subprocess.newv(
                { "gnome-terminal", "--wait", "--", "bash", "-c", held },
                SubprocessFlags.NONE
            );
            yield proc.wait_async();
            string status_text;
            try {
                FileUtils.get_contents(status_path, out status_text);
            } catch (FileError e) {
                throw new IOError.FAILED("The terminal closed before the command finished.");
            }
            if (status_text.strip() != "0") {
                throw new IOError.FAILED("The command failed (%s).".printf(status_text.strip()));
            }
        }

        private async string run_captured(string[] argv) throws Error {
            var proc = new Subprocess.newv(
                argv,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );
            string? stdout_text = null;
            string? stderr_text = null;
            yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);
            if (!proc.get_successful()) {
                var detail = (stderr_text ?? stdout_text ?? "command failed").strip();
                if (detail.length > 180) {
                    detail = detail.substring(0, 180);
                }
                throw new IOError.FAILED(detail != "" ? detail : "command failed");
            }
            return (stdout_text ?? "").strip();
        }

        private static string last_status_line(string text) {
            string last = "";
            foreach (var line in text.split("\n")) {
                var piece = line.strip();
                var cr = piece.last_index_of_char('\r');
                if (cr >= 0) {
                    piece = piece.substring(cr + 1).strip();
                }
                if (piece != "") {
                    last = piece;
                }
            }
            return last;
        }

        private void toast(string message) {
            toast_overlay.add_toast(new Adw.Toast(message));
        }

        private static string atl_edge_commands() {
            var recipe = AppPaths.atl_edge_dir() ?? "/usr/share/apk-manager/atl-edge";
            return "# ATL.edge: Android Translation Layer built from the newest upstream commit.\n" +
                "# Edge builds get new features and app fixes weeks before the community AppImage,\n" +
                "# and can occasionally break. Re-run to update; check with check-update.sh.\n" +
                "# Builds in a rootless Podman container (Arch Linux), needs about 25 GB free,\n" +
                "# and the first build can take an hour or more.\n" +
                "sh " + Shell.quote(Path.build_filename(recipe, "build.sh")) + "\n\n" +
                "# Then ApkManager installs the AppImage from ~/Downloads with AppManager,\n" +
                "# replacing the current Android Translation Layer.\n" +
                "# Is there a newer edge build?\n" +
                "sh " + Shell.quote(Path.build_filename(recipe, "check-update.sh"));
        }

        private static string guide_page_name(RuntimeEngine engine) {
            switch (engine) {
            case RuntimeEngine.ANDROID_TRANSLATION_LAYER:
                return "atl";
            case RuntimeEngine.LEPTON:
                return "lepton";
            default:
                return "waydroid";
            }
        }

        // Condensed from docs/research/20261115.research.apkmanager.android-runtime.*.md.
        private static RuntimeGuide[] guides() {
            return {
                RuntimeGuide() {
                    engine = RuntimeEngine.WAYDROID,
                    page_name = guide_page_name(RuntimeEngine.WAYDROID),
                    title = "Waydroid",
                    summary = "Boots a full Android system (LineageOS) in an LXC container on your kernel, so apps run at native speed.",
                    requirements = "A Wayland session (under X11, run Weston or Cage first), a kernel with binder (check with: grep binder /proc/filesystems), Mesa graphics (Intel or AMD), and about 4 GB of free disk. The first init downloads the Android images.",
                    distros = {
                        DistroSteps() {
                            name = "Debian",
                            icon_name = "apk-manager-distro-debian",
                            note = "Official in forky and sid, and in trixie-backports",
                            commands = "# Debian 13: enable backports once\necho \"deb http://deb.debian.org/debian trixie-backports main\" | sudo tee /etc/apt/sources.list.d/backports.list\nsudo apt update || echo \"apt update reported errors (often an unrelated repository); continuing\"\nsudo apt install -t trixie-backports waydroid\n\n# Debian 12 instead: curl -s https://repo.waydro.id | sudo bash && sudo apt install waydroid\n\nsudo waydroid init\nsudo systemctl enable --now waydroid-container\nwaydroid session start"
                        },
                        DistroSteps() {
                            name = "Ubuntu / Linux Mint",
                            icon_name = "apk-manager-distro-ubuntu",
                            note = "Upstream repo for LTS releases; Mint is detected automatically",
                            commands = "sudo apt install curl ca-certificates\ncurl -s https://repo.waydro.id | sudo bash\nsudo apt install waydroid\nsudo waydroid init\nsudo systemctl enable --now waydroid-container\n\n# Linux Mint (X11): sudo apt install weston, start weston, then run inside it:\nwaydroid session start"
                        },
                        DistroSteps() {
                            name = "Fedora",
                            icon_name = "apk-manager-distro-fedora",
                            note = "Official Fedora repositories",
                            commands = "sudo dnf install waydroid\nsudo waydroid init\nsudo systemctl enable --now waydroid-container\nwaydroid session start"
                        }
                    },
                    link_urls = { "https://waydro.id", "https://docs.waydro.id", "https://github.com/waydroid/waydroid" },
                    link_labels = { "Website", "Documentation", "Source code" }
                },
                RuntimeGuide() {
                    engine = RuntimeEngine.ANDROID_TRANSLATION_LAYER,
                    page_name = guide_page_name(RuntimeEngine.ANDROID_TRANSLATION_LAYER),
                    title = "Android Translation Layer",
                    summary = "Runs an APK directly as a Linux program, the way Wine runs Windows programs. No Android system or container. Experimental: many apps still crash.",
                    requirements = "A GTK 4 desktop (on X11, launch with GDK_DEBUG=gl-egl), Mesa graphics with EGL, and FUSE 2 for the AppImage. Not packaged by Debian, Ubuntu, or Fedora: use the community AppImage below, or ATL.edge, which builds the newest upstream source on this computer.",
                    distros = {
                        DistroSteps() {
                            name = "Debian",
                            icon_name = "apk-manager-distro-debian",
                            note = "AppImage (use libfuse2t64 on Debian 13)",
                            commands = "sudo apt install curl libfuse2\ncurl -LO \"https://github.com/pkgforge-dev/android_translation_layer-AppImage/releases/download/3e686d14%402026-09-22_1790090775/Android_Translation_Layer-3e686d14-anylinux-x86_64.AppImage\"\nchmod +x Android_Translation_Layer-*-x86_64.AppImage\n./Android_Translation_Layer-*-x86_64.AppImage /path/to/app.apk"
                        },
                        DistroSteps() {
                            name = "Ubuntu / Linux Mint",
                            icon_name = "apk-manager-distro-ubuntu",
                            note = "AppImage (use libfuse2 on 22.04 / Mint 21)",
                            commands = "sudo apt install curl libfuse2t64\ncurl -LO \"https://github.com/pkgforge-dev/android_translation_layer-AppImage/releases/download/3e686d14%402026-09-22_1790090775/Android_Translation_Layer-3e686d14-anylinux-x86_64.AppImage\"\nchmod +x Android_Translation_Layer-*-x86_64.AppImage\n./Android_Translation_Layer-*-x86_64.AppImage /path/to/app.apk"
                        },
                        DistroSteps() {
                            name = "Fedora",
                            icon_name = "apk-manager-distro-fedora",
                            note = "AppImage",
                            commands = "sudo dnf install curl fuse-libs\ncurl -LO \"https://github.com/pkgforge-dev/android_translation_layer-AppImage/releases/download/3e686d14%402026-09-22_1790090775/Android_Translation_Layer-3e686d14-anylinux-x86_64.AppImage\"\nchmod +x Android_Translation_Layer-*-x86_64.AppImage\n./Android_Translation_Layer-*-x86_64.AppImage /path/to/app.apk"
                        },
                        DistroSteps() {
                            name = "ATL.edge",
                            icon_name = "software-update-available-symbolic",
                            note = "Edge builds: the latest upstream source, with the newest features and fixes first. Any distro with Podman",
                            commands = atl_edge_commands(),
                            edge = true
                        }
                    },
                    link_urls = {
                        "https://gitlab.com/android_translation_layer/android_translation_layer",
                        "https://gitlab.com/android_translation_layer/android_translation_layer/-/blob/master/doc/Build.md",
                        "https://github.com/pkgforge-dev/android_translation_layer-AppImage/releases"
                    },
                    link_labels = { "Source code", "Build from source", "AppImage releases" }
                },
                RuntimeGuide() {
                    engine = RuntimeEngine.LEPTON,
                    page_name = guide_page_name(RuntimeEngine.LEPTON),
                    title = "Lepton",
                    summary = "Valve's Android compatibility tool for Steam: a trimmed Waydroid-based Android 11 in a rootless Podman container, built for games.",
                    requirements = "Steam, Podman, a kernel with binder, and Wayland. The official Lepton from Steam (Library → Tools → Lepton) only runs on ARM64. On x86_64 PCs, use the community lepton-x86 port, which currently supports AMD GPUs only. Its prebuilt release needs about 3 GB of free disk (building it yourself needs more than 100 GB). On Debian, Ubuntu and Linux Mint the steps also load the binder kernel module and, for X11 desktops, add a steam-lepton launcher that opens Android apps in a Weston window.",
                    distros = {
                        DistroSteps() {
                            name = "Debian",
                            icon_name = "apk-manager-distro-debian",
                            note = "Steam from contrib, with 32-bit multiarch",
                            commands = "sudo dpkg --add-architecture i386\n# enable \"contrib\" in /etc/apt/sources.list.d/debian.sources, then:\nsudo apt update || echo \"apt update reported errors (often an unrelated repository); continuing\"\nsudo apt install steam-installer podman catatonit inotify-tools adb attr curl zstd weston\n\n" + LEPTON_BINDER_STEPS + LEPTON_X86_STEPS + LEPTON_WESTON_STEPS
                        },
                        DistroSteps() {
                            name = "Ubuntu / Linux Mint",
                            icon_name = "apk-manager-distro-ubuntu",
                            note = "Steam from multiverse (enabled by default on Mint)",
                            commands = "# Ubuntu: enable multiverse (already on in Linux Mint)\ngrep -rqs multiverse /etc/apt/sources.list /etc/apt/sources.list.d/ || sudo add-apt-repository -y multiverse\nsudo dpkg --add-architecture i386\nsudo apt update || echo \"apt update reported errors (often an unrelated repository); continuing\"\nsudo apt install steam-installer podman catatonit inotify-tools adb attr curl zstd weston\n\n" + LEPTON_BINDER_STEPS + LEPTON_X86_STEPS + LEPTON_WESTON_STEPS
                        },
                        DistroSteps() {
                            name = "Fedora",
                            icon_name = "apk-manager-distro-fedora",
                            note = "Steam from RPM Fusion nonfree",
                            commands = "sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm\nsudo dnf install steam podman catatonit inotify-tools android-tools attr policycoreutils curl zstd\n\n" + LEPTON_X86_STEPS
                        }
                    },
                    link_urls = {
                        "https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility",
                        "https://gitlab.steamos.cloud/frame-public/lepton",
                        "https://github.com/Lolig4/lepton-x86"
                    },
                    link_labels = { "Steamworks documentation", "Source code (Valve)", "x86_64 community port" }
                }
            };
        }
    }
}
