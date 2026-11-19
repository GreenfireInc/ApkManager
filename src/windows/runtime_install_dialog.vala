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
                install_group.add(build_distro_row(guide.distros[i], i == 0));
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

        private Gtk.Widget build_distro_row(DistroSteps steps, bool expanded) {
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
            copy_button.valign = Gtk.Align.START;
            copy_button.add_css_class("flat");
            var text = steps.commands;
            var distro = steps.name;
            copy_button.clicked.connect(() => {
                get_clipboard().set_text(text);
                toast_overlay.add_toast(new Adw.Toast("%s commands copied".printf(distro)));
            });

            var block = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            block.margin_top = 10;
            block.margin_bottom = 10;
            block.margin_start = 12;
            block.margin_end = 6;
            block.append(commands);
            block.append(copy_button);
            row.add_row(block);
            return row;
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
                            commands = "# Debian 13: enable backports once\necho \"deb http://deb.debian.org/debian trixie-backports main\" | sudo tee /etc/apt/sources.list.d/backports.list\nsudo apt update\nsudo apt install -t trixie-backports waydroid\n\n# Debian 12 instead: curl -s https://repo.waydro.id | sudo bash && sudo apt install waydroid\n\nsudo waydroid init\nsudo systemctl enable --now waydroid-container\nwaydroid session start"
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
                    requirements = "A GTK 4 desktop (on X11, launch with GDK_DEBUG=gl-egl), Mesa graphics with EGL, and FUSE 2 for the AppImage. Not packaged by Debian, Ubuntu, or Fedora: use the community AppImage below, or build from source.",
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
                    requirements = "Steam, Podman, a kernel with binder, and Wayland. The official Lepton from Steam (Library → Tools → Lepton) only runs on ARM64. On x86_64 PCs, use the community lepton-x86 port, which currently supports AMD GPUs only and needs more than 100 GB of disk to build.",
                    distros = {
                        DistroSteps() {
                            name = "Debian",
                            icon_name = "apk-manager-distro-debian",
                            note = "Steam from contrib, with 32-bit multiarch",
                            commands = "sudo dpkg --add-architecture i386\n# enable \"contrib\" in /etc/apt/sources.list.d/debian.sources, then:\nsudo apt update\nsudo apt install steam-installer podman catatonit inotify-tools adb attr\n\n# x86_64: build and install the community port\ngit clone https://github.com/Lolig4/lepton-x86.git && cd lepton-x86\n.x86_scripts/install-dependencies.sh\n.x86_scripts/build-all.sh\ntar --zstd --xattrs -xf lepton-x86_64-*.tar.zst -C ~/.local/share/Steam/compatibilitytools.d/\nsudo ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh"
                        },
                        DistroSteps() {
                            name = "Ubuntu / Linux Mint",
                            icon_name = "apk-manager-distro-ubuntu",
                            note = "Steam from multiverse (enabled by default on Mint)",
                            commands = "sudo add-apt-repository multiverse\nsudo dpkg --add-architecture i386\nsudo apt update\nsudo apt install steam-installer podman catatonit inotify-tools adb attr\n\n# x86_64: build and install the community port\ngit clone https://github.com/Lolig4/lepton-x86.git && cd lepton-x86\n.x86_scripts/install-dependencies.sh\n.x86_scripts/build-all.sh\ntar --zstd --xattrs -xf lepton-x86_64-*.tar.zst -C ~/.local/share/Steam/compatibilitytools.d/\nsudo ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh"
                        },
                        DistroSteps() {
                            name = "Fedora",
                            icon_name = "apk-manager-distro-fedora",
                            note = "Steam from RPM Fusion nonfree",
                            commands = "sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm\nsudo dnf install steam podman catatonit inotify-tools android-tools attr policycoreutils\n\n# x86_64: build and install the community port\ngit clone https://github.com/Lolig4/lepton-x86.git && cd lepton-x86\n.x86_scripts/install-dependencies.sh\n.x86_scripts/build-all.sh\ntar --zstd --xattrs -xf lepton-x86_64-*.tar.zst -C ~/.local/share/Steam/compatibilitytools.d/\nsudo ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh"
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
