#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AX_CHECK="$ROOT/Scripts/check-app-ax.sh"
QUICK_MENU="$ROOT/Sources/Standfast/QuickMenuView.swift"
SCENE_ACTIVATION="$ROOT/Sources/Standfast/SceneActivationCoordinator.swift"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/standfast-ax-contract.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
SENTINEL="$TEST_ROOT/osascript-called"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  case "$output" in
    *"$expected"*) ;;
    *) fail "output did not contain: $expected" ;;
  esac
}

assert_status_open_transitions() {
  local script="$1"
  local expected="$2"
  local label="$3"
  local transition_count
  transition_count="$(awk '
    stage == 0 && /set menuClosedBeforePress to false/ { stage = 1; next }
    stage == 1 && /set menuClosedBeforePress to not \(selected of statusItem\)/ {
      stage = 2
      next
    }
    stage == 2 && /if not menuClosedBeforePress then/ { stage = 3; next }
    stage == 3 && /perform action "AXPress" of statusItem/ {
      count += 1
      stage = 0
    }
    END { print count + 0 }
  ' "$script")"
  [ "$transition_count" -eq "$expected" ] \
    || fail "$label must prove a closed-to-exposed transition before every AXPress"
}

mkdir -p "$FAKE_BIN"
printf '%s\n' \
  '#!/bin/bash' \
  ': > "$STANDFAST_OSASCRIPT_SENTINEL"' \
  '[ -z "${STANDFAST_OSASCRIPT_ERROR_MESSAGE:-}" ] || printf "%s\n" "$STANDFAST_OSASCRIPT_ERROR_MESSAGE" >&2' \
  'if [ -n "${STANDFAST_OSASCRIPT_CAPTURE_DIR:-}" ]; then' \
  '  count_file="$STANDFAST_OSASCRIPT_CAPTURE_DIR/count"' \
  '  call_count=0' \
  '  [ ! -f "$count_file" ] || call_count="$(cat "$count_file")"' \
  '  call_count=$((call_count + 1))' \
  '  printf "%s\n" "$call_count" > "$count_file"' \
  '  cat > "$STANDFAST_OSASCRIPT_CAPTURE_DIR/call-$call_count.applescript"' \
  '  case "$call_count" in' \
  '    1) printf "%b\n" "${STANDFAST_OSASCRIPT_MENU_OUTPUT:-Fleet idle\nOpen Standfast\nSettings\nQuit}" ;;' \
  '    2)' \
  '      [ "${STANDFAST_OSASCRIPT_LIFECYCLE_ABORT:-0}" != 1 ] || exit 1' \
  '      printf "%s\n" "${STANDFAST_OSASCRIPT_LIFECYCLE_TUPLE:-true|true|true|true|true|true|true|true|true|true|true|0|true}"' \
  '      ;;' \
  '  esac' \
  'fi' \
  'exit 0' > "$FAKE_BIN/osascript"
chmod +x "$FAKE_BIN/osascript"

invalid_output=""
if invalid_output="$(STANDFAST_AX_MODE=maybe "$AX_CHECK" --validate 2>&1)"; then
  fail "an invalid STANDFAST_AX_MODE was accepted"
fi
assert_contains "$invalid_output" "STANDFAST_AX_MODE must be require or skip"

require_output=""
if require_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" "$AX_CHECK" "$$" 2>&1
)"; then
  fail "require mode passed without a readable menu"
fi
assert_contains "$require_output" "Accessibility coverage is required"
[ -f "$SENTINEL" ] || fail "require mode did not attempt the AX read"

rm -f "$SENTINEL"
default_output=""
if default_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    env -u STANDFAST_AX_MODE "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the default mode passed without a readable menu"
fi
assert_contains "$default_output" "Accessibility coverage is required"
[ -f "$SENTINEL" ] || fail "the default mode did not attempt the AX read"

rm -f "$SENTINEL"
diagnostic_output=""
if diagnostic_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_ERROR_MESSAGE="synthetic AX diagnostic" \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "require mode passed without a readable menu"
fi
assert_contains "$diagnostic_output" "synthetic AX diagnostic"

