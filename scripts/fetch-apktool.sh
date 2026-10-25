#!/usr/bin/env bash
# Download and pin Apktool for ApkManager builds.
set -euo pipefail

OUTDIR="${1:?usage: fetch-apktool.sh <output-dir> [source-root]}"
SOURCE_ROOT="${2:-}"
VERSION="2.9.3"
JAR_NAME="apktool.jar"
DEST="${OUTDIR}/${JAR_NAME}"
# Offline builds (Flatpak) download the JAR as a checksummed source into this path.
VENDORED="${SOURCE_ROOT:+${SOURCE_ROOT}/third_party/apktool/apktool_${VERSION}.jar}"

# Official release mirror (Bitbucket downloads).
URL="https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_${VERSION}.jar"

mkdir -p "${OUTDIR}"

if [[ -f "${DEST}" ]]; then
  echo "fetch-apktool: ${DEST} already exists"
  exit 0
fi

if [[ -n "${VENDORED}" && -f "${VENDORED}" ]]; then
  cp "${VENDORED}" "${DEST}"
  echo "fetch-apktool: using ${VENDORED}"
  exit 0
fi

echo "fetch-apktool: downloading Apktool ${VERSION}..."
curl -fsSL "${URL}" -o "${DEST}.tmp"
mv "${DEST}.tmp" "${DEST}"
echo "fetch-apktool: saved to ${DEST}"
