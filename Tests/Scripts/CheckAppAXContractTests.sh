#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AX_CHECK="${STANDFAST_AX_CHECK_SOURCE:-$ROOT/Scripts/check-app-ax.sh}"
QUICK_MENU="$ROOT/Sources/Standfast/QuickMenuView.swift"
APP_SOURCE="$ROOT/Sources/Standfast/App.swift"
SCENE_ACTIVATION="$ROOT/Sources/Standfast/SceneActivationCoordinator.swift"
SCENE_REGISTRY="$ROOT/Sources/Standfast/SceneWindowRegistry.swift"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/standfast-ax-contract.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
SENTINEL="$TEST_ROOT/osascript-called"
LIFECYCLE_SUCCESS="identified Control Center/Settings focus transitions and targeted closure passed"
LIFECYCLE_VALID_TUPLE="true|true|true|true|true|true|true|true|true|true|true|true|true|true|true|true|0|true|true"
SETTINGS_VALID_OUTPUT='settings\tdev.standfast.settings.notifications.job-failed\nsettings\tdev.standfast.settings.notifications.disconnected\nsettings\tdev.standfast.settings.notifications.stopped\nsettings\tdev.standfast.settings.power.prevent-sleep\nsettings\tdev.standfast.settings.startup.open-at-login\nsettings\tdev.standfast.settings.version'
SETTINGS_PARTIAL_OUTPUT='settings\tdev.standfast.settings.notifications.job-failed\nsettings\tdev.standfast.settings.notifications.disconnected'

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

assert_not_contains() {
  local output="$1"
  local rejected="$2"
  case "$output" in
    *"$rejected"*) fail "output unexpectedly contained: $rejected" ;;
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

