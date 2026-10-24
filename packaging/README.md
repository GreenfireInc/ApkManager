# ApkManager packaging

Build scripts and metadata for **deb**, **rpm**, **Flatpak**, **Snap**, and **AppImage**.

Version is taken from `meson.build` (currently **0.1.0**).

## GitHub Actions

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | PR into `main`, push to `CS.*`, called by release | Meson compile + headless `--version` smoke test |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | Push/merge to `main`, tag `v*`, or **Run workflow** | Run CI, then build deb, rpm, Flatpak, Snap, AppImage; publish a GitHub Release on tags |

**Cut a release:**

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow uploads all five package types to the GitHub Release page.  
Manual runs (`workflow_dispatch`) build artifacts without creating a release unless the ref is a `v*` tag.

---

## Quick start

From the repository root:

```bash
chmod +x scripts/build-packages.sh packaging/make-dist.sh build/build-apimage
./scripts/build-packages.sh deb
./scripts/build-packages.sh rpm
./scripts/build-packages.sh flatpak
./scripts/build-packages.sh snap
./scripts/build-packages.sh appimage
./scripts/build-packages.sh all
```

Artifacts are written under `dist/` unless noted otherwise.

---

## Debian (.deb)

**Files:** `build/debian/` (symlinked to `debian/` at build time)  
**Meson build tree:** `build/meson-debian/` (created during `.deb` build)

**Host tools:**

```bash
sudo apt install build-essential debhelper meson ninja-build valac pkg-config \
  libgtk-4-dev libadwaita-1-dev libgtksourceview-5-dev libglib2.0-dev \
  libjson-glib-dev libgee-0.8-dev libarchive-dev libcairo2-dev curl \
  desktop-file-utils libglib2.0-bin devscripts
```

**Build:**

```bash
./scripts/build-packages.sh deb
# Creates a temporary debian -> build/debian symlink, then runs dpkg-buildpackage
```

**Install:**

```bash
sudo apt install ./dist/apk-manager_0.1.0-1_amd64.deb
```

**Runtime:** `default-jre-headless` or OpenJDK 17+ for Apktool decode.

---

## RPM (Fedora / RHEL-family)

**Files:** `packaging/rpm/apk-manager.spec`

**Host tools:**

```bash
sudo dnf install rpm-build meson ninja-build vala gtk4-devel libadwaita-devel \
  gtksourceview5-devel glib2-devel json-glib-devel libgee-devel libarchive-devel \
  cairo-devel curl desktop-file-utils
```

**Build:**

```bash
./scripts/build-packages.sh rpm
```

**Install:**

```bash
sudo dnf install dist/apk-manager-0.1.0-1.*.rpm
```

---

## Flatpak

**Files:** `packaging/flatpak/com.github.ApkManager.yml`

Bundles a minimal **OpenJDK 17** JRE inside the sandbox (`/app/jre`).

**Host tools:**

```bash
sudo apt install flatpak flatpak-builder   # Debian/Ubuntu
# or: sudo dnf install flatpak flatpak-builder
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

**Build:**

```bash
./scripts/build-packages.sh flatpak
```

**Install locally:**

```bash
flatpak install --user dist/com.github.ApkManager-0.1.0.flatpak
flatpak run com.github.ApkManager
```

---

## Snap

**Files:** `build/snap/snapcraft.yaml`

Uses **core22** + **gnome** extension and stages **openjdk-17-jre-headless**.

**Host tools:**

```bash
sudo snap install snapcraft --classic
```

**Build (from repo root):**

```bash
./scripts/build-packages.sh snap
```

**Install locally:**

```bash
sudo snap install --dangerous dist/apk-manager_0.1.0_amd64.snap
apk-manager
```

---

## AppImage

**Script:** `packaging/appimage/build-appimage.sh`  
**Output:** `dist/ApkManager-<version>-<arch>.AppImage` (staging under `build/`)

Bundles the GTK application and libraries via **linuxdeploy** + **linuxdeploy-plugin-gtk**.  
**Java is not bundled** — Apktool decode needs Java 17+ on the host (same as a bare `meson install`).

**Host tools:**

```bash
# Meson toolchain (see README.md) plus:
# - linuxdeploy + linuxdeploy-plugin-gtk (https://github.com/linuxdeploy)
# - appimagetool (https://github.com/AppImage/AppImageKit)
```

**Build:**

```bash
export PATH="$HOME/.local/bin:$PATH"   # linuxdeploy tools, if needed
./packaging/appimage/build-appimage.sh
# → build/build.appImage
```

Or via the package helper:

```bash
./scripts/build-packages.sh appimage
```

**Run:**

```bash
chmod +x dist/ApkManager-0.1.0-x86_64.AppImage
./dist/ApkManager-0.1.0-x86_64.AppImage
```

---

## What every package ships

| Component | Location after install |
|-----------|-------------------------|
| Binary | `apk-manager` |
| Apktool JAR | `lib/apk-manager/apktool.jar` (or `lib64/…` on Fedora) |
| Desktop entry | `share/applications/com.github.ApkManager.desktop` |
| AppStream | `share/metainfo/com.github.ApkManager.metainfo.xml` |
| GSettings schema | `share/glib-2.0/schemas/com.github.ApkManager.gschema.xml` |
| MIME + thumbnailer | For Nemo/Cinnamon APK icons |
| App icon | `share/icons/hicolor/scalable/apps/com.github.ApkManager.svg` |

---

## Notes

- **Debian `3.0 (native)`** — this tree is the upstream source; no separate orig tarball.
- **Snap grade** is `devel` until published on the Snap Store.
- **Flatpak** manifest uses `type: dir` for local builds; point `sources` at a git URL for CI.
- **Publishing** to Flathub, Snap Store, or a PPA/COPR is out of scope here; these recipes are for local and CI builds.

See also: [docs/requirements/20261007.requirements.apkmanager.build.environment.debian.fedora.composer-2.5-fast.md](../docs/requirements/20261007.requirements.apkmanager.build.environment.debian.fedora.composer-2.5-fast.md)
