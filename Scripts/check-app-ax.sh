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
AX_CLICK_TOOL=""
AX_POINTER_ORIGIN=""
restore_pointer() {
  [ -n "$AX_CLICK_TOOL" ] || return 0
  [ -n "$AX_POINTER_ORIGIN" ] || return 0
  # Leaving the pointer parked over a menu bar item is its own small lie about
  # the machine's state; put it back where the operator left it.
  # shellcheck disable=SC2086 # Two integers, deliberately word-split.
  "$AX_CLICK_TOOL" move $AX_POINTER_ORIGIN >/dev/null 2>&1 || return 0
}
cleanup() {
  rm -f -- "$AX_STDERR_FILE"
  restore_pointer
  return 0
}
trap cleanup EXIT

# A locked screen starts no menu tracking and discards synthetic clicks, so
# every press below fails and the app looks broken when it is not. This is a
# diagnosis, never a verdict: the probe still runs and still reports what it
# actually saw, and only appends the lock as the likely cause of a failure.
SESSION_LOCK_NOTE=""
if ioreg -n Root -d1 -a 2>/dev/null \
  | grep -A1 -F '<key>IOConsoleLocked</key>' \
  | grep -qF '<true/>'; then
  SESSION_LOCK_NOTE=" (this login session's screen is locked, which discards the synthetic input this probe needs; unlock the Mac and run the gate again)"
fi

# `perform action "AXPress"` reaches a SwiftUI MenuBarExtra item's Accessibility
# entry without running its action on macOS 27: the item reports itself pressed,
# no scene opens, and the app's own activation logger never fires. Menu tracking
# begins only for genuine HID events, so the probe posts real clicks.
if [ -n "${STANDFAST_AX_CLICK_TOOL:-}" ]; then
  AX_CLICK_TOOL="$STANDFAST_AX_CLICK_TOOL"
  [ -x "$AX_CLICK_TOOL" ] \
    || fail "STANDFAST_AX_CLICK_TOOL is not executable: $AX_CLICK_TOOL"
else
  AX_CLICK_SOURCE="$(dirname "$0")/ax-click.swift"
  [ -f "$AX_CLICK_SOURCE" ] \
    || fail "the click helper source is missing: $AX_CLICK_SOURCE"
  # Cached beside the build products, not in a temporary directory: this gate
  # runs many times in a row and a fresh compile each time is pure latency.
  AX_CLICK_TOOL="$(dirname "$0")/../.build/standfast-ax-click"
  if [ ! -x "$AX_CLICK_TOOL" ] || [ "$AX_CLICK_SOURCE" -nt "$AX_CLICK_TOOL" ]; then
    mkdir -p -- "$(dirname "$AX_CLICK_TOOL")" \
      || fail "could not create the click helper cache directory"
    swiftc -O "$AX_CLICK_SOURCE" -o "$AX_CLICK_TOOL" \
      || fail "could not build the click helper from $AX_CLICK_SOURCE"
  fi
fi
AX_POINTER_ORIGIN="$("$AX_CLICK_TOOL" where 2>/dev/null)" || AX_POINTER_ORIGIN=""

# An app in full screen hides the menu bar, and the status item goes on
# reporting the position it would occupy. Every click below then lands in the
# full-screen app, no menu tracks, and the failure reads as a broken app.
#
# Push the pointer into the top edge first, which is what a person does to get
# the bar back. Unconditional: the helper cannot tell whether the bar is
# hidden, and doing it to a screen whose bar is already showing costs nothing.
"$AX_CLICK_TOOL" reveal-menu-bar >/dev/null 2>&1 || true

# Then name the condition, so a failure below does not get blamed on the app.
# Asked through the click helper rather than a third `osascript`: the two
# AppleScript calls below are the menu read and the window lifecycle, and a
# diagnostic that quietly became a third would be a change to what this gate
# does. Like the locked screen above, this is a diagnosis and never a verdict:
# the probe still runs and still reports what it actually saw.
MENU_BAR_NOTE=""
menuBarState="$("$AX_CLICK_TOOL" menu-bar-state 2>/dev/null)" || menuBarState=""
if [ "$menuBarState" = hidden ]; then
  MENU_BAR_NOTE=" (the frontmost app is in full screen, which hides the menu bar while the status item goes on reporting the position it would occupy, so the synthetic clicks this probe needs land in that app instead; leave full screen and run the gate again)"

# A named cause beats a guess.
#
# The two notes above are appended to any failure they could plausibly explain,
# which is right while the cause is unknown and wrong the moment it is not.
# This one names itself: two processes called Standfast, because the gate
# launches its own copy beside whatever the operator already has running, and
# System Events refuses to choose between them. Telling that reader to unlock a
# Mac that is not locked, and to leave a full screen they are not in, costs the
# one thing a diagnostic exists to save.
diagnosis() {
  case "$1" in
    *"ambiguous Accessibility process name"*)
      printf '%s' " (another copy of Standfast is running and the gate launched its own; System Events will not choose between two processes of the same name. Quit the other one — usually the copy in ~/Applications — and run the gate again)"
      ;;
    *) printf '%s%s' "$SESSION_LOCK_NOTE" "$MENU_BAR_NOTE" ;;
  esac
}
fi

echo "==> Reading the menu (Accessibility coverage is required)"
# Menu bar 2, not 1: an agent app still gets a main menu bar it never shows,
# and that is the one holding the Apple menu. Status items live in the second.
menuStatus=0
menu="$(CHECK_PID="$PID" CHECK_CLICK_TOOL="$AX_CLICK_TOOL" \
  osascript 2>"$AX_STDERR_FILE" <<'APPLESCRIPT'