scene_probe_binding_is_exact() {
  local source="$1"
  awk '
    /^[[:space:]]*Window\(L10n\.controlCenterTitle, id: "control-center"\) \{/ {
      scene = "control"
      controlScenes += 1
      next
    }
    scene == "control" && /^[[:space:]]*\.defaultSize\(/ {
      scene = ""
      awaitingTarget = ""
      next
    }
    /^[[:space:]]*Settings \{/ {
      scene = "settings"
      settingsScenes += 1
      next
    }
    scene == "control" && /SceneWindowProbe\(/ {
      controlProbes += 1
      awaitingTarget = "control"
      next
    }
    scene == "settings" && /SceneWindowProbe\(/ {
      settingsProbes += 1
      awaitingTarget = "settings"
      next
    }
    awaitingTarget != "" && /target:[[:space:]]*\./ {
      if (awaitingTarget == "control" && /target:[[:space:]]*\.controlCenter,/) {
        controlMatches += 1
      } else if (awaitingTarget == "settings" && /target:[[:space:]]*\.settings,/) {
        settingsMatches += 1
      } else {
        invalid = 1
      }
      awaitingTarget = ""
    }
    END {
      valid = controlScenes == 1 && settingsScenes == 1 &&
        controlProbes == 1 && settingsProbes == 1 &&
        controlMatches == 1 && settingsMatches == 1 &&
        awaitingTarget == "" && !invalid
      exit(valid ? 0 : 1)
    }
  ' "$source"
}

mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # Variables expand when the generated fake runs.
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
  '    1) printf "%b\n" "${STANDFAST_OSASCRIPT_MENU_OUTPUT:-runner\tbuild-mac · Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit}" ;;' \
  '    2)' \
  '      printf "%s\n" "${CHECK_LANGUAGE:-}" > "$STANDFAST_OSASCRIPT_CAPTURE_DIR/call-2.language"' \
  '      [ "${STANDFAST_OSASCRIPT_LIFECYCLE_ABORT:-0}" != 1 ] || exit 1' \
  '      printf "%s\n" "${STANDFAST_OSASCRIPT_LIFECYCLE_TUPLE:-true|true|true|true|true|true|true|true|true|true|true|true|true|true|true|true|0|true|true}"' \
  '      settings_output="${STANDFAST_OSASCRIPT_SETTINGS_OUTPUT:-settings\tdev.standfast.settings.notifications.job-failed\nsettings\tdev.standfast.settings.notifications.disconnected\nsettings\tdev.standfast.settings.notifications.stopped\nsettings\tdev.standfast.settings.power.prevent-sleep\nsettings\tdev.standfast.settings.startup.open-at-login\nsettings\tdev.standfast.settings.version}"' \
  '      if [ "${STANDFAST_OSASCRIPT_SETTINGS_EVENTUAL_OUTPUT+x}" = x ]; then' \
  '        if grep -Fq "repeat with settingsPollAttempt from 1 to pollAttemptLimit" "$STANDFAST_OSASCRIPT_CAPTURE_DIR/call-2.applescript"; then' \
  '          settings_output="$STANDFAST_OSASCRIPT_SETTINGS_EVENTUAL_OUTPUT"' \
  '        else' \
  '          settings_output="${STANDFAST_OSASCRIPT_SETTINGS_INITIAL_OUTPUT:-\\c}"' \
  '        fi' \
  '      fi' \
  '      printf "%b\n" "$settings_output"' \
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
assert_contains "$lifecycle_output" "$LIFECYCLE_SUCCESS"
[ "$(<"$capture_dir/call-2.language")" = en ] \
  || fail "the English menu language was not passed to the lifecycle probe"

empty_settings_dir="$TEST_ROOT/captured-settings-empty"
mkdir -p "$empty_settings_dir"
empty_settings_output=""
if empty_settings_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$empty_settings_dir" \
    STANDFAST_OSASCRIPT_SETTINGS_OUTPUT='\c' \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke accepted a Settings tree with zero identifier records"
fi
assert_contains "$empty_settings_output" \
  "Settings AX identifiers not ready before timeout: missing=dev.standfast.settings.notifications.job-failed,dev.standfast.settings.notifications.disconnected,dev.standfast.settings.notifications.stopped,dev.standfast.settings.power.prevent-sleep,dev.standfast.settings.startup.open-at-login,dev.standfast.settings.version; duplicates=none"
assert_not_contains "$empty_settings_output" "unknown Settings AX record type"
assert_not_contains "$empty_settings_output" "empty record"

delayed_settings_dir="$TEST_ROOT/captured-delayed-settings"
mkdir -p "$delayed_settings_dir"
delayed_settings_output=""
if ! delayed_settings_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$delayed_settings_dir" \
    STANDFAST_OSASCRIPT_SETTINGS_INITIAL_OUTPUT="$SETTINGS_PARTIAL_OUTPUT" \
    STANDFAST_OSASCRIPT_SETTINGS_EVENTUAL_OUTPUT="$SETTINGS_VALID_OUTPUT" \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke rejected Settings identifiers that became ready: $delayed_settings_output"
fi
assert_contains "$delayed_settings_output" "$LIFECYCLE_SUCCESS"

expect_settings_output_rejected() {
  local name="$1"
  local settings_output="$2"
  local expected="$3"
  local settings_capture_dir="$TEST_ROOT/captured-settings-$name"
  local rejected_output=""
  mkdir -p "$settings_capture_dir"
  if rejected_output="$(
    PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
      STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
      STANDFAST_OSASCRIPT_CAPTURE_DIR="$settings_capture_dir" \
      STANDFAST_OSASCRIPT_SETTINGS_OUTPUT="$settings_output" \
      "$AX_CHECK" "$$" 2>&1
  )"; then
    fail "the AX smoke accepted $name"
  fi
  assert_contains "$rejected_output" "$expected"
}

settings_without_power="$(
  printf '%b\n' "$SETTINGS_VALID_OUTPUT" \
    | grep -Fv 'dev.standfast.settings.power.prevent-sleep'
)"
expect_settings_output_rejected \
  "settings-without-power-toggle" \
  "$settings_without_power" \
  "Settings AX identifiers not ready before timeout: missing=dev.standfast.settings.power.prevent-sleep; duplicates=none"

settings_with_duplicate_version="$(
  printf '%b\nsettings\tdev.standfast.settings.version\n' "$SETTINGS_VALID_OUTPUT"
)"
expect_settings_output_rejected \
  "settings-with-duplicate-version" \
  "$settings_with_duplicate_version" \
  "Settings AX identifiers not ready before timeout: missing=none; duplicates=dev.standfast.settings.version(2)"

never_complete_dir="$TEST_ROOT/captured-settings-never-complete"
mkdir -p "$never_complete_dir"
never_complete_output=""
if never_complete_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$never_complete_dir" \
    STANDFAST_OSASCRIPT_SETTINGS_INITIAL_OUTPUT="$SETTINGS_PARTIAL_OUTPUT" \
    STANDFAST_OSASCRIPT_SETTINGS_EVENTUAL_OUTPUT="$SETTINGS_PARTIAL_OUTPUT" \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke accepted a Settings tree that never became complete"
fi
assert_contains "$never_complete_output" \
  "Settings AX identifiers not ready before timeout: missing=dev.standfast.settings.notifications.stopped,dev.standfast.settings.power.prevent-sleep,dev.standfast.settings.startup.open-at-login,dev.standfast.settings.version; duplicates=none"

expect_settings_output_rejected \
  "settings-with-unknown-record" \
  "$(printf '%b\nunknown\tdev.standfast.settings.version\n' "$SETTINGS_VALID_OUTPUT")" \
  "unknown Settings AX record type"

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
assert_contains "$warning_output" "$LIFECYCLE_SUCCESS"

key_like_runner_dir="$TEST_ROOT/captured-key-like-runner"
mkdir -p "$key_like_runner_dir"
key_like_runner_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$key_like_runner_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='runner\tstate.idle · build-mac · Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$key_like_runner_output" "$LIFECYCLE_SUCCESS"

fleet_named_runner_dir="$TEST_ROOT/captured-fleet-named-runner"
mkdir -p "$fleet_named_runner_dir"
fleet_named_runner_output=""
if ! fleet_named_runner_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$fleet_named_runner_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='runner\tFleet — build-mac · Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke rejected a legitimate Fleet-prefixed runner: $fleet_named_runner_output"
fi
assert_contains "$fleet_named_runner_output" "$LIFECYCLE_SUCCESS"

flota_named_runner_dir="$TEST_ROOT/captured-flota-named-runner"
mkdir -p "$flota_named_runner_dir"
flota_named_runner_output=""
if ! flota_named_runner_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$flota_named_runner_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='runner\tFlota — mac-mini-m4 · Ejecutando\nstatic\tAbrir Standfast\nstatic\tConfiguración\nstatic\tSalir' \
    "$AX_CHECK" "$$" 2>&1
)"; then
  fail "the AX smoke rejected a legitimate Flota-prefixed runner: $flota_named_runner_output"
fi
assert_contains "$flota_named_runner_output" "$LIFECYCLE_SUCCESS"

non_boundary_key_dir="$TEST_ROOT/captured-non-boundary-key"
mkdir -p "$non_boundary_key_dir"
non_boundary_key_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$non_boundary_key_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='static\tDiagnostic mentions state.idle\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$non_boundary_key_output" "$LIFECYCLE_SUCCESS"

spanish_dir="$TEST_ROOT/captured-spanish-menu"
mkdir -p "$spanish_dir"
spanish_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
    STANDFAST_OSASCRIPT_CAPTURE_DIR="$spanish_dir" \
    STANDFAST_OSASCRIPT_MENU_OUTPUT='runner\tmac-mini-m4 · Ejecutando\nstatic\tAbrir Standfast\nstatic\tConfiguración\nstatic\tSalir' \
    "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$spanish_output" "$LIFECYCLE_SUCCESS"
[ "$(<"$spanish_dir/call-2.language")" = es ] \
  || fail "the Spanish menu language was not passed to the lifecycle probe"

expect_menu_output_rejected() {
  local name="$1"
  local menu_output="$2"
  local expected="$3"
  local menu_capture_dir="$TEST_ROOT/captured-menu-$name"
  local rejected_output=""
  mkdir -p "$menu_capture_dir"
  if rejected_output="$(
    PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=require \
      STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" \
      STANDFAST_OSASCRIPT_CAPTURE_DIR="$menu_capture_dir" \
      STANDFAST_OSASCRIPT_MENU_OUTPUT="$menu_output" \
      "$AX_CHECK" "$$" 2>&1
  )"; then
    fail "the AX smoke accepted $name"
  fi
  assert_contains "$rejected_output" "$expected"
}

