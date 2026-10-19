#!/usr/bin/env bash
# Install linuxdeploy, the GTK plugin script, and appimagetool into /usr/local/bin.
set -euo pipefail

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    LINUXDEPLOY="linuxdeploy-x86_64.AppImage"
    APPIMAGETOOL="appimagetool-x86_64.AppImage"
    ;;
  aarch64)
    LINUXDEPLOY="linuxdeploy-aarch64.AppImage"
    APPIMAGETOOL="appimagetool-aarch64.AppImage"
    ;;
  *)
    echo "Unsupported architecture for AppImage tools: $ARCH" >&2
    exit 1
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/${LINUXDEPLOY}" \
  -o "$tmpdir/linuxdeploy"
curl -fsSL "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" \
  -o "$tmpdir/linuxdeploy-plugin-gtk.sh"
curl -fsSL "https://github.com/AppImage/AppImageKit/releases/download/continuous/${APPIMAGETOOL}" \
  -o "$tmpdir/appimagetool"

BINDIR="${APPIMAGE_TOOLS_DIR:-$HOME/.local/bin}"
mkdir -p "$BINDIR"

chmod +x "$tmpdir/linuxdeploy" "$tmpdir/linuxdeploy-plugin-gtk.sh" "$tmpdir/appimagetool"
install -m 0755 "$tmpdir/linuxdeploy" "$BINDIR/linuxdeploy"
install -m 0755 "$tmpdir/linuxdeploy-plugin-gtk.sh" "$BINDIR/linuxdeploy-plugin-gtk.sh"
install -m 0755 "$tmpdir/appimagetool" "$BINDIR/appimagetool"

export PATH="$BINDIR:$PATH"
linuxdeploy --help >/dev/null
appimagetool --version >/dev/null
echo "AppImage tools installed to $BINDIR"
echo "Ensure PATH includes: export PATH=\"$BINDIR:\$PATH\""
