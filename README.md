# ApkManager

Native GTK 4 / Libadwaita desktop application for inspecting Android APK files
on Debian and Fedora.

ApkManager wraps a pinned [Apktool](https://apktool.org/) release and presents
decoded manifests, resources, and archive contents in a read-only GUI modeled
after AppManager's desktop patterns.

## Requirements

- Vala, Meson, Ninja
- GTK 4, Libadwaita (≥ 1.4), GtkSourceView 5
- libarchive, json-glib, libgee
- Java runtime 17+ (required for Apktool decode; raw archive listing works
  without Java)

### Debian / Ubuntu

```bash
sudo apt install valac meson ninja-build pkg-config \
  libgtk-4-dev libadwaita-1-dev libgtksourceview-5-dev \
  libglib2.0-dev libjson-glib-dev libgee-0.8-dev libarchive-dev \
  desktop-file-utils default-jre-headless
```
### Fedora

```bash
sudo dnf install vala meson ninja-build gtk4-devel libadwaita-devel \
  gtksourceview5-devel glib2-devel json-glib-devel libgee-devel \
  libarchive-devel desktop-file-utils java-latest-openjdk-headless
```
## Build

First-time setup:

```bash
cd ~/Workspace/Applications/apkManager
chmod +x scripts/fetch-apktool.sh
meson setup build --prefix=$HOME/.local
meson compile -C build
meson install -C build
update-desktop-database ~/.local/share/applications
```
Rebuild and run:

```bash
cd ~/Workspace/Applications/apkManager
meson compile -C build && meson install -C build
export PATH="$HOME/.local/bin:$PATH"
apk-manager
```
## Usage

```bash
export PATH="$HOME/.local/bin:$PATH"
apk-manager                    # Launch GUI
apk-manager /path/to/app.apk   # Open an APK
apk-manager --version
```

Use **Get APKs** in the sidebar to search [F-Droid](https://f-droid.org/), [Aptoide](https://en.aptoide.com/), [IzzyOnDroid](https://izzyondroid.org/), [OpenAPK](https://www.openapk.net/), and [Uptodown](https://en.uptodown.com/) and download APKs. F-Droid, Aptoide, IzzyOnDroid, and OpenAPK downloads happen inside the app; Uptodown opens its download page in your browser (their site requires browser verification).
## Project layout

```text
src/
  application.vala          # GApplication entry, file-open routing
  core/                     # Apktool runner, archive reader, sessions
  windows/                  # Main window and open/drop window
data/                       # Desktop file, AppStream, GSettings
scripts/fetch-apktool.sh    # Pin and download apktool.jar at build time
docs/methodologies/         # Architecture and implementation plans
docs/progress/              # Build progress reports
```
## Distribution packages

Build **deb**, **rpm**, **Flatpak**, **Snap**, and **AppImage** from the repo:

```bash
chmod +x scripts/build-packages.sh
./scripts/build-packages.sh deb        # or: rpm | flatpak | snap | appimage | all
```

See [packaging/README.md](packaging/README.md) for host dependencies and install commands.

**CI:** push/PR runs compile checks; push a `v*` tag (e.g. `v0.1.0`) to build all packages and publish a GitHub Release.

## Status

Initial foundation (Phase 0–1): Meson scaffold, raw archive browser, Apktool
subprocess integration, session registry, desktop metadata.

See `docs/methodologies/` for the full implementation roadmap.