expect_menu_output_rejected \
  "unknown-record" \
  'mystery\tstate.idle\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "unknown AX menu record type"
expect_menu_output_rejected \
  "untyped-record" \
  'state.idle\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "unknown AX menu record type"
expect_menu_output_rejected \
  "mixed-language" \
  'static\tFleet idle\nstatic\tOpen Standfast\nstatic\tConfiguración\nstatic\tQuit' \
  "one complete English or Spanish static action set"
expect_menu_output_rejected \
  "two-languages" \
  'static\tOpen Standfast\nstatic\tSettings\nstatic\tQuit\nstatic\tAbrir Standfast\nstatic\tConfiguración\nstatic\tSalir' \
  "one complete English or Spanish static action set"
expect_menu_output_rejected \
  "runner-action-spoof" \
  'runner\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "one complete English or Spanish static action set"
expect_menu_output_rejected \
  "english-fleet-aggregate" \
  'static\tFleet — Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "aggregate Fleet/Flota row escaped into the quick menu"
expect_menu_output_rejected \
  "spanish-fleet-aggregate" \
  'static\tFlota — Listo\nstatic\tAbrir Standfast\nstatic\tConfiguración\nstatic\tSalir' \
  "aggregate Fleet/Flota row escaped into the quick menu"
expect_menu_output_rejected \
  "runner-without-separator" \
  'runner\tbuild-mac Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "runner AX menu record has no concrete identity and localized short state"
