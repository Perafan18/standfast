#!/bin/bash
# Exercises the packaged app's status menu and window lifecycle through the
# macOS Accessibility tree. `check-app.sh` owns packaging and process checks;
# keeping this probe separate makes its permission contract executable without
# weakening the full check.
set -euo pipefail

AX_MODE="${STANDFAST_AX_MODE:-require}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case "$AX_MODE" in
  require|skip) ;;
  *) fail "STANDFAST_AX_MODE must be require or skip (got: $AX_MODE)" ;;
esac

if [ "${1:-}" = "--validate" ]; then
  exit 0
fi

[ "$#" = 1 ] || fail "usage: check-app-ax.sh <pid>"
PID="$1"

if [ "$AX_MODE" = "skip" ]; then
  echo "==> AX COVERAGE SKIPPED: menu, windows, and Accessibility are NOT COVERED"
  echo "    Control Center and Settings lifecycle is not tested in this mode."
  exit 0
fi

echo "==> Reading the menu (Accessibility coverage is required)"
# Menu bar 2, not 1: an agent app still gets a main menu bar it never shows,
# and that is the one holding the Apple menu. Status items live in the second.
menu="$(CHECK_PID="$PID" osascript 2>/dev/null <<'APPLESCRIPT' || true
tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  tell (first process whose unix id is targetPID)
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
[ -n "$menu" ] \
  || fail "Accessibility coverage is required, but the status menu could not be read"

echo "    menu: $menu"
# Dotted identifiers are what a menu looks like when every lookup missed and
# the built-in English was not there to catch it.
case "$menu" in
  # One pattern per family of keys in L10n. A new family that is not added here
  # is a family this check silently stops covering.
  *menu.*|*state.*|*job.*|*duration.*|*thermal.*|*notification.*)
    fail "the menu is showing raw localisation keys" ;;
esac

echo "==> Exercising Control Center and Settings through Accessibility"
windows="$(CHECK_PID="$PID" osascript 2>/dev/null <<'APPLESCRIPT' || true
tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  tell (first process whose unix id is targetPID)
    click menu bar item 1 of menu bar 2
    delay 1
    set controlClicked to false
    repeat with candidate in {"Open Standfast", "Abrir Standfast"}
      if exists menu item (candidate as text) of menu 1 of menu bar item 1 of menu bar 2 then
        click menu item (candidate as text) of menu 1 of menu bar item 1 of menu bar 2
        set controlClicked to true
        exit repeat
      end if
    end repeat
    if not controlClicked then error "Control Center menu item missing"
    delay 1
    set controlWindow to missing value
    set controlWindowCount to 0
    set controlResolved to false
    repeat with candidate in {"Standfast Control Center", "Centro de control de Standfast"}
      set candidateWindows to every window whose name is (candidate as text)
      set candidateCount to count of candidateWindows
      set controlWindowCount to controlWindowCount + candidateCount
      if not controlResolved and candidateCount > 0 then
        set controlWindow to item 1 of candidateWindows
        set controlResolved to true
      end if
    end repeat
    set controlSingleton to controlWindowCount is 1
    set controlMain to false
    set controlFocused to false
    if controlResolved then
      set controlMain to value of attribute "AXMain" of controlWindow as boolean
      set controlFocused to value of attribute "AXFocused" of controlWindow as boolean
      perform action "AXClose" of controlWindow
    end if
    delay 1
    set remainingControlWindows to 0
    repeat with candidate in {"Standfast Control Center", "Centro de control de Standfast"}
      set remainingControlWindows to remainingControlWindows + ¬
        (count of (every window whose name is (candidate as text)))
    end repeat
    set controlClosed to remainingControlWindows is 0

    click menu bar item 1 of menu bar 2
    delay 1
    set settingsClicked to false
    repeat with candidate in {"Settings", "Configuración"}
      if exists menu item (candidate as text) of menu 1 of menu bar item 1 of menu bar 2 then
        click menu item (candidate as text) of menu 1 of menu bar item 1 of menu bar 2
        set settingsClicked to true
        exit repeat
      end if
    end repeat
    if not settingsClicked then error "Settings menu item missing"
    delay 1
    set settingsOpened to (count of windows) > 0
    set closeAttemptLimit to 8
    set closeAttempts to 0
    repeat
      if (count of windows) is 0 then exit repeat
      if closeAttempts is greater than or equal to closeAttemptLimit then exit repeat
      set closeAttempts to closeAttempts + 1
      try
        perform action "AXClose" of window 1
      on error
        exit repeat
      end try
      delay 0.25
    end repeat
    set remainingWindows to count of windows
    set settingsClosedWithinLimit to ¬
      ((remainingWindows is 0) and (closeAttempts is less than or equal to closeAttemptLimit))
    set statusItemAlive to exists menu bar item 1 of menu bar 2
    return (controlResolved as text) & "|" & (controlSingleton as text) & "|" & ¬
      (controlMain as text) & "|" & (controlFocused as text) & "|" & ¬
      (controlClosed as text) & "|" & (settingsOpened as text) & "|" & ¬
      (settingsClosedWithinLimit as text) & "|" & (remainingWindows as text) & "|" & ¬
      (closeAttempts as text) & "|" & (statusItemAlive as text)
  end tell
end tell
APPLESCRIPT
)"

controlResolved=""
controlSingleton=""
controlMain=""
controlFocused=""
controlClosed=""
settingsOpened=""
settingsClosedWithinLimit=""
remainingWindows=""
closeAttempts=""
statusItemAlive=""
IFS='|' read -r controlResolved controlSingleton controlMain controlFocused \
  controlClosed settingsOpened settingsClosedWithinLimit remainingWindows \
  closeAttempts statusItemAlive <<< "$windows" || true
attemptsAreBounded=false
case "$closeAttempts" in
  ""|*[!0-9]*) ;;
  *) [ "$closeAttempts" -le 8 ] && attemptsAreBounded=true ;;
esac

if [ "$controlResolved" = true ] && [ "$controlSingleton" = true ] \
  && [ "$controlMain" = true ] && [ "$controlFocused" = true ] \
  && [ "$controlClosed" = true ] && [ "$settingsOpened" = true ] \
  && [ "$settingsClosedWithinLimit" = true ] && [ "$remainingWindows" = 0 ] \
  && [ "$attemptsAreBounded" = true ] && [ "$statusItemAlive" = true ]; then
  echo "    singleton main/focused Control Center and bounded Settings close passed"
else
  fail "window lifecycle AX check failed: resolved=${controlResolved:-missing}, singleton=${controlSingleton:-missing}, main=${controlMain:-missing}, focused=${controlFocused:-missing}, controlClosed=${controlClosed:-missing}, settingsOpened=${settingsOpened:-missing}, settingsClosedWithinLimit=${settingsClosedWithinLimit:-missing}, remaining=${remainingWindows:-missing}, closeAttempts=${closeAttempts:-missing}, statusItemAlive=${statusItemAlive:-missing}"
fi

kill -0 "$PID" 2>/dev/null \
  || fail "closing every window terminated the menu-bar process"