rm -f "$SENTINEL"
skip_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=skip \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$skip_output" "AX COVERAGE SKIPPED"
assert_contains "$skip_output" "menu, windows, and Accessibility are NOT COVERED"
[ ! -e "$SENTINEL" ] || fail "skip mode invoked osascript"

capture_dir="$TEST_ROOT/captured"
mkdir -p "$capture_dir"
lifecycle_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$capture_dir" \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$lifecycle_output" \
  "singleton main/focused Control Center and Settings lifecycle passed"

warning_dir="$TEST_ROOT/captured-benign-warning"
mkdir -p "$warning_dir"
warning_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$warning_dir" \
    STANDFAST_OSASCRIPT_ERROR_MESSAGE="synthetic benign AX warning" \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$warning_output" "synthetic benign AX warning"
assert_contains "$warning_output" \
  "singleton main/focused Control Center and Settings lifecycle passed"

key_like_runner_dir="$TEST_ROOT/captured-key-like-runner"
mkdir -p "$key_like_runner_dir"
key_like_runner_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$key_like_runner_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='state.prod\nOpen Standfast\nSettings\nQuit' \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$key_like_runner_output" \
  "singleton main/focused Control Center and Settings lifecycle passed"

raw_key_dir="$TEST_ROOT/captured-raw-key-menu"
mkdir -p "$raw_key_dir"
raw_key_output=""
if raw_key_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$raw_key_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='state.idle\nmenu.controlCenter\nmenu.settings\nmenu.quit' \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke accepted a menu with no localized static actions"
fi
assert_contains "$raw_key_output" \
  "did not expose the localized Control Center action"
exact_action_check_count="$(grep -Fc 'grep -Fxq' "$AX_CHECK" || true)"
[ "$exact_action_check_count" -eq 3 ] \
  || fail "the AX smoke does not match each localized static action as a whole line"

lifecycle_script="$capture_dir/call-2.applescript"
[ -f "$lifecycle_script" ] || fail "the lifecycle AppleScript was not captured"
menu_script="$capture_dir/call-1.applescript"
[ -f "$menu_script" ] || fail "the menu AppleScript was not captured"
# Everything below is a structural source contract plus an osacompile syntax
# check. It never executes System Events; the unlocked es/en runtime gate owns
# the behavioral proof for selection transitions and window lifecycle.
menu_status_press_count="$(grep -Fc 'perform action "AXPress" of statusItem' "$menu_script" || true)"
[ "$menu_status_press_count" -eq 1 ] \
  || fail "the menu probe does not expose the status menu through AXPress"
grep -Fq 'set menuExposed to selected of statusItem' "$menu_script" \
  || fail "the menu probe does not wait for AXSelected before reading"
grep -Fq 'status menu did not become exposed through AXPress; the GUI session may be locked' \
  "$menu_script" \
  || fail "the menu probe has no causal locked-session diagnostic"
grep -Fq 'value of attribute "AXVisibleChildren" of targetMenu' "$menu_script" \
  || fail "the menu probe reads cached children instead of visible children"
grep -Fq 'set directMenuItems to every menu item of targetMenu' "$menu_script" \
  || fail "the menu probe does not capture the direct AXChildren after exposure"
if grep -Eq 'count of visibleMenuItems.*count of directMenuItems|hidden or stale direct items' \
  "$menu_script"; then
  fail "the menu probe treats visible-child cardinality as a freshness guarantee"
fi
grep -Fq 'repeat with directMenuItem in directMenuItems' "$menu_script" \
  || fail "the menu probe does not enumerate its verified direct AXChildren"
grep -Fq 'set end of names to name of directMenuItem as text' "$menu_script" \
  || fail "the menu probe does not read names from its verified direct AXChildren"
grep -Fq 'set text item delimiters of AppleScript to linefeed' "$menu_script" \
  || fail "the menu probe concatenates adjacent item names without a delimiter"
