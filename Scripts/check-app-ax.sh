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

AX_STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/standfast-ax.XXXXXX")" \
  || fail "could not create an Accessibility diagnostic file"
cleanup() {
  rm -f -- "$AX_STDERR_FILE"
}
trap cleanup EXIT

echo "==> Reading the menu (Accessibility coverage is required)"
# Menu bar 2, not 1: an agent app still gets a main menu bar it never shows,
# and that is the one holding the Apple menu. Status items live in the second.
menuStatus=0
menu="$(CHECK_PID="$PID" osascript 2>"$AX_STDERR_FILE" <<'APPLESCRIPT'
tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  tell (first process whose unix id is targetPID)
    if not (exists menu bar item 1 of menu bar 2) then return ""
      set pollAttemptLimit to 50
      set pollDelaySeconds to 0.1
      set statusItem to menu bar item 1 of menu bar 2
      set menuClosedBeforePress to false
      try
        if selected of statusItem then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (selected of statusItem)
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before AXPress"
      end if
      perform action "AXPress" of statusItem
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to selected of statusItem
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not become exposed through AXPress; the GUI session may be locked"
    end if
      set targetMenu to menu 1 of statusItem
      set visibleMenuItems to value of attribute "AXVisibleChildren" of targetMenu
      if (count of visibleMenuItems) is 0 then error "exposed status menu has no visible items"
      set directMenuItems to every menu item of targetMenu
      set names to {}
      repeat with directMenuItem in directMenuItems
        try
          set end of names to name of directMenuItem as text
        end try
      end repeat
      perform action "AXCancel" of targetMenu
      set menuClosedAfterCancel to false
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedAfterCancel to not (selected of statusItem)
        on error
          set menuClosedAfterCancel to false
        end try
        if menuClosedAfterCancel then exit repeat
        delay pollDelaySeconds
    end repeat
    if not menuClosedAfterCancel then error "status menu did not close after AXCancel"
    set previousDelimiters to text item delimiters of AppleScript
    set text item delimiters of AppleScript to linefeed
    set joinedNames to names as text
    set text item delimiters of AppleScript to previousDelimiters
    return joinedNames
  end tell
end tell
APPLESCRIPT
)" || menuStatus=$?
menuError="$(<"$AX_STDERR_FILE")"
if [ "$menuStatus" -ne 0 ]; then
  fail "Accessibility coverage is required, but the status menu could not be read: ${menuError:-osascript exited with status $menuStatus}"
fi
if [ -z "$menu" ]; then
  if [ -n "$menuError" ]; then
    fail "Accessibility coverage is required, but the status menu could not be read: $menuError"
  fi
  fail "Accessibility coverage is required, but the status menu could not be read"
fi
if [ -n "$menuError" ]; then
  printf '    osascript warning: %s\n' "$menuError" >&2
fi

echo "    menu: $menu"
# Check the supported static actions instead of scanning the entire menu for
# key-like text. Runner names are user data and may legitimately be values
# such as `state.prod` or `menu.build`.
printf '%s\n' "$menu" | grep -Fxq -e "Open Standfast" -e "Abrir Standfast" \
  || fail "the packaged menu did not expose the localized Control Center action"
printf '%s\n' "$menu" | grep -Fxq -e "Settings" -e "Configuración" \
  || fail "the packaged menu did not expose the localized Settings action"
printf '%s\n' "$menu" | grep -Fxq -e "Quit" -e "Salir" \
  || fail "the packaged menu did not expose the localized Quit action"

