#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ROOT="$PWD"
CHECK="$ROOT/Scripts/check-localization-catalogues.sh"
PACKAGE_CHECK="$ROOT/Scripts/check-app.sh"
TEST_TMP="$(mktemp -d /tmp/standfast-catalogues.XXXXXX)"
trap 'rm -rf "$TEST_TMP"' EXIT

SOURCE_ROOT="$TEST_TMP/source"
APP="$TEST_TMP/Standfast.app"

for language in en es; do
  source_catalogue="$SOURCE_ROOT/Sources/Standfast/Resources/$language.lproj/Localizable.strings"
  loose_catalogue="$APP/Contents/Resources/$language.lproj/Localizable.strings"
  nested_catalogue="$APP/Contents/Resources/Standfast_Standfast.bundle/$language.lproj/Localizable.strings"
  mkdir -p "$(dirname "$source_catalogue")" "$(dirname "$loose_catalogue")" \
    "$(dirname "$nested_catalogue")"
  printf '"menu.start" = "%s";\n' "$language" >"$source_catalogue"
  cp "$source_catalogue" "$loose_catalogue"
  cp "$source_catalogue" "$nested_catalogue"
done

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  expected="$1"
  shift
  output="$TEST_TMP/output"
  if "$@" >"$output" 2>&1; then
    fail "command unexpectedly passed: $*"
  fi
  grep -Fq "$expected" "$output" \
    || fail "failure did not mention '$expected': $(cat "$output")"
}

"$CHECK" "$SOURCE_ROOT" "$APP" \
  || fail "matching source, loose and nested catalogues were rejected"

# shellcheck disable=SC2016 # Match the literal variables in check-app.sh.
integration_call='"$ROOT/Scripts/check-localization-catalogues.sh" "$ROOT" "$APP"'
integration_call_count="$(grep -Fxc "$integration_call" "$PACKAGE_CHECK" || true)"
[ "$integration_call_count" -eq 1 ] \
  || fail "check-app.sh must invoke the catalogue checker exactly once on its staged app"

for shape in loose nested; do
  for language in en es; do
    source_catalogue="$SOURCE_ROOT/Sources/Standfast/Resources/$language.lproj/Localizable.strings"
    case "$shape" in
      loose)
        packaged_catalogue="$APP/Contents/Resources/$language.lproj/Localizable.strings"
        ;;
      nested)
        packaged_catalogue="$APP/Contents/Resources/Standfast_Standfast.bundle/$language.lproj/Localizable.strings"
        ;;
    esac
    printf 'truncated\n' >"$packaged_catalogue"
    expect_failure "$shape $language catalogue differs from source" \
      "$CHECK" "$SOURCE_ROOT" "$APP"
    cp "$source_catalogue" "$packaged_catalogue"
  done
done

echo "PASS"