on clickCentre(elementPosition, elementSize)
  set clickTool to system attribute "CHECK_CLICK_TOOL"
  if clickTool is "" then error "the lifecycle probe has no click helper"
  set centreX to ((item 1 of elementPosition) + ((item 1 of elementSize) / 2)) as integer
  set centreY to ((item 2 of elementPosition) + ((item 2 of elementSize) / 2)) as integer
  do shell script quoted form of clickTool & " " & centreX & " " & centreY
end clickCentre

-- Geometry, not `AXSelected`. A status item reports itself selected for an
-- `AXPress` that never opened anything, so only a menu with real on-screen
-- size proves the menu is tracking and can receive a click.
on menuIsTracking(statusItem)
  tell application "System Events"
    try
      set menuSize to size of menu 1 of statusItem
    on error
      return false
    end try
    if menuSize is missing value then return false
    if (count of menuSize) is not 2 then return false
    return ((item 1 of menuSize) > 0) and ((item 2 of menuSize) > 0)
  end tell
end menuIsTracking

tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  set targetProcessCount to count of (every application process whose unix id is targetPID)
  if targetProcessCount is not 1 then
    error "supplied PID does not identify exactly one Accessibility application process: " & targetPID
  end if
  set targetSystemEventsID to id of first application process whose unix id is targetPID
  set targetProcess to a reference to application process id targetSystemEventsID
  set resolvedPID to unix id of targetProcess as integer
  if resolvedPID is not targetPID then
    error "System Events resolved another process for PID " & targetPID
  end if
  set targetProcessName to name of targetProcess as text
  set homonymousProcessCount to count of (every application process whose name is targetProcessName)
  if homonymousProcessCount is not 1 then
    error "refusing ambiguous Accessibility process name: " & targetProcessName
  end if
  tell targetProcess
    set auditedPID to unix id as integer
    if auditedPID is not targetPID then
      error "Accessibility process identity changed before the menu audit"
    end if
    if not (exists menu bar item 1 of menu bar 2) then return ""
      set pollAttemptLimit to 50
      set pollDelaySeconds to 0.1
      set statusItem to menu bar item 1 of menu bar 2
      set menuClosedBeforePress to false
      try
        if my menuIsTracking(statusItem) then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (my menuIsTracking(statusItem))
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before the opening click"
      end if
      my clickCentre(position of statusItem, size of statusItem)
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to my menuIsTracking(statusItem)
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not begin tracking after a real click on the status item"
    end if
      set targetMenu to menu 1 of statusItem
      set menuItemCount to count of menu items of targetMenu
      if menuItemCount is 0 then error "exposed status menu has no native items"
      set menuRecords to {}
      repeat with menuItemIndex from 1 to menuItemCount
        set candidateMenuItem to a reference to menu item menuItemIndex of targetMenu
        set menuItemRole to role of candidateMenuItem as text
        if menuItemRole is not "AXMenuItem" then
          error "unexpected native status-menu role: " & menuItemRole
        end if
        set rawMenuItemName to name of candidateMenuItem
        set menuItemName to ""
        if rawMenuItemName is not missing value then
          set menuItemName to rawMenuItemName as text
        end if
        set menuItemEnabled to enabled of candidateMenuItem
        set menuItemHasSubmenu to exists menu 1 of candidateMenuItem
        if menuItemName is "" then
          if menuItemEnabled or menuItemHasSubmenu then
            error "unnamed native status-menu item is not a separator"
          end if
        else
          if menuItemHasSubmenu then
            set recordType to "runner"
          else
            set recordType to "static"
          end if
          set end of menuRecords to recordType & tab & menuItemName
        end if
      end repeat
      perform action "AXCancel" of targetMenu
      set menuClosedAfterCancel to false
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedAfterCancel to not (my menuIsTracking(statusItem))
        on error
          set menuClosedAfterCancel to false
        end try
        if menuClosedAfterCancel then exit repeat
        delay pollDelaySeconds
    end repeat
    if not menuClosedAfterCancel then error "status menu did not close after AXCancel"
    set previousDelimiters to text item delimiters of AppleScript
    set text item delimiters of AppleScript to linefeed
    set joinedMenuRecords to menuRecords as text
    set text item delimiters of AppleScript to previousDelimiters
    set finalResolvedPID to unix id as integer
    if finalResolvedPID is not targetPID then
      error "Accessibility process identity changed during the menu audit"
    end if
    return joinedMenuRecords
  end tell
end tell
APPLESCRIPT
)" || menuStatus=$?
menuError="$(<"$AX_STDERR_FILE")"
if [ "$menuStatus" -ne 0 ]; then
  fail "Accessibility coverage is required, but the status menu could not be read: ${menuError:-osascript exited with status $menuStatus}$(diagnosis "$menuError")"
fi
if [ -z "$menu" ]; then
  if [ -n "$menuError" ]; then
    fail "Accessibility coverage is required, but the status menu could not be read: $menuError$(diagnosis "$menuError")"
  fi
  fail "Accessibility coverage is required, but the status menu could not be read$(diagnosis "$menuError")"
fi
if [ -n "$menuError" ]; then
  printf '    osascript warning: %s\n' "$menuError" >&2
fi