expect_menu_output_rejected \
  "runner-without-identity" \
  'runner\t · Ready\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "runner AX menu record has no concrete identity and localized short state"
expect_menu_output_rejected \
  "runner-with-long-state" \
  'runner\tbuild-mac · Idle — ready for jobs\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit' \
  "runner AX menu record has no concrete identity and localized short state"

for raw_key in \
  menu.controlCenter \
  state.idle \
  job.running \
  duration.seconds \
  thermal.serious \
  notification.failed
do
  family="${raw_key%%.*}"
  expect_menu_output_rejected \
    "raw-$family-at-start" \
    "static\t$raw_key\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit" \
    "raw localization key escaped into static AX menu content: $raw_key"
  expect_menu_output_rejected \
    "raw-$family-after-separator" \
    "static\tFleet — $raw_key\nstatic\tOpen Standfast\nstatic\tSettings\nstatic\tQuit" \
    "raw localization key escaped into static AX menu content: Fleet — $raw_key"
done

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
if grep -Fq 'every menu item of targetMenu' "$menu_script"; then
  fail "the menu probe searches cached AXChildren instead of the exposed AXVisibleChildren"
fi
grep -Fq 'repeat with visibleMenuItem in visibleMenuItems' "$menu_script" \
  || fail "the menu probe does not enumerate the exposed AXVisibleChildren"
grep -Fq 'value of attribute "AXTitle" of visibleMenuItem' "$menu_script" \
  || fail "the menu probe does not read titles from exposed AXVisibleChildren"
grep -Fq 'value of attribute "AXValue" of visibleMenuItem' "$menu_script" \
  || fail "the menu probe does not fall back to AXValue for runner identity"
grep -Fq 'value of attribute "AXIdentifier" of visibleMenuItem' "$menu_script" \
  || fail "the menu probe does not type exposed records from stable AX identifiers"
grep -Fq 'dev.standfast.quick-menu.static' "$menu_script" \
  || fail "the menu probe does not recognize the stable static AX identifier"
grep -Fq 'dev.standfast.quick-menu.runner' "$menu_script" \
  || fail "the menu probe does not recognize the stable runner AX identifier"
grep -Fq 'set recordType to "unknown"' "$menu_script" \
  || fail "the menu probe does not emit a closed-world type for unknown identifiers"
if grep -Fq 'set records to {}' "$menu_script"; then
  fail "the menu probe uses AppleScript's reserved process records collection"
fi
grep -Fq 'set menuRecords to {}' "$menu_script" \
  || fail "the menu probe does not initialize its nonreserved record collection"
