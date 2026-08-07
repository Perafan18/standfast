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

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/\
LaunchServices.framework/Support/lsregister

cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  # Launching the staged copy registers this path with LaunchServices under
  # `dev.standfast.app`, and deleting the directory does not unregister it.
  # Every run of this script therefore used to leave one more entry claiming
  # the app's bundle identifier at a path that no longer exists — twenty of
  # them accumulated on the machine this was found on, each reported by
  # `lsregister -dump` as "Bundle node not found on disk". Whatever else that
  # costs, it makes `dev.standfast.app` resolve to a phantom, and the app this
  # script exists to prove is installable is the one being shadowed.
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$APP" 2>/dev/null || true
  rm -rf "$STAGE"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Reject typos before doing a build whose evidence would otherwise be labeled
# with a mode the script never understood.
"$ROOT/Scripts/check-app-ax.sh" --validate

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }

SOURCE_ICON="$ROOT/Resources/AppIcon.png"
[ -f "$SOURCE_ICON" ] || fail "Resources/AppIcon.png is missing"
source_icon_format="$(sips -g format "$SOURCE_ICON" 2>/dev/null \
  | awk '/format:/ { print $2 }')"
[ "$source_icon_format" = "png" ] \
  || fail "Resources/AppIcon.png is $source_icon_format, not PNG"
source_icon_has_alpha="$(sips -g hasAlpha "$SOURCE_ICON" 2>/dev/null \
  | awk '/hasAlpha:/ { print $2 }')"
[ "$source_icon_has_alpha" = "no" ] \
  || fail "Resources/AppIcon.png must be an opaque PNG (hasAlpha=$source_icon_has_alpha)"
source_icon_dimensions="$(sips -g pixelWidth -g pixelHeight "$SOURCE_ICON" 2>/dev/null \
  | awk '/pixelWidth:/ { width = $2 } /pixelHeight:/ { height = $2 } END { print width "x" height }')"
[ "$source_icon_dimensions" = "1024x1024" ] \
  || fail "Resources/AppIcon.png is $source_icon_dimensions, not 1024x1024"

echo "==> Assembling the bundle"
"$ROOT/Scripts/build-app.sh" >/dev/null
cp -R "$ROOT/.build/Standfast.app" "$APP"

echo "==> Checking the bundle's shape"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist does not lint"
[ -x "$APP/Contents/MacOS/Standfast" ] || fail "no executable in Contents/MacOS"
[ "$(plist CFBundleIdentifier)" = "dev.standfast.app" ] || fail "wrong bundle identifier"
[ "$(plist CFBundleIconFile)" = "Standfast" ] || fail "wrong bundle icon name"
[ "$(plist LSUIElement)" = "true" ] || fail "LSUIElement is not set: this app would take a Dock tile"
[ -d "$APP/Contents/Resources/Standfast_Standfast.bundle" ] \
  || fail "the SwiftPM resource bundle did not make it into the app"
APP_ICON="$APP/Contents/Resources/Standfast.icns"
[ -f "$APP_ICON" ] || fail "Standfast.icns is missing from the bundle"
app_icon_format="$(sips -g format "$APP_ICON" 2>/dev/null \
  | awk '/format:/ { print $2 }')"
[ "$app_icon_format" = "icns" ] || fail "Standfast.icns is not an ICNS file"
APP_ICONSET="$STAGE/Standfast.iconset"
/usr/bin/iconutil -c iconset "$APP_ICON" -o "$APP_ICONSET" \
  || fail "Standfast.icns could not be expanded as an iconset"
for icon_specification in \
  icon_16x16.png:16 \
  icon_16x16@2x.png:32 \
  icon_32x32.png:32 \
  icon_32x32@2x.png:64 \
  icon_128x128.png:128 \
  icon_128x128@2x.png:256 \
  icon_256x256.png:256 \
  icon_256x256@2x.png:512 \
  icon_512x512.png:512 \
  icon_512x512@2x.png:1024; do
  icon_name="${icon_specification%%:*}"
  expected_pixels="${icon_specification##*:}"
  icon_file="$APP_ICONSET/$icon_name"
  [ -f "$icon_file" ] || fail "Standfast.icns is missing $icon_name"
  icon_dimensions="$(sips -g pixelWidth -g pixelHeight "$icon_file" 2>/dev/null \
    | awk '/pixelWidth:/ { width = $2 } /pixelHeight:/ { height = $2 } END { print width "x" height }')"
  [ "$icon_dimensions" = "${expected_pixels}x${expected_pixels}" ] \
    || fail "$icon_name is $icon_dimensions, not ${expected_pixels}x${expected_pixels}"
