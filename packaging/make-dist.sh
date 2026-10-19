#!/usr/bin/env bash
# Create apk-manager-VERSION.tar.gz for RPM and other distros.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep "version:" "$ROOT/meson.build" | head -1 | sed "s/.*'\\([^']*\\)'.*/\\1/")"
NAME="apk-manager-${VERSION}"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/$NAME"
tar -C "$ROOT" \
  --exclude=.git \
  --exclude=build/meson-debian \
  --exclude=build/meson-appimage \
  --exclude=build/AppDir \
  --exclude=build/debian/apk-manager \
  --exclude=build/debian/.debhelper \
  --exclude=build/debian/debhelper-build-stamp \
  --exclude=build/debian/files \
  --exclude=build/debian/*.substvars \
  --exclude=build/snap/parts \
  --exclude=build/snap/stage \
  --exclude=build/snap/prime \
  --exclude=dist \
  --exclude=.venv-gplay \
  --exclude='*.AppImage' \
  -cf - . | tar -C "$STAGING/$NAME" -xf -

mkdir -p "$ROOT/dist"
tar -C "$STAGING" -czf "$ROOT/dist/${NAME}.tar.gz" "$NAME"
echo "Created $ROOT/dist/${NAME}.tar.gz"