echo "    menu records: $menu"
# Only direct top-level records are covered here. Runner titles are user data,
# so raw localization-key checks apply exclusively to AX-typed static rows;
# submenu and catalogue traversal belongs to a separate runtime gate.
staticMenu=""
runnerMenu=""
while IFS= read -r menuRecord || [ -n "$menuRecord" ]; do
  case "$menuRecord" in
    static$'\t'*)
      staticText="${menuRecord#*$'\t'}"
      [ -n "$staticText" ] \
        || fail "empty static AX menu record"
      if printf '%s\n' "$staticText" \
        | grep -Eq '(^| — )(menu|state|job|duration|thermal|notification)\.'; then
        fail "raw localization key escaped into static AX menu content: $staticText"
      fi
      case "$staticText" in
        "Fleet — "*|"Flota — "*)
          fail "aggregate Fleet/Flota row escaped into the quick menu: $staticText"
          ;;
      esac
      if [ -n "$staticMenu" ]; then
        staticMenu="$staticMenu"$'\n'"$staticText"
      else
        staticMenu="$staticText"
      fi
      ;;
    runner$'\t'*)
      runnerText="${menuRecord#*$'\t'}"
      [ -n "$runnerText" ] \
        || fail "empty runner AX menu record"
      if [ -n "$runnerMenu" ]; then
        runnerMenu="$runnerMenu"$'\n'"$runnerText"
      else
        runnerMenu="$runnerText"
      fi
      ;;
    *)
      fail "unknown AX menu record type: ${menuRecord:-empty record}"
      ;;
  esac
done <<< "$menu"

if [ -z "$runnerMenu" ]; then
  echo "==> AX COVERAGE REDUCED: zero runner records; runner row identity/state parsing was not exercised" >&2
fi

static_has() {
  printf '%s\n' "$staticMenu" | grep -Fxq -- "$1"
}

englishActionCount=0
spanishActionCount=0
for action in "Open Standfast" "Settings" "Quit"; do
  if static_has "$action"; then
    englishActionCount=$((englishActionCount + 1))
  fi
done
for action in "Abrir Standfast" "Ajustes" "Salir"; do
  if static_has "$action"; then
    spanishActionCount=$((spanishActionCount + 1))
  fi
done

if [ "$englishActionCount" -eq 3 ] && [ "$spanishActionCount" -eq 0 ]; then
  menuLanguage=en
elif [ "$spanishActionCount" -eq 3 ] && [ "$englishActionCount" -eq 0 ]; then
  menuLanguage=es
else
  fail "the packaged menu did not expose one complete English or Spanish static action set"
fi

while IFS= read -r runnerText || [ -n "$runnerText" ]; do
  [ -n "$runnerText" ] || continue
  runnerIdentity="${runnerText% · *}"
  runnerState="${runnerText##* · }"
  validRunnerState=false
  if [ "$menuLanguage" = en ]; then
    case "$runnerState" in
      Ready|Running|Disconnected|Stopped|Starting|Unknown) validRunnerState=true ;;
    esac
  else
    case "$runnerState" in
      Listo|Ejecutando|Desconectado|Detenido|Arrancando|Desconocido)
        validRunnerState=true
        ;;
    esac
  fi
  if [ "$runnerIdentity" = "$runnerText" ] || [ -z "$runnerIdentity" ] \
    || [ "$validRunnerState" != true ]; then
    fail "runner AX menu record has no concrete identity and localized short state: $runnerText"
  fi
  printf '    runner parsed: identity=%s | state=%s\n' \
    "$runnerIdentity" "$runnerState"
done <<< "$runnerMenu"

echo "==> Exercising Control Center and Settings through Accessibility"
: > "$AX_STDERR_FILE"
windowsStatus=0
windows="$(CHECK_PID="$PID" CHECK_LANGUAGE="$menuLanguage" \
  CHECK_CLICK_TOOL="$AX_CLICK_TOOL" osascript 2>"$AX_STDERR_FILE" <<'APPLESCRIPT'
on clickCentre(elementPosition, elementSize)
  set clickTool to system attribute "CHECK_CLICK_TOOL"
  if clickTool is "" then error "the lifecycle probe has no click helper"
  set centreX to ((item 1 of elementPosition) + ((item 1 of elementSize) / 2)) as integer
  set centreY to ((item 2 of elementPosition) + ((item 2 of elementSize) / 2)) as integer
  do shell script quoted form of clickTool & " " & centreX & " " & centreY
end clickCentre

-- Geometry, not `AXSelected`. A status item reports itself selected for an
-- `AXPress` that never opened anything, so only a menu with real on-screen
-- size proves the menu is tracking and can receive a click.
on menuIsTracking(statusItem)
  tell application "System Events"
    try
      set menuSize to size of menu 1 of statusItem
    on error
      return false
    end try
    if menuSize is missing value then return false
    if (count of menuSize) is not 2 then return false
    return ((item 1 of menuSize) > 0) and ((item 2 of menuSize) > 0)
  end tell
end menuIsTracking

