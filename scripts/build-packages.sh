#!/usr/bin/env bash
# Build ApkManager distribution packages.
#
# Usage:
#   ./scripts/build-packages.sh deb
#   ./scripts/build-packages.sh rpm
#   ./scripts/build-packages.sh flatpak
#   ./scripts/build-packages.sh snap
#   ./scripts/build-packages.sh appimage
#   ./scripts/build-packages.sh all
#
# Outputs land in ./dist/ (and ../ for deb by default).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep "version:" meson.build | head -1 | sed "s/.*'\\([^']*\\)'.*/\\1/")"
mkdir -p dist

usage() {
  cat <<EOF
Build ApkManager packages (version ${VERSION}).

  deb       Build .deb with dpkg-buildpackage
  rpm       Build .src.rpm and .rpm with rpmbuild
  flatpak   Build Flatpak with flatpak-builder
  snap      Build snap with snapcraft
  appimage  Build AppImage (linuxdeploy + appimagetool)
  all       Build every format supported on this host

Examples:
  ./scripts/build-packages.sh deb
  ./scripts/build-packages.sh flatpak
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool for this target: $1" >&2
    exit 1
  }
}

link_debian_dir() {
  if [[ -e debian && ! -L debian ]]; then
    echo "Refusing to overwrite debian/ (expected symlink to build/debian)." >&2
    exit 1
  fi
  if [[ ! -f build/debian/control ]]; then
    echo "Missing build/debian/control" >&2
    exit 1
  fi
  ln -sfn build/debian debian
}

unlink_debian_dir() {
  [[ -L debian ]] && rm -f debian
}

build_deb() {
  need dpkg-buildpackage
  need dh
  link_debian_dir
  trap unlink_debian_dir RETURN
  echo "==> Building Debian package"
  dpkg-buildpackage -us -uc -b
  mkdir -p dist
  mv ../*.deb dist/ 2>/dev/null || true
  mv ../*.changes dist/ 2>/dev/null || true
  mv ../*.buildinfo dist/ 2>/dev/null || true
  echo "Debian packages in dist/"
}

build_rpm() {
  need rpmbuild
  packaging/make-dist.sh
  mkdir -p "$HOME/rpmbuild/SOURCES"
  cp "dist/apk-manager-${VERSION}.tar.gz" "$HOME/rpmbuild/SOURCES/"
  echo "==> Building RPM"
  rpmbuild -ba packaging/rpm/apk-manager.spec
  mkdir -p dist
  cp "$HOME/rpmbuild/RPMS/"*/*.rpm dist/ 2>/dev/null || true
  cp "$HOME/rpmbuild/SRPMS/"*.rpm dist/ 2>/dev/null || true
  echo "RPM packages in dist/ and ~/rpmbuild/"
}

build_flatpak() {
  need flatpak
  need flatpak-builder
  echo "==> Installing Flatpak SDK/runtime (may prompt once)"
  flatpak install -y flathub org.gnome.Platform//47 org.gnome.Sdk//47 \
    org.freedesktop.Sdk.Extension.openjdk17//24.08 2>/dev/null || \
  flatpak install flathub org.gnome.Platform//47 org.gnome.Sdk//47 \
    org.freedesktop.Sdk.Extension.openjdk17//24.08
  echo "==> Building Flatpak"
  flatpak-builder --force-clean --repo=dist/flatpak-repo \
    dist/flatpak-build packaging/flatpak/com.github.ApkManager.yml
  flatpak build-bundle dist/flatpak-repo \
    "dist/com.github.ApkManager-${VERSION}.flatpak" com.github.ApkManager
  echo "Flatpak bundle: dist/com.github.ApkManager-${VERSION}.flatpak"
}

link_snap_dir() {
  if [[ -e snap && ! -L snap ]]; then
    echo "Refusing to overwrite snap/ (expected symlink to build/snap)." >&2
    exit 1
  fi
  ln -sfn build/snap snap
}

unlink_snap_dir() {
  [[ -L snap ]] && rm -f snap
}

build_snap() {
  need snapcraft
  link_snap_dir
  trap unlink_snap_dir RETURN
  echo "==> Building Snap"
  snapcraft pack --output "dist/apk-manager_${VERSION}_amd64.snap"
  echo "Snap: dist/apk-manager_${VERSION}_amd64.snap"
}

build_appimage() {
  packaging/appimage/build-appimage.sh
}

TARGET="${1:-}"
case "$TARGET" in
  deb) build_deb ;;
  rpm) build_rpm ;;
  flatpak) build_flatpak ;;
  snap) build_snap ;;
  appimage) build_appimage ;;
  all)
    build_deb || echo "deb: skipped or failed"
    build_rpm || echo "rpm: skipped or failed"
    build_flatpak || echo "flatpak: skipped or failed"
    build_snap || echo "snap: skipped or failed"
    build_appimage || echo "appimage: skipped or failed"
    ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 1
    ;;
esac
