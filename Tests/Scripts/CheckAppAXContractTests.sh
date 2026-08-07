#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AX_CHECK="$ROOT/Scripts/check-app-ax.sh"
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

mkdir -p "$FAKE_BIN"
printf '%s\n' \
  '#!/bin/bash' \
  ': > "$STANDFAST_OSASCRIPT_SENTINEL"' \
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
skip_output="$(
  PATH="$FAKE_BIN:$PATH" STANDFAST_AX_MODE=skip \
    STANDFAST_OSASCRIPT_SENTINEL="$SENTINEL" "$AX_CHECK" "$$" 2>&1
)"
assert_contains "$skip_output" "AX COVERAGE SKIPPED"
assert_contains "$skip_output" "menu, windows, and Accessibility are NOT COVERED"
[ ! -e "$SENTINEL" ] || fail "skip mode invoked osascript"

echo "PASS: check-app AX mode contract"