tell application "System Events"
  set targetPID to (system attribute "CHECK_PID") as integer
  set menuLanguage to system attribute "CHECK_LANGUAGE"
  if menuLanguage is "en" then
    set controlCenterItemName to "Open Standfast"
    set settingsItemName to "Settings"
  else if menuLanguage is "es" then
    set controlCenterItemName to "Abrir Standfast"
    set settingsItemName to "Ajustes"
  else
    error "unsupported validated menu language: " & menuLanguage
  end if
  set controlWindowIdentifier to "dev.standfast.scene.control-center"
  set settingsWindowIdentifier to "dev.standfast.scene.settings"
  set targetProcessCount to count of (every application process whose unix id is targetPID)
  if targetProcessCount is not 1 then
    error "supplied PID does not identify exactly one Accessibility application process: " & targetPID
  end if
  set targetSystemEventsID to id of first application process whose unix id is targetPID
  set targetProcess to a reference to application process id targetSystemEventsID
  set resolvedPID to unix id of targetProcess as integer
  if resolvedPID is not targetPID then
    error "System Events resolved another process for PID " & targetPID
  end if
  set targetProcessName to name of targetProcess as text
  set homonymousProcessCount to count of (every application process whose name is targetProcessName)
  if homonymousProcessCount is not 1 then
    error "refusing ambiguous Accessibility process name: " & targetProcessName
  end if
  tell targetProcess
    set auditedPID to unix id as integer
    if auditedPID is not targetPID then
      error "Accessibility process identity changed before the lifecycle audit"
    end if
    set pollAttemptLimit to 50
    set pollDelaySeconds to 0.1

    set initialControlWindowCount to 0
    set initialSettingsWindowCount to 0
    repeat with candidateWindow in every window
      try
        set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
        if candidateIdentifier is controlWindowIdentifier then
          set initialControlWindowCount to initialControlWindowCount + 1
        else if candidateIdentifier is settingsWindowIdentifier then
          set initialSettingsWindowCount to initialSettingsWindowCount + 1
        end if
      end try
    end repeat
    set targetsInitialAbsent to initialControlWindowCount is 0 and initialSettingsWindowCount is 0
    if not targetsInitialAbsent then
      error "identified Control Center or Settings window already existed before the lifecycle probe"
    end if
    set baselineWindows to {}
    repeat with candidateWindow in every window
      set end of baselineWindows to contents of candidateWindow
    end repeat
    set baselineWindowCount to count of baselineWindows

      set statusItem to menu bar item 1 of menu bar 2
      set menuClosedBeforePress to false
      try
        if my menuIsTracking(statusItem) then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (my menuIsTracking(statusItem))
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before the Control Center opening click"
      end if
      my clickCentre(position of statusItem, size of statusItem)
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to my menuIsTracking(statusItem)
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not begin tracking for Control Center after a real click on the status item"
      end if
      set targetMenu to menu 1 of statusItem
      set menuItemCount to count of menu items of targetMenu
      if menuItemCount is 0 then error "exposed Control Center menu has no native items"
      set targetItemName to controlCenterItemName
      set targetMenuItemIndex to 0
      set targetMenuItemMatchCount to 0
      repeat with menuItemIndex from 1 to menuItemCount
        set candidateMenuItem to a reference to menu item menuItemIndex of targetMenu
        if (role of candidateMenuItem as text) is not "AXMenuItem" then
          error "unexpected native Control Center menu-item role"
        end if
        set rawMenuItemName to name of candidateMenuItem
        set menuItemName to ""
        if rawMenuItemName is not missing value then
          set menuItemName to rawMenuItemName as text
        end if
        set menuItemEnabled to enabled of candidateMenuItem
        set menuItemHasSubmenu to exists menu 1 of candidateMenuItem
        if menuItemName is "" then
          if menuItemEnabled or menuItemHasSubmenu then
            error "unnamed Control Center menu item is not a separator"
          end if
        else
          if menuItemName is targetItemName and not (exists menu 1 of candidateMenuItem) then
            set targetMenuItemMatchCount to targetMenuItemMatchCount + 1
            set targetMenuItemIndex to menuItemIndex as integer
          end if
        end if
      end repeat
    if targetMenuItemMatchCount is not 1 then error "Control Center menu action missing or ambiguous"
    set targetMenuItem to a reference to menu item targetMenuItemIndex of targetMenu
    if (role of targetMenuItem as text) is not "AXMenuItem" then error "Control Center action has unexpected role"
    if (name of targetMenuItem as text) is not targetItemName then error "Control Center action changed before the click"
    if exists menu 1 of targetMenuItem then error "Control Center action became a submenu"
    if not (enabled of targetMenuItem) then error "Control Center action is disabled"
    my clickCentre(position of targetMenuItem, size of targetMenuItem)

    set controlWindow to missing value
    set controlOpened to false
    set controlMainInitially to false
    set controlFocusedInitially to false
    set settingsAbsentAfterInitialControl to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlWindow to missing value
      set controlMatchCount to 0
      set settingsMatchCount to 0
      set controlMainInitially to false
      set controlFocusedInitially to false
      repeat with candidateWindow in every window
        try
          set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
          if candidateIdentifier is controlWindowIdentifier then
            set controlMatchCount to controlMatchCount + 1
            if controlWindow is missing value then set controlWindow to contents of candidateWindow
          else if candidateIdentifier is settingsWindowIdentifier then
            set settingsMatchCount to settingsMatchCount + 1
          end if
        end try
      end repeat
      set controlOpened to controlMatchCount is 1
      set settingsAbsentAfterInitialControl to settingsMatchCount is 0
      if controlOpened then
        try
          set controlMainInitially to value of attribute "AXMain" of controlWindow as boolean
          set controlFocusedInitially to value of attribute "AXFocused" of controlWindow as boolean
        end try
      end if
      if controlOpened and settingsAbsentAfterInitialControl and controlMainInitially and controlFocusedInitially then exit repeat
      delay pollDelaySeconds
    end repeat
    if not controlOpened then
      error "Control Center action produced no window with AXIdentifier " & controlWindowIdentifier & " after a real click on a tracking menu, so the app never opened the scene"
    end if
    if not settingsAbsentAfterInitialControl then
      error "Settings window appeared while opening the initial Control Center window"
    end if
    if not controlMainInitially or not controlFocusedInitially then
      error "identified Control Center window did not become main and focused"
    end if

      set menuClosedBeforePress to false
      try
        if my menuIsTracking(statusItem) then
          perform action "AXCancel" of menu 1 of statusItem
        end if
      end try
      repeat with pollAttempt from 1 to pollAttemptLimit
        try
          set menuClosedBeforePress to not (my menuIsTracking(statusItem))
        on error
          set menuClosedBeforePress to false
        end try
        if menuClosedBeforePress then exit repeat
        delay pollDelaySeconds
      end repeat
      if not menuClosedBeforePress then
        error "status menu did not become closed before the Settings opening click"
      end if
      my clickCentre(position of statusItem, size of statusItem)
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to my menuIsTracking(statusItem)
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not begin tracking for Settings after a real click on the status item"
      end if
      set targetMenu to menu 1 of statusItem
      set menuItemCount to count of menu items of targetMenu
      if menuItemCount is 0 then error "exposed Settings menu has no native items"
      set targetItemName to settingsItemName
      set targetMenuItemIndex to 0
      set targetMenuItemMatchCount to 0
      repeat with menuItemIndex from 1 to menuItemCount
        set candidateMenuItem to a reference to menu item menuItemIndex of targetMenu
        if (role of candidateMenuItem as text) is not "AXMenuItem" then
          error "unexpected native Settings menu-item role"
        end if
        set rawMenuItemName to name of candidateMenuItem
        set menuItemName to ""
        if rawMenuItemName is not missing value then
          set menuItemName to rawMenuItemName as text
        end if
        set menuItemEnabled to enabled of candidateMenuItem
        set menuItemHasSubmenu to exists menu 1 of candidateMenuItem
        if menuItemName is "" then
          if menuItemEnabled or menuItemHasSubmenu then
            error "unnamed Settings menu item is not a separator"
          end if
        else
          if menuItemName is targetItemName and not (exists menu 1 of candidateMenuItem) then
            set targetMenuItemMatchCount to targetMenuItemMatchCount + 1
            set targetMenuItemIndex to menuItemIndex as integer
          end if
        end if
      end repeat
    if targetMenuItemMatchCount is not 1 then error "Settings menu action missing or ambiguous"
    set targetMenuItem to a reference to menu item targetMenuItemIndex of targetMenu
    if (role of targetMenuItem as text) is not "AXMenuItem" then error "Settings action has unexpected role"
    if (name of targetMenuItem as text) is not targetItemName then error "Settings action changed before the click"
    if exists menu 1 of targetMenuItem then error "Settings action became a submenu"
    if not (enabled of targetMenuItem) then error "Settings action is disabled"
    my clickCentre(position of targetMenuItem, size of targetMenuItem)

    set settingsWindow to missing value
    set settingsOpened to false
    set controlRetainedForSettings to false
    set settingsMainAfterControl to false
    set settingsFocusedAfterControl to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlWindow to missing value
      set settingsWindow to missing value
      set controlMatchCount to 0
      set settingsMatchCount to 0
      set settingsMainAfterControl to false
      set settingsFocusedAfterControl to false
      repeat with candidateWindow in every window
        try
          set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
          if candidateIdentifier is controlWindowIdentifier then
            set controlMatchCount to controlMatchCount + 1
            if controlWindow is missing value then set controlWindow to contents of candidateWindow
          else if candidateIdentifier is settingsWindowIdentifier then
            set settingsMatchCount to settingsMatchCount + 1
            if settingsWindow is missing value then set settingsWindow to contents of candidateWindow
          end if
        end try
      end repeat
      set controlRetainedForSettings to controlMatchCount is 1
      set settingsOpened to settingsMatchCount is 1
      if settingsOpened then
        try
          set settingsMainAfterControl to value of attribute "AXMain" of settingsWindow as boolean
          set settingsFocusedAfterControl to value of attribute "AXFocused" of settingsWindow as boolean
        end try
      end if
      if controlRetainedForSettings and settingsOpened and settingsMainAfterControl and settingsFocusedAfterControl then exit repeat
      delay pollDelaySeconds
    end repeat
    if not settingsOpened then
      error "Settings action produced no window with AXIdentifier " & settingsWindowIdentifier & " after a real click on a tracking menu, so the app never opened the scene"
    end if
    if not controlRetainedForSettings then
      error "Control Center window was lost while opening Settings"
    end if
    if not settingsMainAfterControl or not settingsFocusedAfterControl then
      error "identified Settings window did not become main and focused after Control Center"
    end if

    set requiredSettingsIdentifiers to {¬
      "dev.standfast.settings.notifications.job-failed", ¬
      "dev.standfast.settings.notifications.disconnected", ¬
      "dev.standfast.settings.notifications.stopped", ¬
      "dev.standfast.settings.power.prevent-sleep", ¬
      "dev.standfast.settings.startup.open-at-login", ¬
      "dev.standfast.settings.version"}
    set settingsIdentifierRecords to {}
    set settingsIdentifiersReady to false
    repeat with settingsPollAttempt from 1 to pollAttemptLimit
      set settingsIdentifierRecords to {}
      set settingsElements to {}
      try
        set settingsElements to entire contents of settingsWindow
      end try
      repeat with settingsElement in settingsElements
        try
          set settingsIdentifier to value of attribute "AXIdentifier" of settingsElement as text
          if requiredSettingsIdentifiers contains settingsIdentifier then
            set end of settingsIdentifierRecords to "settings" & tab & settingsIdentifier
          end if
        end try
      end repeat
      set settingsIdentifiersReady to true
      repeat with requiredSettingsIdentifier in requiredSettingsIdentifiers
        set requiredSettingsRecord to "settings" & tab & (requiredSettingsIdentifier as text)
        set settingsIdentifierCount to 0
        repeat with settingsIdentifierRecord in settingsIdentifierRecords
          if (contents of settingsIdentifierRecord) is requiredSettingsRecord then
            set settingsIdentifierCount to settingsIdentifierCount + 1
          end if
        end repeat
        if settingsIdentifierCount is not 1 then
          set settingsIdentifiersReady to false
        end if
      end repeat
      if settingsIdentifiersReady then exit repeat
      delay pollDelaySeconds
    end repeat

    set menuClosedBeforePress to false
    try
      if my menuIsTracking(statusItem) then
        perform action "AXCancel" of menu 1 of statusItem
      end if
    end try
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuClosedBeforePress to not (my menuIsTracking(statusItem))
      on error
        set menuClosedBeforePress to false
      end try
      if menuClosedBeforePress then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuClosedBeforePress then
      error "status menu did not become closed before the Control Center return click"
    end if
    my clickCentre(position of statusItem, size of statusItem)
    set menuExposed to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      try
        set menuExposed to my menuIsTracking(statusItem)
      on error
        set menuExposed to false
      end try
      if menuExposed then exit repeat
      delay pollDelaySeconds
    end repeat
    if not menuExposed then
      error "status menu did not begin tracking for the Control Center return after a real click on the status item"
    end if
    set targetMenu to menu 1 of statusItem
    set menuItemCount to count of menu items of targetMenu
    if menuItemCount is 0 then error "exposed Control Center return menu has no native items"
    set targetItemName to controlCenterItemName
    set targetMenuItemIndex to 0
    set targetMenuItemMatchCount to 0
    repeat with menuItemIndex from 1 to menuItemCount
      set candidateMenuItem to a reference to menu item menuItemIndex of targetMenu
      if (role of candidateMenuItem as text) is not "AXMenuItem" then
        error "unexpected native Control Center return menu-item role"
      end if
      set rawMenuItemName to name of candidateMenuItem
      set menuItemName to ""
      if rawMenuItemName is not missing value then
        set menuItemName to rawMenuItemName as text
      end if
      set menuItemEnabled to enabled of candidateMenuItem
      set menuItemHasSubmenu to exists menu 1 of candidateMenuItem
      if menuItemName is "" then
        if menuItemEnabled or menuItemHasSubmenu then
          error "unnamed Control Center return menu item is not a separator"
        end if
      else
        if menuItemName is targetItemName and not (exists menu 1 of candidateMenuItem) then
          set targetMenuItemMatchCount to targetMenuItemMatchCount + 1
          set targetMenuItemIndex to menuItemIndex as integer
        end if
      end if
    end repeat
    if targetMenuItemMatchCount is not 1 then error "Control Center return action missing or ambiguous"
    set targetMenuItem to a reference to menu item targetMenuItemIndex of targetMenu
    if (role of targetMenuItem as text) is not "AXMenuItem" then error "Control Center return action has unexpected role"
    if (name of targetMenuItem as text) is not targetItemName then error "Control Center return action changed before the click"
    if exists menu 1 of targetMenuItem then error "Control Center return action became a submenu"
    if not (enabled of targetMenuItem) then error "Control Center return action is disabled"
    my clickCentre(position of targetMenuItem, size of targetMenuItem)

    set controlReturned to false
    set settingsRetainedForControl to false
    set controlMainAfterSettings to false
    set controlFocusedAfterSettings to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlWindow to missing value
      set settingsWindow to missing value
      set controlMatchCount to 0
      set settingsMatchCount to 0
      set controlMainAfterSettings to false
      set controlFocusedAfterSettings to false
      repeat with candidateWindow in every window
        try
          set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
          if candidateIdentifier is controlWindowIdentifier then
            set controlMatchCount to controlMatchCount + 1
            if controlWindow is missing value then set controlWindow to contents of candidateWindow
          else if candidateIdentifier is settingsWindowIdentifier then
            set settingsMatchCount to settingsMatchCount + 1
            if settingsWindow is missing value then set settingsWindow to contents of candidateWindow
          end if
        end try
      end repeat
      set controlReturned to controlMatchCount is 1
      set settingsRetainedForControl to settingsMatchCount is 1
      if controlReturned then
        try
          set controlMainAfterSettings to value of attribute "AXMain" of controlWindow as boolean
          set controlFocusedAfterSettings to value of attribute "AXFocused" of controlWindow as boolean
        end try
      end if
      if controlReturned and settingsRetainedForControl and controlMainAfterSettings and controlFocusedAfterSettings then exit repeat
      delay pollDelaySeconds
    end repeat
    if not controlReturned then
      error "Control Center action did not return the identified window without duplication"
    end if
    if not settingsRetainedForControl then
      error "Settings window was lost while returning to Control Center"
    end if
    if not controlMainAfterSettings or not controlFocusedAfterSettings then
      error "identified Control Center window did not become main and focused after Settings"
    end if

    set closeButtons to every button of controlWindow whose subrole is "AXCloseButton"
    if (count of closeButtons) is 0 then error "Control Center close button missing"
    set closeButton to item 1 of closeButtons
    perform action "AXPress" of closeButton

    set controlClosed to false
    set settingsRetainedAfterControlClose to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlMatchCount to 0
      set settingsMatchCount to 0
      set settingsWindow to missing value
      repeat with candidateWindow in every window
        try
          set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
          if candidateIdentifier is controlWindowIdentifier then
            set controlMatchCount to controlMatchCount + 1
          else if candidateIdentifier is settingsWindowIdentifier then
            set settingsMatchCount to settingsMatchCount + 1
            if settingsWindow is missing value then set settingsWindow to contents of candidateWindow
          end if
        end try
      end repeat
      set controlClosed to controlMatchCount is 0
      set settingsRetainedAfterControlClose to settingsMatchCount is 1
      if controlClosed and settingsRetainedAfterControlClose then exit repeat
      delay pollDelaySeconds
    end repeat
    if not controlClosed then error "identified Control Center window did not close"
    if not settingsRetainedAfterControlClose then
      error "closing Control Center also removed or duplicated the Settings window"
    end if

    set closeButtons to every button of settingsWindow whose subrole is "AXCloseButton"
    if (count of closeButtons) is 0 then error "Settings close button missing"
    set closeButton to item 1 of closeButtons
    perform action "AXPress" of closeButton

    set settingsClosed to false
    set remainingTargetWindows to 2
    set unrelatedWindowsPreserved to false
    repeat with pollAttempt from 1 to pollAttemptLimit
      set controlMatchCount to 0
      set settingsMatchCount to 0
      set currentWindows to every window
      repeat with candidateWindow in currentWindows
        try
          set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow as text
          if candidateIdentifier is controlWindowIdentifier then
            set controlMatchCount to controlMatchCount + 1
          else if candidateIdentifier is settingsWindowIdentifier then
            set settingsMatchCount to settingsMatchCount + 1
          end if
        end try
      end repeat
      set settingsClosed to settingsMatchCount is 0
      set remainingTargetWindows to controlMatchCount + settingsMatchCount
      set baselineWindowsPreserved to true
      repeat with baselineWindow in baselineWindows
        set baselineWindowStillPresent to false
        repeat with candidateWindow in currentWindows
          if (contents of candidateWindow) is (contents of baselineWindow) then
            set baselineWindowStillPresent to true
            exit repeat
          end if
        end repeat
        if not baselineWindowStillPresent then
          set baselineWindowsPreserved to false
          exit repeat
        end if
      end repeat
      set unrelatedWindowsPreserved to baselineWindowsPreserved and ((count of currentWindows) is baselineWindowCount)
      if settingsClosed and remainingTargetWindows is 0 and unrelatedWindowsPreserved then exit repeat
      delay pollDelaySeconds
    end repeat

    set statusItemAlive to exists menu bar item 1 of menu bar 2
    set finalResolvedPID to unix id as integer
    if finalResolvedPID is not targetPID then
      error "Accessibility process identity changed during the lifecycle audit"
    end if
    set lifecycleRecord to (targetsInitialAbsent as text) & "|" & (controlOpened as text) & "|" & ¬
      (controlMainInitially as text) & "|" & (controlFocusedInitially as text) & "|" & ¬
      (settingsAbsentAfterInitialControl as text) & "|" & (settingsOpened as text) & "|" & ¬
      (controlRetainedForSettings as text) & "|" & ¬
      (settingsMainAfterControl as text) & "|" & (settingsFocusedAfterControl as text) & "|" & ¬
      (controlReturned as text) & "|" & (settingsRetainedForControl as text) & "|" & ¬
      (controlMainAfterSettings as text) & "|" & (controlFocusedAfterSettings as text) & "|" & ¬
      (controlClosed as text) & "|" & (settingsRetainedAfterControlClose as text) & "|" & ¬
      (settingsClosed as text) & "|" & (remainingTargetWindows as text) & "|" & ¬
      (unrelatedWindowsPreserved as text) & "|" & (statusItemAlive as text)
    set previousDelimiters to text item delimiters of AppleScript
    set text item delimiters of AppleScript to linefeed
    set settingsRecordsText to settingsIdentifierRecords as text
    set text item delimiters of AppleScript to previousDelimiters
    return lifecycleRecord & linefeed & settingsRecordsText
  end tell