grep -Fq 'set end of menuRecords to recordType & tab' "$menu_script" \
  || fail "the menu probe does not emit one typed record per visible AX child"
grep -Fq 'set joinedMenuRecords to menuRecords as text' "$menu_script" \
  || fail "the menu probe does not join the nonreserved record collection"
grep -Fq 'return joinedMenuRecords' "$menu_script" \
  || fail "the menu probe does not return the joined nonreserved record collection"
grep -Fq 'set text item delimiters of AppleScript to linefeed' "$menu_script" \
  || fail "the menu probe concatenates adjacent item names without a delimiter"
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
[ "$lifecycle_status_press_count" -eq 3 ] \
  || fail "Control, Settings, and Control return must expose the status menu through AXPress"
lifecycle_exposure_count="$(grep -Fc 'set menuExposed to selected of statusItem' "$lifecycle_script" || true)"
[ "$lifecycle_exposure_count" -eq 3 ] \
  || fail "all three lifecycle actions must wait for AXSelected"
assert_status_open_transitions "$lifecycle_script" 3 "all three lifecycle actions"
lifecycle_visible_children_count="$(grep -Fc 'value of attribute "AXVisibleChildren" of targetMenu' "$lifecycle_script" || true)"
[ "$lifecycle_visible_children_count" -eq 3 ] \
  || fail "all three lifecycle actions must inspect visible children after exposure"
visible_menu_guard_count="$(grep -Fc 'if (count of visibleMenuItems) is 0 then error' "$lifecycle_script" || true)"
[ "$visible_menu_guard_count" -eq 3 ] \
  || fail "all three lifecycle actions must reject an exposed menu with no visible children"
if grep -Fq 'every menu item of targetMenu' "$lifecycle_script"; then
  fail "a lifecycle action searches cached AXChildren instead of its exposed AXVisibleChildren"
fi
visible_menu_loop_count="$(grep -Fc 'repeat with visibleMenuItem in visibleMenuItems' "$lifecycle_script" || true)"
[ "$visible_menu_loop_count" -eq 3 ] \
  || fail "all three lifecycle actions must search their exposed AXVisibleChildren"
visible_menu_title_count="$(grep -Fc 'value of attribute "AXTitle" of visibleMenuItem as text' "$lifecycle_script" || true)"
[ "$visible_menu_title_count" -eq 3 ] \
  || fail "all three lifecycle actions must read titles from exposed AXVisibleChildren"
visible_menu_resolution_count="$(grep -Fc 'set targetMenuItem to contents of visibleMenuItem' "$lifecycle_script" || true)"
[ "$visible_menu_resolution_count" -eq 3 ] \
  || fail "all three lifecycle actions must press an item from exposed AXVisibleChildren"
menu_item_press_count="$(grep -Fc 'perform action "AXPress" of targetMenuItem' "$lifecycle_script" || true)"
[ "$menu_item_press_count" -eq 3 ] \
  || fail "all three visible lifecycle menu items must be invoked through AXPress"
grep -Fq 'system attribute "CHECK_LANGUAGE"' "$lifecycle_script" \
  || fail "the lifecycle probe does not reuse the one validated menu language"
if grep -Fq 'click statusItem' "$lifecycle_script"; then
  fail "the lifecycle probe still uses an unreliable synthetic status-item click"
fi
grep -Fq 'Control Center action produced no window with AXIdentifier' \
  "$lifecycle_script" \
  || fail "the Control Center path has no causal dispatch diagnostic"
grep -Fq 'Settings action produced no window with AXIdentifier' \
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
grep -Fq 'dev.standfast.scene.control-center' "$lifecycle_script" \
  || fail "the lifecycle probe does not use the stable Control Center window identifier"
grep -Fq 'dev.standfast.scene.settings' "$lifecycle_script" \
  || fail "the lifecycle probe does not use the stable Settings window identifier"
grep -Fq 'entire contents of settingsWindow' "$lifecycle_script" \
  || fail "the lifecycle probe does not inspect the opened Settings descendants"