if grep -Fq 'name of every menu item of targetMenu' "$menu_script"; then
  fail "the menu probe bypasses its verified direct AXChildren list"
fi
assert_status_open_transitions "$menu_script" 1 "the menu probe"
grep -Fq 'set menuClosedAfterCancel to not (selected of statusItem)' "$menu_script" \
  || fail "the menu probe returns before AXCancel has closed the status menu"
grep -Fq 'status menu did not close after AXCancel' "$menu_script" \
  || fail "the menu probe has no causal AXCancel transition diagnostic"
if grep -Fq 'click statusItem' "$menu_script"; then
  fail "the menu probe still uses an unreliable synthetic click"
fi
grep -Fq 'set pollAttemptLimit to 50' "$menu_script" \
  || fail "the menu probe has no bounded polling budget"
grep -Fq 'delay pollDelaySeconds' "$menu_script" \
  || fail "the menu probe does not poll readiness by condition"
if grep -Eq 'delay (1|1\.5|0\.25)$' "$menu_script"; then
  fail "the menu probe still samples readiness after a fixed sleep"
fi
/usr/bin/osacompile -o "$TEST_ROOT/menu.scpt" "$menu_script" \
  >/dev/null || fail "the menu AppleScript does not compile"
lifecycle_status_press_count="$(grep -Fc 'perform action "AXPress" of statusItem' "$lifecycle_script" || true)"
[ "$lifecycle_status_press_count" -eq 2 ] \
  || fail "both lifecycle actions must expose the status menu through AXPress"
lifecycle_exposure_count="$(grep -Fc 'set menuExposed to selected of statusItem' "$lifecycle_script" || true)"
[ "$lifecycle_exposure_count" -eq 2 ] \
  || fail "both lifecycle actions must wait for AXSelected"
assert_status_open_transitions "$lifecycle_script" 2 "both lifecycle actions"
lifecycle_visible_children_count="$(grep -Fc 'value of attribute "AXVisibleChildren" of targetMenu' "$lifecycle_script" || true)"
[ "$lifecycle_visible_children_count" -eq 2 ] \
  || fail "both lifecycle actions must inspect visible children after exposure"
visible_menu_guard_count="$(grep -Fc 'if (count of visibleMenuItems) is 0 then error' "$lifecycle_script" || true)"
[ "$visible_menu_guard_count" -eq 2 ] \
  || fail "both lifecycle actions must reject an exposed menu with no visible children"
direct_menu_capture_count="$(grep -Fc 'set directMenuItems to every menu item of targetMenu' "$lifecycle_script" || true)"
[ "$direct_menu_capture_count" -eq 2 ] \
  || fail "both lifecycle actions must capture direct AXChildren after exposure"
if grep -Eq 'count of visibleMenuItems.*count of directMenuItems|hidden or stale direct items' \
  "$lifecycle_script"; then
  fail "a lifecycle action treats visible-child cardinality as freshness"
fi
direct_menu_loop_count="$(grep -Fc 'repeat with directMenuItem in directMenuItems' "$lifecycle_script" || true)"
[ "$direct_menu_loop_count" -eq 2 ] \
  || fail "both lifecycle actions must search the verified direct AXChildren"
direct_menu_resolution_count="$(grep -Fc 'set targetMenuItem to contents of directMenuItem' "$lifecycle_script" || true)"
[ "$direct_menu_resolution_count" -eq 2 ] \
  || fail "both lifecycle actions must press an item from the verified direct AXChildren"
menu_item_press_count="$(grep -Fc 'perform action "AXPress" of targetMenuItem' "$lifecycle_script" || true)"
[ "$menu_item_press_count" -eq 2 ] \
  || fail "both visible lifecycle menu items must be invoked through AXPress"
if grep -Fq 'click statusItem' "$lifecycle_script"; then
  fail "the lifecycle probe still uses an unreliable synthetic status-item click"
fi
grep -Fq 'Control Center action produced no window after AXPress on an exposed menu' \
  "$lifecycle_script" \
  || fail "the Control Center path has no causal dispatch diagnostic"
