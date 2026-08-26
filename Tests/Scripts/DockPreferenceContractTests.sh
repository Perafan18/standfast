#!/bin/bash
# The Dock preference, and the two places that have to agree about it.
#
# `LSUIElement` starts the process without a Dock tile and cannot be a
# preference: it is read once at launch, and changing it means editing an
# installed bundle, which breaks the signature. So the switch is a runtime
# activation policy (`DockVisibility`), and the bundle keeps saying
# `LSUIElement`.
#
# That leaves the strict gate holding a belief that used to be free: it asserted
# the running app is background-only, which is now true or false depending on
# what the user asked for. Left alone it fails on the Mac of anybody who turns
# the switch on — a red gate reporting a preference working exactly as designed.
#
# Nothing in the build links the defaults key in the shell to the one in Swift.
# Rename it on one side and the gate silently reads a key nobody writes, which
# looks like "the preference is off" forever.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. The bundle still starts as an accessory. The preference promotes it; it is
#    not how the app ships.
lsui="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist 2>/dev/null || true)"
[ "$lsui" = "true" ] \
  || fail "Info.plist no longer declares LSUIElement: the app would take a Dock tile before anybody asked"

# 2. The key, in both languages.
swift_key="$(sed -n 's/.*static let defaultsKey = "\([^"]*\)".*/\1/p' \
  Sources/Standfast/DockVisibility.swift | head -n 1)"
[ -n "$swift_key" ] || fail "DockVisibility no longer declares defaultsKey"

script_key="$(sed -n 's/.*DOCK_PREFERENCE_KEY="\([^"]*\)".*/\1/p' Scripts/check-app.sh | head -n 1)"
[ -n "$script_key" ] || fail "check-app.sh does not name the Dock preference key"

[ "$swift_key" = "$script_key" ] \
  || fail "the Dock preference key disagrees: Swift says '$swift_key', check-app.sh says '$script_key'"

# 3. The gate reads the preference rather than assuming the answer. A grep for
#    the key is not enough — it has to reach the branch that expects a tile.
grep -q "background only: a Dock tile, as configured" Scripts/check-app.sh \
  || fail "check-app.sh still treats a Dock tile as a failure regardless of the preference"

echo "PASS"