echo "==> Exercising Control Center and Settings through Accessibility"
: > "$AX_STDERR_FILE"
windowsStatus=0
windows="$(CHECK_PID="$PID" osascript 2>"$AX_STDERR_FILE" <<'APPLESCRIPT'
tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  tell (first process whose unix id is targetPID)
    set pollAttemptLimit to 50
      set pollDelaySeconds to 0.1

      set statusItem to menu bar item 1 of menu bar 2
      set menuClosedBeforePress to false
      try
        if selected of statusItem then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (selected of statusItem)
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before Control Center AXPress"
      end if
      perform action "AXPress" of statusItem
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to selected of statusItem
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not become exposed for Control Center; the GUI session may be locked"
    end if
      set targetMenu to menu 1 of statusItem
      set visibleMenuItems to value of attribute "AXVisibleChildren" of targetMenu
      if (count of visibleMenuItems) is 0 then error "exposed Control Center menu has no visible items"
      set directMenuItems to every menu item of targetMenu
      set targetMenuItem to missing value
      repeat with candidate in {"Open Standfast", "Abrir Standfast"}
        set candidateName to candidate as text
        repeat with directMenuItem in directMenuItems
          try
            set directName to name of directMenuItem as text
            if directName is candidateName then
              set targetMenuItem to contents of directMenuItem
              exit repeat
            end if
          end try
        end repeat
        if targetMenuItem is not missing value then exit repeat
      end repeat
    if targetMenuItem is missing value then error "visible Control Center menu item missing"
    perform action "AXPress" of targetMenuItem

    set controlWindow to missing value
    set controlWindowCount to 0
    set controlResolved to false
    set controlSingleton to false
    set controlMain to false
    set controlFocused to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlWindow to missing value
      set controlWindowCount to 0
      set processWindowCount to count of windows
      set controlResolved to false
      set controlMain to false
      set controlFocused to false
      repeat with candidate in {"Standfast Control Center", "Centro de control de Standfast"}
        set candidateWindows to every window whose name is (candidate as text)
        set candidateCount to count of candidateWindows
        set controlWindowCount to controlWindowCount + candidateCount
        if not controlResolved and candidateCount > 0 then
          set controlWindow to item 1 of candidateWindows
          set controlResolved to true
        end if
      end repeat
      set controlSingleton to controlWindowCount is 1 and processWindowCount is 1
      if controlResolved and controlSingleton then
        try
          set controlMain to value of attribute "AXMain" of controlWindow as boolean
          set controlFocused to value of attribute "AXFocused" of controlWindow as boolean
        end try
      end if
      if controlResolved and controlSingleton and controlMain and controlFocused then exit repeat
      delay pollDelaySeconds
    end repeat
    if not controlResolved and (count of windows) is 0 then
      error "Control Center action produced no window after AXPress on an exposed menu; the GUI session may be locked"
    end if

    set controlReady to controlResolved and controlSingleton and controlMain and controlFocused
    if controlReady then
      set closeButtons to every button of controlWindow whose subrole is "AXCloseButton"
      if (count of closeButtons) is 0 then error "Control Center close button missing"
      set closeButton to item 1 of closeButtons
      perform action "AXPress" of closeButton
    end if
    set controlClosed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      if (count of windows) is 0 then
        set controlClosed to true
        exit repeat
      end if
      delay pollDelaySeconds
    end repeat

      set settingsInitialEmpty to (count of windows) is 0
      set menuClosedBeforePress to false
      try
        if selected of statusItem then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (selected of statusItem)
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before Settings AXPress"
      end if
      perform action "AXPress" of statusItem
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to selected of statusItem
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not become exposed for Settings; the GUI session may be locked"
    end if
      set targetMenu to menu 1 of statusItem
      set visibleMenuItems to value of attribute "AXVisibleChildren" of targetMenu
      if (count of visibleMenuItems) is 0 then error "exposed Settings menu has no visible items"
      set directMenuItems to every menu item of targetMenu
      set targetMenuItem to missing value
      repeat with candidate in {"Settings", "Configuración"}
        set candidateName to candidate as text
        repeat with directMenuItem in directMenuItems
          try
            set directName to name of directMenuItem as text
            if directName is candidateName then
              set targetMenuItem to contents of directMenuItem
              exit repeat
            end if
          end try
        end repeat
        if targetMenuItem is not missing value then exit repeat
      end repeat
    if targetMenuItem is missing value then error "visible Settings menu item missing"
    perform action "AXPress" of targetMenuItem

    set settingsWindow to missing value
    set settingsWindowCount to 0
    set settingsOpened to false
    set settingsSingleton to false
    set settingsMain to false
    set settingsFocused to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set settingsWindow to missing value
      set settingsWindowCount to count of windows
      set settingsOpened to settingsWindowCount > 0
      set settingsSingleton to settingsWindowCount is 1
      set settingsMain to false
      set settingsFocused to false
      if settingsSingleton then
        set settingsWindow to window 1
        try
          set settingsMain to value of attribute "AXMain" of settingsWindow as boolean
          set settingsFocused to value of attribute "AXFocused" of settingsWindow as boolean
        end try
      end if
      if settingsOpened and settingsSingleton and settingsMain and settingsFocused then exit repeat
      delay pollDelaySeconds
    end repeat
    if not settingsOpened then
      error "Settings action produced no window after AXPress on an exposed menu; the GUI session may be locked"
    end if

    set settingsReady to settingsInitialEmpty and settingsOpened and settingsSingleton and ¬
      settingsMain and settingsFocused
    if settingsReady then
      set closeButtons to every button of settingsWindow whose subrole is "AXCloseButton"
      if (count of closeButtons) is 0 then error "Settings close button missing"
      set closeButton to item 1 of closeButtons
      perform action "AXPress" of closeButton
    end if
    repeat with pollAttempt from 1 to pollAttemptLimit
      if (count of windows) is 0 then
        exit repeat
      end if
      delay pollDelaySeconds
    end repeat
    set remainingWindows to count of windows
    set settingsClosed to remainingWindows is 0
    set statusItemAlive to exists menu bar item 1 of menu bar 2
    return (controlResolved as text) & "|" & (controlSingleton as text) & "|" & ¬
      (controlMain as text) & "|" & (controlFocused as text) & "|" & ¬
      (controlClosed as text) & "|" & (settingsInitialEmpty as text) & "|" & ¬
      (settingsOpened as text) & "|" & (settingsSingleton as text) & "|" & ¬
      (settingsMain as text) & "|" & (settingsFocused as text) & "|" & ¬
      (settingsClosed as text) & "|" & (remainingWindows as text) & "|" & ¬
      (statusItemAlive as text)
  end tell
