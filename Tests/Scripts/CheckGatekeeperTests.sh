#!/bin/bash
# Which Gatekeeper verdicts the packaging gate accepts for which signatures.
#
# `codesign`, `spctl` and `xcrun` are fakes: no real bundle is assessed, and no
# certificate or notarisation is needed to reach the Developer ID branches.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ROOT="$PWD"
CHECK="$ROOT/Scripts/check-gatekeeper.sh"
PACKAGE_CHECK="$ROOT/Scripts/check-app.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/standfast-gatekeeper.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # Variables expand when the generated fakes run.
printf '%s\n' '#!/bin/bash' 'printf "%b\n" "$STANDFAST_FAKE_SIGNATURE" >&2' \
  > "$FAKE_BIN/codesign"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/bash' 'printf "%b\n" "$STANDFAST_FAKE_ASSESSMENT" >&2' \
  'case "$STANDFAST_FAKE_ASSESSMENT" in *accepted*) exit 0 ;; esac' 'exit 3' \
  > "$FAKE_BIN/spctl"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/bash' \
  '[ "$1 $2" = "stapler validate" ] || exit 64' \
  '[ "$STANDFAST_FAKE_STAPLED" = yes ]' \
  > "$FAKE_BIN/xcrun"
chmod +x "$FAKE_BIN/codesign" "$FAKE_BIN/spctl" "$FAKE_BIN/xcrun"

ADHOC='Identifier=dev.standfast.app\nSignature=adhoc'
DEVELOPER_ID='Identifier=dev.standfast.app\nAuthority=Developer ID Application: Someone (TEAM123456)'
UNNOTARISED='Standfast.app: rejected\nsource=Unnotarized Developer ID'
NOTARISED='Standfast.app: accepted\nsource=Notarized Developer ID'
REVOKED='Standfast.app: rejected\nsource=Developer ID\nCSSMERR_TP_CERT_REVOKED'

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# expect <pass|fail> <description> <signature> <assessment> <stapled>
expect() {
  local outcome
  if PATH="$FAKE_BIN:$PATH" STANDFAST_FAKE_SIGNATURE="$3" \
    STANDFAST_FAKE_ASSESSMENT="$4" STANDFAST_FAKE_STAPLED="$5" \
    "$CHECK" "$TEST_TMP/Standfast.app" > "$TEST_TMP/output" 2>&1; then
    outcome=pass
  else
    outcome=fail
  fi
  if [ "$outcome" = "$1" ]; then
    printf 'PASS: %s\n' "$2"
  else
    fail "$2 (the check said $outcome): $(cat "$TEST_TMP/output")"
  fi
}

expect pass "an ad-hoc build is expected to be rejected" \
  "$ADHOC" 'Standfast.app: rejected\nsource=no usable signature' no
# The release manager's own machine: a fresh Developer ID build, before
# notarize.sh has run. Rule 14 of `spctl --list` denies exactly this.
expect pass "an unnotarised Developer ID build is expected to be rejected" \
  "$DEVELOPER_ID" "$UNNOTARISED" no
expect fail "a Developer ID build rejected for anything else fails" \
  "$DEVELOPER_ID" "$REVOKED" no
expect fail "a stapled build that Gatekeeper rejects fails" \
  "$DEVELOPER_ID" "$UNNOTARISED" yes
expect pass "a stapled build that Gatekeeper accepts passes" \
  "$DEVELOPER_ID" "$NOTARISED" yes

# shellcheck disable=SC2016 # Match the literal variables in check-app.sh.
integration_call='"$ROOT/Scripts/check-gatekeeper.sh" "$APP"'
integration_call_count="$(grep -Fxc "$integration_call" "$PACKAGE_CHECK" || true)"
[ "$integration_call_count" -eq 1 ] \
  || fail "check-app.sh must invoke the Gatekeeper check exactly once on its staged app"

if [ "$failures" -ne 0 ]; then
  printf '\n%s Gatekeeper check assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll Gatekeeper check assertions passed\n'