grep -Fq 'Settings action produced no window after AXPress on an exposed menu' \
  "$lifecycle_script" \
  || fail "the Settings path has no causal dispatch diagnostic"
close_button_count="$(grep -Fc 'subrole is "AXCloseButton"' "$lifecycle_script" || true)"
[ "$close_button_count" -eq 2 ] \
  || fail "the lifecycle probe does not resolve both standard close buttons"
close_press_count="$(grep -Fc 'perform action "AXPress" of closeButton' "$lifecycle_script" || true)"
[ "$close_press_count" -eq 2 ] \
  || fail "the lifecycle probe does not press both resolved close buttons"
if grep -Fq 'perform action "AXClose"' "$lifecycle_script"; then
  fail "the lifecycle probe still invokes unsupported AXClose on a window"
fi
if grep -Eq 'Standfast Settings|Ajustes de Standfast' "$lifecycle_script"; then
  fail "the lifecycle probe identifies the system-owned Settings title by copy"
fi
grep -Fq 'set settingsInitialEmpty to (count of windows) is 0' "$lifecycle_script" \
  || fail "the lifecycle probe does not require a zero-window Settings baseline"
grep -Fq 'set controlSingleton to controlWindowCount is 1 and processWindowCount is 1' \
  "$lifecycle_script" \
  || fail "the Control Center probe accepts an unrelated process window"
grep -Fq 'set settingsSingleton to settingsWindowCount is 1' "$lifecycle_script" \
  || fail "the Settings probe accepts an unrelated or duplicate process window"
grep -Fq 'set settingsMain to value of attribute "AXMain" of settingsWindow as boolean' \
  "$lifecycle_script" \
  || fail "the Settings probe does not require the window to be main"
grep -Fq 'set settingsFocused to value of attribute "AXFocused" of settingsWindow as boolean' \
  "$lifecycle_script" \
  || fail "the Settings probe does not require the window to be focused"
grep -Fq 'set pollAttemptLimit to 50' "$lifecycle_script" \
  || fail "the lifecycle probe has no bounded polling budget"
grep -Fq 'delay pollDelaySeconds' "$lifecycle_script" \
  || fail "the lifecycle probe does not poll transitions by condition"
if grep -Eq 'delay (1|1\.5|0\.25)$' "$lifecycle_script"; then
  fail "the lifecycle probe still samples a transition after a fixed sleep"
fi
if grep -Eq 'closeAttemptLimit|closeAttempts|attemptsAreBounded' "$lifecycle_script"; then
  fail "the lifecycle probe still reports a synthetic close-attempt bound"
fi
/usr/bin/osacompile -o "$TEST_ROOT/lifecycle.scpt" "$lifecycle_script" \
  >/dev/null || fail "the lifecycle AppleScript does not compile"

lifecycle_failure_dir="$TEST_ROOT/captured-lifecycle-failure"
mkdir -p "$lifecycle_failure_dir"
lifecycle_failure_output=""
if lifecycle_failure_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$lifecycle_failure_dir" \
    STANDFAST_OSASCRIPT_ERROR_MESSAGE="synthetic lifecycle AX failure" \
    STANDFAST_OSASCRIPT_LIFECYCLE_ABORT=1 \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the lifecycle probe accepted an aborted window traversal"
fi
assert_contains "$lifecycle_failure_output" "Accessibility lifecycle probe aborted"
assert_contains "$lifecycle_failure_output" "synthetic lifecycle AX failure"
case "$lifecycle_failure_output" in
  *"resolved="*) fail "an osascript error was obscured by a synthetic lifecycle tuple" ;;
esac