done
# The identifier `codesign` reports, not the one Info.plist claims. Until the
# bundle is signed the two differ — SwiftPM leaves the executable linker-signed
# as `Standfast` with Info.plist unbound — and an app with no bundle identity
# is one whose notifications `usernoted` drops without registering it or
# saying anything. Nothing on screen, nothing in a log.
# Read into a variable rather than piped into `grep -q`: under `pipefail` a grep
# that stops at its first match leaves codesign writing into a closed pipe, and
# the SIGPIPE it dies of becomes the status of the whole pipeline — a check that
# fails or passes depending on which process got there first.
signature="$(codesign -dvvv "$APP" 2>&1 || true)"
case "$signature" in
  *"Identifier=dev.standfast.app"*) ;;
  *) fail "the bundle is not signed as dev.standfast.app: notifications will be dropped" ;;
esac

# That the seal actually closes over the files that were copied in. The check
# above only reads what the signature claims; this one recomputes it, and it is
# what catches a resource added to the bundle after signing — which stays
# invisible until Gatekeeper refuses the app on somebody else's Mac.
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 \
  || fail "the signature does not verify"

# The hardened runtime, on the ad-hoc path too. Notarisation requires it, and a
# release is the worst place to discover it was dropped: the notary service
# rejects the upload after several minutes with a message that names no line of
# any script. Asserting it on every build makes the revert fail here instead.
flags="$(printf '%s\n' "$signature" | sed -n 's/.*flags=\([^ ]*\).*/\1/p')"
case "$flags" in
  *runtime*) ;;
  *) fail "the bundle is not signed with the hardened runtime (flags=$flags)" ;;
esac

# Gatekeeper's verdict, reported rather than asserted, because the right answer
# depends on the certificate this machine happens to have. An ad-hoc build is
# *supposed* to be rejected — that is what unsigned distribution means — so
# failing on it would break every contributor and all of CI. A Developer ID
# build that is rejected is a real problem, and that one does fail.
echo "==> Gatekeeper's assessment"
assessment="$(spctl --assess --type install -vv "$APP" 2>&1 || true)"
printf '    %s\n' "${assessment//$'\n'/$'\n    '}"
case "$signature" in
  *"Authority=Developer ID Application:"*)
    case "$assessment" in
      *accepted*) ;;
      *) fail "signed with a Developer ID and still rejected by Gatekeeper" ;;
    esac ;;
  *)
    echo "    (ad-hoc build: rejection here is expected)" ;;
esac
for language in en es; do
  [ -d "$APP/Contents/Resources/$language.lproj" ] || fail "$language.lproj is missing"
  plist "CFBundleLocalizations" | grep -qx "    $language" \
    || fail "$language is not declared in CFBundleLocalizations"
done
"$ROOT/Scripts/check-localization-catalogues.sh" "$ROOT" "$APP"

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

AX_CHECK_STATUS=0
"$ROOT/Scripts/check-app-ax.sh" "$PID" || AX_CHECK_STATUS=$?

echo "==> Checking it stays out of the Dock"
background="$(CHECK_PID="$PID" osascript -e \
  'tell application "System Events" to get background only of (first process whose unix id is ((system attribute "CHECK_PID") as integer))' \
  2>/dev/null || true)"
case "$background" in
  true) echo "    background only: no Dock tile" ;;
  "") echo "    SKIPPED: could not read the process list" ;;
  *) fail "the app is not background-only; LSUIElement did not take effect" ;;
esac

[ "$AX_CHECK_STATUS" -eq 0 ] || exit "$AX_CHECK_STATUS"

echo "PASS"