end tell
APPLESCRIPT
)" || windowsStatus=$?
windowsError="$(<"$AX_STDERR_FILE")"
if [ "$windowsStatus" -ne 0 ]; then
  fail "Accessibility lifecycle probe aborted: ${windowsError:-osascript exited with status $windowsStatus}$(diagnosis "$windowsError")"
fi
if [ -n "$windowsError" ]; then
  printf '    osascript warning: %s\n' "$windowsError" >&2
fi

targetsInitialAbsent=""
controlOpened=""
controlMainInitially=""
controlFocusedInitially=""
settingsAbsentAfterInitialControl=""
settingsOpened=""
controlRetainedForSettings=""
settingsMainAfterControl=""
settingsFocusedAfterControl=""
controlReturned=""
settingsRetainedForControl=""
controlMainAfterSettings=""
controlFocusedAfterSettings=""
controlClosed=""
settingsRetainedAfterControlClose=""
settingsClosed=""
remainingTargetWindows=""
unrelatedWindowsPreserved=""
statusItemAlive=""
settingsRecords=""
case "$windows" in
  *$'\n'*)
    lifecycleRecord="${windows%%$'\n'*}"
    settingsRecords="${windows#*$'\n'}"
    ;;
  *) lifecycleRecord="$windows" ;;