grep -Fq 'repeat with settingsPollAttempt from 1 to pollAttemptLimit' \
  "$lifecycle_script" \
  || fail "the Settings identifier probe does not poll within the lifecycle deadline"
grep -Fq 'if settingsIdentifiersReady then exit repeat' "$lifecycle_script" \
  || fail "the Settings identifier probe does not stop when every exact ID is ready"
for settings_identifier in \
  dev.standfast.settings.notifications.job-failed \
  dev.standfast.settings.notifications.disconnected \
  dev.standfast.settings.notifications.stopped \
  dev.standfast.settings.power.prevent-sleep \
  dev.standfast.settings.startup.open-at-login \
  dev.standfast.settings.version
do
  grep -Fq "$settings_identifier" "$lifecycle_script" \
    || fail "the lifecycle probe does not require Settings identifier $settings_identifier"
done
if grep -Fq 'perform action "AXPress" of settingsElement' "$lifecycle_script"; then
  fail "the Settings inspection toggles a control instead of reading identifiers"
fi
window_identifier_read_count="$(grep -Fc 'value of attribute "AXIdentifier" of candidateWindow as text' "$lifecycle_script" || true)"
[ "$window_identifier_read_count" -ge 6 ] \
  || fail "the lifecycle probe does not resolve every transition by exact window identifier"
if grep -Eq 'Standfast Control Center|Centro de control de Standfast|Standfast Settings|Ajustes de Standfast' \
  "$lifecycle_script"; then
  fail "the lifecycle probe still identifies a target window by localized title"
fi
if grep -Eq 'processWindowCount|controlSingleton|settingsSingleton|settingsInitialEmpty|count of windows\) is 0' \
  "$lifecycle_script"; then
  fail "the lifecycle probe still assumes its target is the process singleton"
fi
control_action_resolution_count="$(grep -Fc 'visibleName is controlCenterItemName' "$lifecycle_script" || true)"
[ "$control_action_resolution_count" -eq 2 ] \
  || fail "the lifecycle probe must invoke Control Center before and after Settings"
settings_action_resolution_count="$(grep -Fc 'visibleName is settingsItemName' "$lifecycle_script" || true)"
[ "$settings_action_resolution_count" -eq 1 ] \
  || fail "the lifecycle probe must invoke Settings once between Control actions"
grep -Fq 'set settingsMainAfterControl to value of attribute "AXMain" of settingsWindow as boolean' \
  "$lifecycle_script" \
  || fail "Control-to-Settings does not require Settings to become main"
grep -Fq 'set settingsFocusedAfterControl to value of attribute "AXFocused" of settingsWindow as boolean' \
  "$lifecycle_script" \
  || fail "Control-to-Settings does not require Settings to become focused"
grep -Fq 'set controlMainAfterSettings to value of attribute "AXMain" of controlWindow as boolean' \
  "$lifecycle_script" \
  || fail "Settings-to-Control does not require Control Center to become main"
grep -Fq 'set controlFocusedAfterSettings to value of attribute "AXFocused" of controlWindow as boolean' \
  "$lifecycle_script" \
  || fail "Settings-to-Control does not require Control Center to become focused"
grep -Fq 'set settingsRetainedAfterControlClose' "$lifecycle_script" \
  || fail "targeted closure does not prove Settings survived closing Control Center"
grep -Fq 'set settingsAbsentAfterInitialControl to settingsMatchCount is 0' "$lifecycle_script" \
  || fail "the initial Control transition does not explicitly require Settings to stay absent"
grep -Fq 'if not settingsAbsentAfterInitialControl then' "$lifecycle_script" \
  || fail "the initial Control transition has no causal failure for an unexpected Settings window"
grep -Fq 'set baselineWindows to {}' "$lifecycle_script" \
  || fail "the lifecycle probe does not retain baseline window identities"
grep -Fq 'set end of baselineWindows to contents of candidateWindow' "$lifecycle_script" \
  || fail "the lifecycle probe does not retain concrete baseline window references"
grep -Fq 'repeat with baselineWindow in baselineWindows' "$lifecycle_script" \
  || fail "targeted closure does not verify every baseline window reference"
