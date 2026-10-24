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
meson setup build/meson --prefix=$HOME/.local
meson compile -C build/meson
meson install -C build/meson
update-desktop-database ~/.local/share/applications
```
Rebuild and run:

```bash
cd ~/Workspace/Applications/apkManager
meson compile -C build/meson && meson install -C build/meson
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

**CI:** pull requests into `main` run compile checks; merging into `main` runs CI and then builds all packages; push a `v*` tag (e.g. `v0.2.0`) to also publish a GitHub Release.

## Status

Version **0.2.0**. Working today:

- Open or drop an APK, browse raw archive entries, run **Quick Manifest** or
  **Full Decode** (Apktool 2.9.3), and view package metadata and the app icon
  (including adaptive and vector-drawable icons) on the Properties tab
- **Get APKs** search and download from F-Droid, IzzyOnDroid, Aptoide, OpenAPK,
  APKMirror, and Uptodown, with install to a managed folder
- Drag-and-drop install, SHA-256 verification, and APK thumbnails in
  Nemo/Nautilus
- Preferences, keyboard shortcuts, About, and a Donations dialog
- deb, rpm, Flatpak, Snap, and AppImage packages built by GitHub Actions

Not yet done: browsing the decoded file tree after Full Decode, opening decoded
files in a viewer or editor, and an Apktool framework install UI.

See `docs/progress/` for detailed progress reports and `docs/methodologies/`
for the full implementation roadmap.

