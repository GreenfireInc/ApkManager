#!/usr/bin/env bash
# Copy the pinned apktool.jar into the install prefix verbatim.
#
# Invoked by Meson via meson.add_install_script(). Meson's built-in installer
# treats any installed build-target output ending in `.jar` as a Java target
# and runs `jar xf` / `jar ufM` to strip Class-Path from its manifest. That
# requires a JDK `jar` binary (absent on headless-JRE-only hosts) and would
# modify a third-party release artifact. A plain copy avoids both problems.
set -euo pipefail

SRC="${1:?usage: install-apktool.sh <built-jar> <libdir-relative-subdir>}"
REL_DIR="${2:?usage: install-apktool.sh <built-jar> <libdir-relative-subdir>}"

# Meson exports MESON_INSTALL_DESTDIR_PREFIX = $DESTDIR + prefix.
PREFIX="${MESON_INSTALL_DESTDIR_PREFIX:?MESON_INSTALL_DESTDIR_PREFIX not set; run via meson install}"
DEST_DIR="${PREFIX}/${REL_DIR}"

if [[ ! -f "${SRC}" ]]; then
  echo "install-apktool: ${SRC} not found; run 'meson compile' first" >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"
install -m 0644 "${SRC}" "${DEST_DIR}/apktool.jar"
echo "Installing apktool.jar to ${DEST_DIR}"