esac
IFS='|' read -r targetsInitialAbsent controlOpened controlMainInitially \
  controlFocusedInitially settingsAbsentAfterInitialControl settingsOpened \
  controlRetainedForSettings \
  settingsMainAfterControl settingsFocusedAfterControl controlReturned \
  settingsRetainedForControl controlMainAfterSettings controlFocusedAfterSettings \
  controlClosed settingsRetainedAfterControlClose settingsClosed \
  remainingTargetWindows unrelatedWindowsPreserved statusItemAlive \
  <<< "$lifecycleRecord" || true

settingsMenu=""
if [ -n "$settingsRecords" ]; then
  while IFS= read -r settingsRecord || [ -n "$settingsRecord" ]; do
    case "$settingsRecord" in
      settings$'\t'*)
        settingsIdentifier="${settingsRecord#*$'\t'}"
        [ -n "$settingsIdentifier" ] \
          || fail "empty Settings AX identifier record"
        if [ -n "$settingsMenu" ]; then
          settingsMenu="$settingsMenu"$'\n'"$settingsIdentifier"
        else
          settingsMenu="$settingsIdentifier"
        fi
        ;;
      *)
        fail "unknown Settings AX record type: ${settingsRecord:-empty record}"
        ;;
    esac
  done <<< "$settingsRecords"
