#!/bin/bash
# Assembles Standfast.app, moves it away from the build tree, deletes the build
# tree, and launches it.
#
# The one check no unit test can make. Under `swift test` the binary sits in
# .build next to everything it was compiled with, so every path it might look
# for a resource along happens to exist — including the absolute build
# directory baked into `Bundle.module`'s accessor, which calls `fatalError`
# when it misses. That is why a packaging bug here reads as "works on my
# machine" and dies with SIGTRAP on everybody else's: the bug is not in the
# code, it is in which files ended up next to it.
#
# Deleting .build before launching is the whole trick. Skip it and the app
# finds its resources at the compile-time path and the test proves nothing.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

ALIVE_SECONDS="${ALIVE_SECONDS:-6}"
STAGE="$(mktemp -d /tmp/standfast-check.XXXXXX)"
APP="$STAGE/Standfast.app"
PID=""

cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }

echo "==> Assembling the bundle"
"$ROOT/Scripts/build-app.sh" >/dev/null
cp -R "$ROOT/.build/Standfast.app" "$APP"

echo "==> Checking the bundle's shape"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist does not lint"
[ -x "$APP/Contents/MacOS/Standfast" ] || fail "no executable in Contents/MacOS"
[ "$(plist CFBundleIdentifier)" = "dev.standfast.app" ] || fail "wrong bundle identifier"
[ "$(plist LSUIElement)" = "true" ] || fail "LSUIElement is not set: this app would take a Dock tile"
[ -d "$APP/Contents/Resources/Standfast_Standfast.bundle" ] \
  || fail "the SwiftPM resource bundle did not make it into the app"
for language in en es; do
  [ -d "$APP/Contents/Resources/$language.lproj" ] || fail "$language.lproj is missing"
  plist "CFBundleLocalizations" | grep -qx "    $language" \
    || fail "$language is not declared in CFBundleLocalizations"
done

echo "==> Deleting the build tree the app was compiled in"
rm -rf "$ROOT/.build"
[ -d "$ROOT/.build" ] && fail ".build survived; the launch below would prove nothing"

echo "==> Launching $APP"
"$APP/Contents/MacOS/Standfast" >"$STAGE/stdout" 2>"$STAGE/stderr" &
PID=$!

for _ in $(seq "$ALIVE_SECONDS"); do
  sleep 1
  if ! kill -0 "$PID" 2>/dev/null; then
    status=0
    wait "$PID" || status=$?
    echo "--- stderr ---"
    cat "$STAGE/stderr" >&2
    # 128+5: SIGTRAP, which is what `fatalError` in a resource accessor looks
    # like from out here.
    [ "$status" = 133 ] && fail "the app trapped on startup (exit 133, SIGTRAP)"
    fail "the app exited on startup with status $status"
  fi
done
echo "    still alive after ${ALIVE_SECONDS}s"

# Best effort from here down: reading another process's menu needs Accessibility
# permission, which a CI runner does not have and cannot be asked for. Reported
# as skipped rather than failed so this script stays usable from CI, where the
# launch above is still the check that matters.
echo "==> Reading the menu (needs Accessibility permission)"
# Menu bar 2, not 1: an agent app still gets a main menu bar it never shows,
# and that is the one holding the Apple menu. Status items live in the second.
menu="$(osascript 2>/dev/null <<'APPLESCRIPT' || true
tell application "System Events"
  tell process "Standfast"
    if not (exists menu bar item 1 of menu bar 2) then return ""
    click menu bar item 1 of menu bar 2
    delay 1.5
    set names to name of every menu item of menu 1 of menu bar item 1 of menu bar 2
    key code 53
    return names as text
  end tell
end tell
APPLESCRIPT
)"
if [ -z "$menu" ]; then
  echo "    SKIPPED: no Accessibility permission, or no status item to read"
else
  echo "    menu: $menu"
  # Dotted identifiers are what a menu looks like when every lookup missed and
  # the built-in English was not there to catch it.
  case "$menu" in
    # One pattern per family of keys in L10n. A new family that is not added
    # here is a family this check silently stops covering.
    *menu.*|*state.*|*job.*|*duration.*)
      fail "the menu is showing raw localisation keys" ;;
  esac
fi

echo "==> Checking it stays out of the Dock"
background="$(osascript -e \
  'tell application "System Events" to get background only of process "Standfast"' \
  2>/dev/null || true)"
case "$background" in
  true) echo "    background only: no Dock tile" ;;
  "") echo "    SKIPPED: could not read the process list" ;;
  *) fail "the app is not background-only; LSUIElement did not take effect" ;;
esac

echo "PASS"