expect_lifecycle_tuple_rejected() {
  local name="$1"
  local tuple="$2"
  local expected="$3"
  local tuple_capture_dir="$TEST_ROOT/captured-$name"
  local tuple_output=""
  mkdir -p "$tuple_capture_dir"
  if tuple_output="$(
    PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
      STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
      STANDFAST_OSASCRIPT_CAPTURE_DIR="$tuple_capture_dir" \
      STANDFAST_OSASCRIPT_LIFECYCLE_TUPLE="$tuple" \
      "$AX_CHECK" "$$" 2>&1
  )"; then
    fail "the lifecycle probe accepted $name"
  fi
  assert_contains "$tuple_output" "$expected"
}

expect_lifecycle_tuple_rejected \
  "non-empty-settings-baseline" \
  'true|true|true|true|true|false|true|true|true|true|true|0|true' \
  'settingsInitialEmpty=false'
expect_lifecycle_tuple_rejected \
  "non-main-settings" \
  'true|true|true|true|true|true|true|true|false|true|true|0|true' \
  'settingsMain=false'
expect_lifecycle_tuple_rejected \
  "non-focused-settings" \
  'true|true|true|true|true|true|true|true|true|false|true|0|true' \
  'settingsFocused=false'
expect_lifecycle_tuple_rejected \
  "extra-settings-window" \
  'true|true|true|true|true|true|true|false|true|true|true|0|true' \
  'settingsSingleton=false'

# GitHub cannot run the strict AX path, so retain a small source contract for
# the first-open race that the local runtime gate reproduced. Scene creation is
# deferred; activating in the same turn leaves the first window hidden.
activation_call_count="$(grep -Fc 'SceneActivationCoordinator.live().activateWhenWindowIsVisible()' "$QUICK_MENU" || true)"
[ "$activation_call_count" -eq 2 ] \
  || fail "both scene actions must request condition-based application activation"
control_open_then_activate="$(awk '
  /case \.openControlCenter:/ { in_case = 1; stage = 1; next }
  in_case && /^[[:space:]]+case \./ { in_case = 0; stage = 0 }
  in_case && stage == 1 && /SceneActivationCoordinator\.live\(\)\.activateWhenWindowIsVisible\(\)/ { invalid = 1 }
  in_case && stage == 1 && /openWindow\(id: "control-center"\)/ { stage = 2; next }
  in_case && stage == 2 && /SceneActivationCoordinator\.live\(\)\.activateWhenWindowIsVisible\(\)/ {
    count += 1
    in_case = 0
  }
  END { print invalid ? 0 : count + 0 }
' "$QUICK_MENU")"
[ "$control_open_then_activate" -eq 1 ] \
  || fail "Control Center must be requested before its activation poll starts"
settings_open_then_activate="$(awk '
  /case \.openSettings:/ { in_case = 1; stage = 1; next }
  in_case && /^[[:space:]]+case \./ { in_case = 0; stage = 0 }
  in_case && stage == 1 && /SceneActivationCoordinator\.live\(\)\.activateWhenWindowIsVisible\(\)/ { invalid = 1 }
  in_case && stage == 1 && /openSettings\(\)/ { stage = 2; next }
  in_case && stage == 2 && /SceneActivationCoordinator\.live\(\)\.activateWhenWindowIsVisible\(\)/ {
    count += 1
    in_case = 0
  }
  END { print invalid ? 0 : count + 0 }
' "$QUICK_MENU")"
[ "$settings_open_then_activate" -eq 1 ] \
  || fail "Settings must be requested before its activation poll starts"
activation_count="$(grep -Fc 'NSApplication.shared.activate()' "$SCENE_ACTIVATION" || true)"
[ "$activation_count" -eq 1 ] \
  || fail "condition-based scene activation must have exactly one live implementation"
if grep -Fq 'NSApplication.shared.activate(' "$QUICK_MENU"; then
  fail "QuickMenu must not activate synchronously before a requested scene is visible"
fi
grep -Fq 'NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain }' \
  "$SCENE_ACTIVATION" \
  || fail "scene activation does not wait for a visible window capable of becoming main"
if grep -Fq 'DispatchQueue.main.async {' "$QUICK_MENU"; then
  fail "scene activation regressed to an unconditioned single queue hop"
fi

echo "PASS: check-app AX mode contract"
