#!/bin/sh
# ATL.edge: is upstream newer than the installed edge build?
# Compares the four GitLab heads with the manifest ApkManager saves after
# installing an edge build. Prints one line per changed repo.
# Exit: 0 update available, 1 up to date, 2 error (no manifest, network).
set -eu

MANIFEST="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/apk-manager/atl-edge-build.json}"
BASE=https://gitlab.com/android_translation_layer

if [ ! -f "$MANIFEST" ]; then
	echo "No ATL.edge build recorded at $MANIFEST" >&2
	exit 2
fi

changed=0
for pair in atl:android_translation_layer art_standalone:art_standalone \
	bionic_translation:bionic_translation libopensles_standalone:libopensles-standalone; do
	key=${pair%%:*}
	repo=${pair#*:}
	remote=$(git ls-remote "$BASE/$repo.git" HEAD | cut -f1) || exit 2
	[ -n "$remote" ] || exit 2
	installed=$(sed -n "s/.*\"$key\": *\"\\([0-9a-f]*\\)\".*/\\1/p" "$MANIFEST")
	if [ "$remote" != "$installed" ]; then
		echo "$repo: $(echo "$installed" | cut -c1-8) -> $(echo "$remote" | cut -c1-8)"
		changed=1
	fi
done

[ "$changed" = 1 ] && exit 0
exit 1
