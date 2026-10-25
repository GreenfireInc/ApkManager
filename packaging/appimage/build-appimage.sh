#!/usr/bin/env bash
# Build a portable AppImage for ApkManager (staging in build/, output in dist/).
#
# Requires: meson, ninja, valac, linuxdeploy, linuxdeploy-plugin-gtk.sh, appimagetool
# Java 17+ must be available on the host at runtime (not bundled in this script).
set -euo pipefail

# Run linuxdeploy/appimagetool without FUSE (CI runners and containers lack libfuse2).
export APPIMAGE_EXTRACT_AND_RUN=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(grep "version:" "$ROOT/meson.build" | head -1 | sed "s/.*'\\([^']*\\)'.*/\\1/")"
DIST="$ROOT/dist"
BUILD_DIR="$ROOT/build"
MESON_BUILD="$BUILD_DIR/meson-appimage"
APPDIR="$BUILD_DIR/AppDir"
ARCH="$(uname -m)"
OUTPUT="$DIST/ApkManager-${VERSION}-${ARCH}.AppImage"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

need meson
need ninja
need valac
need linuxdeploy
need appimagetool
if ! command -v linuxdeploy-plugin-gtk.sh >/dev/null 2>&1; then
  echo "Missing linuxdeploy-plugin-gtk.sh (see .github/scripts/install-appimage-tools.sh)" >&2
  exit 1
fi
export LINUXDEPLOY="$(command -v linuxdeploy)"

rm -rf "$MESON_BUILD" "$APPDIR" "$OUTPUT"
mkdir -p "$BUILD_DIR" "$DIST"

echo "==> Configure and install into AppDir"
meson setup "$MESON_BUILD" --prefix=/usr
meson compile -C "$MESON_BUILD"
DESTDIR="$APPDIR" meson install -C "$MESON_BUILD"

DESKTOP="$APPDIR/usr/share/applications/com.github.ApkManager.desktop"
ICON="$APPDIR/usr/share/icons/hicolor/scalable/apps/com.github.ApkManager.svg"

if [[ ! -f "$DESKTOP" ]]; then
  echo "Desktop file not found at $DESKTOP" >&2
  exit 1
fi

# linuxdeploy expects a bare command name in Exec=, not an absolute /usr/bin path.
sed -i 's|^Exec=/usr/bin/apk-manager|Exec=apk-manager|; s|^TryExec=/usr/bin/apk-manager|TryExec=apk-manager|' \
  "$DESKTOP"

echo "==> Bundle GTK and dependencies with linuxdeploy"
cd "$BUILD_DIR"
# appimagetool writes into $OWD when set (e.g. a terminal inside another AppImage
# such as Cursor), so clear it and pass an explicit output path.
unset OWD
linuxdeploy \
  --appdir="$APPDIR" \
  --desktop-file="$DESKTOP" \
  --icon-file="$ICON" \
  --executable="$APPDIR/usr/bin/apk-manager" \
  --plugin gtk

# linuxdeploy-plugin-gtk's AppRun hook forces GTK_THEME=Adwaita:<variant> and
# GDK_BACKEND=x11. GTK_THEME makes libadwaita apps render with GTK's built-in
# theme instead of the libadwaita stylesheet (plain GTK header bar and window
# controls), and the X11 override bypasses native Wayland. Drop both.
GTK_HOOK="$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"
if [[ ! -f "$GTK_HOOK" ]]; then
  echo "Expected GTK AppRun hook not found at $GTK_HOOK" >&2
  exit 1
fi
sed -i '/^export GTK_THEME=/d; /^export GDK_BACKEND=/d' "$GTK_HOOK"
if grep -qE '^export (GTK_THEME|GDK_BACKEND)=' "$GTK_HOOK"; then
  echo "Failed to remove GTK_THEME/GDK_BACKEND from $GTK_HOOK" >&2
  exit 1
fi

echo "==> Pack AppImage"
# Second pass without --plugin gtk, so the edited hook is kept as-is.
LDAI_OUTPUT="$OUTPUT" linuxdeploy --appdir="$APPDIR" --output appimage
if [[ ! -f "$OUTPUT" ]]; then
  echo "linuxdeploy did not produce $OUTPUT" >&2
  exit 1
fi

chmod +x "$OUTPUT"
echo "==> Built $OUTPUT"
echo "Note: Apktool decode requires Java 17+ installed on the host system."