grep -Fq 'if (contents of candidateWindow) is (contents of baselineWindow) then' "$lifecycle_script" \
  || fail "targeted closure does not compare current windows with each baseline identity"
grep -Fq 'set unrelatedWindowsPreserved to baselineWindowsPreserved and' "$lifecycle_script" \
  || fail "targeted closure does not combine baseline identity and cardinality preservation"
if grep -Fq 'set unrelatedWindowsPreserved to (count of windows) is baselineWindowCount' \
  "$lifecycle_script"; then
  fail "targeted closure still treats equal window counts as identity preservation"
fi
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
  *"targetsInitialAbsent="*) fail "an osascript error was obscured by a synthetic lifecycle tuple" ;;
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

lifecycle_tuple_with_field() {
  local field="$1"
  local value="$2"
  printf '%s\n' "$LIFECYCLE_VALID_TUPLE" \
    | awk -F '|' -v OFS='|' -v field="$field" -v value="$value" \
      '{$field = value; print}'
}

expect_lifecycle_tuple_rejected \
  "pre-existing-target-window" \
  "$(lifecycle_tuple_with_field 1 false)" \
  'targetsInitialAbsent=false'
expect_lifecycle_tuple_rejected \
  "initial-control-not-main" \
  "$(lifecycle_tuple_with_field 3 false)" \
  'controlMainInitially=false'
expect_lifecycle_tuple_rejected \
  "control-not-opened" \
  "$(lifecycle_tuple_with_field 2 false)" \
  'controlOpened=false'
expect_lifecycle_tuple_rejected \
  "initial-control-not-focused" \
  "$(lifecycle_tuple_with_field 4 false)" \
  'controlFocusedInitially=false'
expect_lifecycle_tuple_rejected \
  "settings-opened-with-initial-control" \
  "$(lifecycle_tuple_with_field 5 false)" \
  'settingsAbsentAfterInitialControl=false'
expect_lifecycle_tuple_rejected \
  "settings-not-opened" \
  "$(lifecycle_tuple_with_field 6 false)" \
  'settingsOpened=false'
expect_lifecycle_tuple_rejected \
  "control-lost-during-settings-transition" \
  "$(lifecycle_tuple_with_field 7 false)" \
  'controlRetainedForSettings=false'
expect_lifecycle_tuple_rejected \
  "settings-not-main-after-control" \
  "$(lifecycle_tuple_with_field 8 false)" \
  'settingsMainAfterControl=false'
expect_lifecycle_tuple_rejected \
  "settings-not-focused-after-control" \
  "$(lifecycle_tuple_with_field 9 false)" \
  'settingsFocusedAfterControl=false'
expect_lifecycle_tuple_rejected \
  "settings-lost-during-control-return" \
  "$(lifecycle_tuple_with_field 11 false)" \
  'settingsRetainedForControl=false'
expect_lifecycle_tuple_rejected \
  "control-not-returned" \
  "$(lifecycle_tuple_with_field 10 false)" \
  'controlReturned=false'
expect_lifecycle_tuple_rejected \
  "control-not-main-after-settings" \
  "$(lifecycle_tuple_with_field 12 false)" \
  'controlMainAfterSettings=false'
expect_lifecycle_tuple_rejected \
  "control-not-focused-after-settings" \
  "$(lifecycle_tuple_with_field 13 false)" \
  'controlFocusedAfterSettings=false'
expect_lifecycle_tuple_rejected \
  "control-not-closed" \
  "$(lifecycle_tuple_with_field 14 false)" \
  'controlClosed=false'
expect_lifecycle_tuple_rejected \
  "settings-collateral-close" \
  "$(lifecycle_tuple_with_field 15 false)" \
  'settingsRetainedAfterControlClose=false'
expect_lifecycle_tuple_rejected \
  "settings-not-closed" \
  "$(lifecycle_tuple_with_field 16 false)" \
  'settingsClosed=false'
expect_lifecycle_tuple_rejected \
  "target-window-remains" \
  "$(lifecycle_tuple_with_field 17 1)" \
  'remainingTargetWindows=1'
expect_lifecycle_tuple_rejected \
  "unrelated-window-closed" \
  "$(lifecycle_tuple_with_field 18 false)" \
  'unrelatedWindowsPreserved=false'