fi

missingSettingsIdentifiers=""
duplicateSettingsIdentifiers=""
for requiredSettingsIdentifier in \
  dev.standfast.settings.notifications.job-failed \
  dev.standfast.settings.notifications.disconnected \
  dev.standfast.settings.notifications.stopped \
  dev.standfast.settings.power.prevent-sleep \
  dev.standfast.settings.startup.open-at-login \
  dev.standfast.settings.version
do
  settingsIdentifierCount="$(
    printf '%s\n' "$settingsMenu" \
      | grep -Fxc -- "$requiredSettingsIdentifier" || true
  )"
  if [ "$settingsIdentifierCount" -eq 0 ]; then
    if [ -n "$missingSettingsIdentifiers" ]; then
      missingSettingsIdentifiers="$missingSettingsIdentifiers,$requiredSettingsIdentifier"
    else
      missingSettingsIdentifiers="$requiredSettingsIdentifier"
    fi
  elif [ "$settingsIdentifierCount" -ne 1 ]; then
    duplicateSettingsIdentifier="$requiredSettingsIdentifier($settingsIdentifierCount)"
    if [ -n "$duplicateSettingsIdentifiers" ]; then
      duplicateSettingsIdentifiers="$duplicateSettingsIdentifiers,$duplicateSettingsIdentifier"
    else
      duplicateSettingsIdentifiers="$duplicateSettingsIdentifier"
    fi
  fi
