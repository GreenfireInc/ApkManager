#!/usr/bin/env bash
# Download and pin Apktool for ApkManager builds.
set -euo pipefail

OUTDIR="${1:?usage: fetch-apktool.sh <output-dir>}"
VERSION="2.9.3"
JAR_NAME="apktool.jar"
DEST="${OUTDIR}/${JAR_NAME}"

# Official release mirror (Bitbucket downloads).
URL="https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_${VERSION}.jar"

mkdir -p "${OUTDIR}"

if [[ -f "${DEST}" ]]; then
  echo "fetch-apktool: ${DEST} already exists"
  exit 0
fi

echo "fetch-apktool: downloading Apktool ${VERSION}..."
curl -fsSL "${URL}" -o "${DEST}.tmp"
mv "${DEST}.tmp" "${DEST}"
echo "fetch-apktool: saved to ${DEST}"