expect_lifecycle_tuple_rejected \
  "status-item-died" \
  "$(lifecycle_tuple_with_field 19 false)" \
  'statusItemAlive=false'

# GitHub cannot run the strict AX path, so retain a small source contract for
# the exact-target race that the local runtime gate reproduced. The coordinator
# must own each open request; no global visible-window predicate can satisfy it.
exact_target_call_count="$(grep -Ec 'sceneActivation\.openAndActivate\(\.(controlCenter|settings)\)' "$QUICK_MENU" || true)"
[ "$exact_target_call_count" -eq 2 ] \
  || fail "both scene actions must request exact-target application activation"
control_open_then_activate="$(awk '
  /case \.openControlCenter:/ { in_case = 1; stage = 1; next }
  in_case && /^[[:space:]]+case \./ { in_case = 0; stage = 0 }
  in_case && stage == 1 && /openWindow\(id: "control-center"\)/ { invalid = 1 }
  in_case && stage == 1 && /sceneActivation\.openAndActivate\(\.controlCenter\)/ {
    stage = 2
    next
  }
  in_case && stage == 2 && /openWindow\(id: "control-center"\)/ {
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
  in_case && stage == 1 && /openSettings\(\)/ { invalid = 1 }
  in_case && stage == 1 && /sceneActivation\.openAndActivate\(\.settings\)/ {
    stage = 2
    next
  }
  in_case && stage == 2 && /openSettings\(\)/ {
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
grep -Fq 'windowRegistry.window(for: request.target)' "$SCENE_ACTIVATION" \
  || fail "scene activation does not resolve the exact requested target"
if grep -Fq 'NSApplication.shared.windows' "$SCENE_ACTIVATION"; then
  fail "scene activation regressed to accepting an unrelated application window"
fi
scene_probe_binding_is_exact "$APP_SOURCE" \
  || fail "each SwiftUI scene must install its own exact-target window probe"
swapped_scene_source="$TEST_ROOT/App-swapped-scene-probes.swift"
awk '
  {
    if (!swappedControl && /target:[[:space:]]*\.controlCenter,/) {
      sub(/target:[[:space:]]*\.controlCenter,/, "target: .settings,")
      swappedControl = 1
    } else if (!swappedSettings && /target:[[:space:]]*\.settings,/) {
      sub(/target:[[:space:]]*\.settings,/, "target: .controlCenter,")
      swappedSettings = 1
    }
    print
  }
  END { if (!swappedControl || !swappedSettings) exit 1 }
' "$APP_SOURCE" > "$swapped_scene_source"
if scene_probe_binding_is_exact "$swapped_scene_source"; then
  fail "the scene source contract accepted swapped Control Center and Settings probes"
fi
grep -Fq 'dev.standfast.scene.control-center' "$SCENE_REGISTRY" \
  || fail "the Control Center window has no stable AX identity"
grep -Fq 'dev.standfast.scene.settings' "$SCENE_REGISTRY" \
  || fail "the Settings window has no stable AX identity"
static_identifier_count="$(grep -Fc '"dev.standfast.quick-menu.static"' "$QUICK_MENU" || true)"
[ "$static_identifier_count" -eq 5 ] \
  || fail "every static quick-menu element must expose the stable static AX identifier"
runner_identifier_count="$(grep -Fc '"dev.standfast.quick-menu.runner"' "$QUICK_MENU" || true)"
[ "$runner_identifier_count" -eq 1 ] \
  || fail "the runner submenu must expose exactly the generic runner AX identifier"
front_then_activate="$(awk '
  /window\.makeKeyAndOrderFront\(nil\)/ { stage = 1; next }
  stage == 1 && /activateApplication\(\)/ { count += 1; stage = 0 }
  END { print count + 0 }
' "$SCENE_ACTIVATION")"
[ "$front_then_activate" -eq 1 ] \
  || fail "the exact window must be made key and front before app activation"
if grep -Fq 'DispatchQueue.main.async {' "$QUICK_MENU"; then
  fail "scene activation regressed to an unconditioned single queue hop"
fi

echo "PASS: check-app AX mode contract"