end tell
APPLESCRIPT
)" || windowsStatus=$?
windowsError="$(<"$AX_STDERR_FILE")"
if [ "$windowsStatus" -ne 0 ]; then
  fail "Accessibility lifecycle probe aborted: ${windowsError:-osascript exited with status $windowsStatus}"
fi
if [ -n "$windowsError" ]; then
  printf '    osascript warning: %s\n' "$windowsError" >&2
fi

controlResolved=""
controlSingleton=""
controlMain=""
controlFocused=""
controlClosed=""
settingsInitialEmpty=""
settingsOpened=""
settingsSingleton=""
settingsMain=""
settingsFocused=""
settingsClosed=""
remainingWindows=""
statusItemAlive=""
IFS='|' read -r controlResolved controlSingleton controlMain controlFocused \
  controlClosed settingsInitialEmpty settingsOpened settingsSingleton \
  settingsMain settingsFocused settingsClosed remainingWindows statusItemAlive \
  <<< "$windows" || true

if [ "$controlResolved" = true ] && [ "$controlSingleton" = true ] \
  && [ "$controlMain" = true ] && [ "$controlFocused" = true ] \
  && [ "$controlClosed" = true ] && [ "$settingsInitialEmpty" = true ] \
  && [ "$settingsOpened" = true ] && [ "$settingsSingleton" = true ] \
  && [ "$settingsMain" = true ] && [ "$settingsFocused" = true ] \
  && [ "$settingsClosed" = true ] && [ "$remainingWindows" = 0 ] \
  && [ "$statusItemAlive" = true ]; then
  echo "    singleton main/focused Control Center and Settings lifecycle passed"
else
  failure="window lifecycle AX check failed: resolved=${controlResolved:-missing}, singleton=${controlSingleton:-missing}, main=${controlMain:-missing}, focused=${controlFocused:-missing}, controlClosed=${controlClosed:-missing}, settingsInitialEmpty=${settingsInitialEmpty:-missing}, settingsOpened=${settingsOpened:-missing}, settingsSingleton=${settingsSingleton:-missing}, settingsMain=${settingsMain:-missing}, settingsFocused=${settingsFocused:-missing}, settingsClosed=${settingsClosed:-missing}, remaining=${remainingWindows:-missing}, statusItemAlive=${statusItemAlive:-missing}"
  fail "$failure"
fi

kill -0 "$PID" 2>/dev/null \
  || fail "closing every window terminated the menu-bar process"
