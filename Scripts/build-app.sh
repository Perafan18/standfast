#!/bin/bash
# Assembles Standfast.app out of the SwiftPM build product.
#
# A script rather than an .xcodeproj on purpose: project files produce merge
# conflicts nobody can read, and a contributor who has to open Xcode to change
# a string is a contributor who does not.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONFIG="${CONFIG:-release}"
DEST="${DEST:-.build/Standfast.app}"

swift build -c "$CONFIG" --product Standfast
BIN="$(swift build -c "$CONFIG" --show-bin-path | tail -n 1)"

EXECUTABLE="$BIN/Standfast"
# Named after the package and the target, both of which are "Standfast".
RESOURCES="$BIN/Standfast_Standfast.bundle"

# Loudly, not with `|| true`. A missing catalogue costs the user their own
# language, and the app is built to survive that rather than crash — which
# means a packaging mistake here would ship and never be noticed.
for required in "$EXECUTABLE" "$RESOURCES"; do
  if [ ! -e "$required" ]; then
    echo "build-app.sh: $required is missing; the build did not produce it" >&2
    exit 1
  fi
done

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cp "$EXECUTABLE" "$DEST/Contents/MacOS/Standfast"
cp Resources/Info.plist "$DEST/Contents/Info.plist"

# Both halves of the localisation, and they are not redundant.
#
# The SwiftPM bundle is what `L10n.resourceBundle` looks for by name, and it
# has to land somewhere `Bundle.main` can reach: Contents/Resources is
# `Bundle.main.resourceURL`, which is one of the places the accessor searches,
# and it is the only one of them that leaves the `.app` a well-formed bundle —
# anything sitting next to Contents/ is unsealed content that `codesign`
# refuses, which would have to be undone the day this app gets notarised.
cp -R "$RESOURCES" "$DEST/Contents/Resources/"

# The loose `.lproj` directories are what make Contents/Resources itself a
# localised bundle, so `Bundle.main` can answer in Spanish even if the bundle
# above were lost, and — with CFBundleLocalizations in Info.plist — what makes
# macOS offer Standfast in the per-app language picker.
cp -R "$RESOURCES"/*.lproj "$DEST/Contents/Resources/"

# LaunchServices caches bundle metadata by mtime; without this a rebuilt app
# can keep being launched with the previous Info.plist.
touch "$DEST"

echo "Built $DEST"