done
if [ -n "$missingSettingsIdentifiers" ] || [ -n "$duplicateSettingsIdentifiers" ]; then
  [ -n "$missingSettingsIdentifiers" ] || missingSettingsIdentifiers=none
  [ -n "$duplicateSettingsIdentifiers" ] || duplicateSettingsIdentifiers=none
  fail "Settings AX identifiers not ready before timeout: missing=$missingSettingsIdentifiers; duplicates=$duplicateSettingsIdentifiers"
fi

if [ "$targetsInitialAbsent" = true ] && [ "$controlOpened" = true ] \
  && [ "$controlMainInitially" = true ] && [ "$controlFocusedInitially" = true ] \
  && [ "$settingsAbsentAfterInitialControl" = true ] \
  && [ "$settingsOpened" = true ] && [ "$controlRetainedForSettings" = true ] \
  && [ "$settingsMainAfterControl" = true ] \
  && [ "$settingsFocusedAfterControl" = true ] \
  && [ "$controlReturned" = true ] && [ "$settingsRetainedForControl" = true ] \
  && [ "$controlMainAfterSettings" = true ] \
  && [ "$controlFocusedAfterSettings" = true ] \
  && [ "$controlClosed" = true ] \
  && [ "$settingsRetainedAfterControlClose" = true ] \
  && [ "$settingsClosed" = true ] && [ "$remainingTargetWindows" = 0 ] \
  && [ "$unrelatedWindowsPreserved" = true ] && [ "$statusItemAlive" = true ]; then
  echo "    identified Control Center/Settings focus transitions and targeted closure passed"
else
  failure="window lifecycle AX check failed: targetsInitialAbsent=${targetsInitialAbsent:-missing}, controlOpened=${controlOpened:-missing}, controlMainInitially=${controlMainInitially:-missing}, controlFocusedInitially=${controlFocusedInitially:-missing}, settingsAbsentAfterInitialControl=${settingsAbsentAfterInitialControl:-missing}, settingsOpened=${settingsOpened:-missing}, controlRetainedForSettings=${controlRetainedForSettings:-missing}, settingsMainAfterControl=${settingsMainAfterControl:-missing}, settingsFocusedAfterControl=${settingsFocusedAfterControl:-missing}, controlReturned=${controlReturned:-missing}, settingsRetainedForControl=${settingsRetainedForControl:-missing}, controlMainAfterSettings=${controlMainAfterSettings:-missing}, controlFocusedAfterSettings=${controlFocusedAfterSettings:-missing}, controlClosed=${controlClosed:-missing}, settingsRetainedAfterControlClose=${settingsRetainedAfterControlClose:-missing}, settingsClosed=${settingsClosed:-missing}, remainingTargetWindows=${remainingTargetWindows:-missing}, unrelatedWindowsPreserved=${unrelatedWindowsPreserved:-missing}, statusItemAlive=${statusItemAlive:-missing}"
  fail "$failure"
fi

kill -0 "$PID" 2>/dev/null \
  || fail "closing the identified windows terminated the menu-bar process"
