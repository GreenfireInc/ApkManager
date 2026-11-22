#!/bin/sh
# ATL.edge: builds Android Translation Layer from the latest upstream source
# into an AppImage, inside a throwaway rootless Podman container (Arch Linux),
# using pkgforge-dev's recipe (setup.sh, get-dependencies.sh, make-appimage.sh).
#
# Environment:
#   ATL_REF               ATL commit or branch to build (default: master)
#   ATL_EDGE_OUT          where the AppImage goes (default: ~/Downloads)
#   ATL_EDGE_MIN_FREE_GB  refuse to start below this much free space (default: 25)
#   ATL_EDGE_IMAGE        container image (default: ghcr.io/pkgforge-dev/archlinux:latest)
#
# On success the AppImage's path is written to <cache>/last-build and the
# build manifest to <cache>/atl-build.json.
set -eu

RECIPE=$(cd "$(dirname "$0")" && pwd)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/apk-manager/atl-edge"
OUT="${ATL_EDGE_OUT:-$HOME/Downloads}"
MIN_FREE_GB="${ATL_EDGE_MIN_FREE_GB:-25}"
IMAGE="${ATL_EDGE_IMAGE:-ghcr.io/pkgforge-dev/archlinux:latest}"
WORK="$CACHE/work"

if ! command -v podman >/dev/null; then
	echo "Podman is not installed. Debian, Ubuntu, Linux Mint: sudo apt install podman. Fedora: sudo dnf install podman." >&2
	exit 1
fi

mkdir -p "$CACHE/pacman" "$OUT"
rm -f "$CACHE/last-build"
# The container is root inside, so a previous tree can hold files owned by subuids.
[ -d "$WORK" ] && podman unshare rm -rf "$WORK"

free_gb=$(df -Pk "$CACHE" | awk 'NR == 2 { print int($4 / 1048576) }')
if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
	echo "Only ${free_gb} GB free; ATL.edge needs at least ${MIN_FREE_GB} GB to build." >&2
	exit 1
fi

mkdir -p "$WORK"
cp -r "$RECIPE/setup.sh" "$RECIPE/get-dependencies.sh" "$RECIPE/make-appimage.sh" \
	"$RECIPE/patches" "$RECIPE/AppDir" "$WORK/"

echo "==> ATL.edge: building Android Translation Layer from ${ATL_REF:-master} (latest upstream source)"
echo "==> Container: $IMAGE    Work: $WORK"
echo "==> The first build downloads several GB and can take an hour or more."
echo

podman run --rm --pull=newer \
	-v "$WORK":/work:Z -w /work \
	-v "$CACHE/pacman":/var/cache/pacman/pkg:Z \
	-e ATL_REF="${ATL_REF:-master}" \
	-e GITHUB_REPOSITORY= \
	"$IMAGE" \
	sh -c 'sh ./setup.sh && sh ./get-dependencies.sh && sh ./make-appimage.sh'

built=""
for f in "$WORK"/dist/*.AppImage; do
	[ -f "$f" ] && built=$f && break
done
if [ -z "$built" ]; then
	echo "The build finished without producing an AppImage." >&2
	exit 1
fi

version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$WORK/dist/atl-build.json")
target="$OUT/Android_Translation_Layer-${version:-edge}-anylinux-$(uname -m).AppImage"
cp "$built" "$target"
chmod +x "$target"
cp "$WORK/dist/atl-build.json" "$CACHE/atl-build.json"
echo "$target" > "$CACHE/last-build"

# The source and build trees are many GB; only the AppImage is kept.
podman unshare rm -rf "$WORK"

echo
echo "==> ATL.edge ${version} built: $target"
