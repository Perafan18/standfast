#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/Scripts/check-public-diff.sh"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/standfast-public-diff.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT

failures=0
case_number=0
case_name=""
repo=""

begin_case() {
  case_number=$((case_number + 1))
  case_name="$1"
  repo="$FIXTURES/case-$case_number"
  mkdir -p "$repo/Scripts" "$repo/Resources" "$repo/docs"
  cp "$CHECK" "$repo/Scripts/check-public-diff.sh"
  git -C "$repo" init -q
  git -C "$repo" checkout -q -b main
  git -C "$repo" config user.name "Standfast Contract"
  git -C "$repo" config user.email "contract@example.invalid"
  printf 'baseline\n' > "$repo/fixture.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm baseline
  git -C "$repo" tag base
}

commit_case() {
  git -C "$repo" add -A
  git -C "$repo" commit -qm "$case_name"
}

expect_pass() {
  local range="$1"
  local output
  if output="$(cd "$repo" && Scripts/check-public-diff.sh "$range" 2>&1)"; then
    printf 'PASS: %s\n' "$case_name"
  else
    printf 'FAIL: %s unexpectedly failed\n%s\n' "$case_name" "$output" >&2
    failures=$((failures + 1))
  fi
}

expect_fail() {
  local range="$1"
  local expected="$2"
  local output
  if output="$(cd "$repo" && Scripts/check-public-diff.sh "$range" 2>&1)"; then
    printf 'FAIL: %s unexpectedly passed\n' "$case_name" >&2
    failures=$((failures + 1))
  elif [ -n "$expected" ] && ! printf '%s\n' "$output" | grep -Fq "$expected"; then
    printf 'FAIL: %s failed for the wrong reason\n%s\n' "$case_name" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$case_name"
  fi
}

# Build rejected marker values only when the fixture runs. The contract itself
# remains suitable input to the checker it exercises.
local_root="/""Users"
private_tool="Obsi""dian"

begin_case "added content beginning with two plus signs is still inspected"
printf '++ %s/example/private\n' "$local_root" >> "$repo/fixture.txt"
commit_case
expect_fail "base...HEAD" "private workspace references"

begin_case "ordinary added private content is rejected"
printf 'local checkout: %s/example/private\n' "$local_root" >> "$repo/fixture.txt"
commit_case
expect_fail "base...HEAD" "private workspace references"

begin_case "ordinary clean added content is allowed"
printf 'public project note\n' >> "$repo/fixture.txt"
commit_case
expect_pass "base...HEAD"

begin_case "a clean renamed and modified path is allowed"
git -C "$repo" mv fixture.txt docs/renamed.md
printf 'public rename note\n' >> "$repo/docs/renamed.md"
commit_case
expect_pass "base...HEAD"

begin_case "a renamed and modified path is inspected"
git -C "$repo" mv fixture.txt docs/renamed.md
printf 'private tool: %s\n' "$private_tool" >> "$repo/docs/renamed.md"
commit_case
expect_fail "base...HEAD" "private workspace references"

begin_case "a dotted branch name is a valid range endpoint"
git -C "$repo" branch -m "release/0.5.0"
printf 'public release note\n' >> "$repo/fixture.txt"
commit_case
expect_pass "release/0.5.0^...release/0.5.0"

begin_case "an invalid range fails closed"
expect_fail "missing-ref...HEAD" ""

begin_case "an unauthorized binary addition is rejected"
mkdir -p "$repo/Assets"
printf 'safe\000binary\n' > "$repo/Assets/new.bin"
commit_case
expect_fail "base...HEAD" "unauthorized binary"

begin_case "the exact application icon binary is allowed"
cp "$ROOT/Resources/AppIcon.png" "$repo/Resources/AppIcon.png"
commit_case
expect_pass "base...HEAD"

begin_case "private strings inside the allowed binary are rejected"
printf '\211PNG\r\n\032\n\000local checkout: %s/example/private\n' "$local_root" \
  > "$repo/Resources/AppIcon.png"
commit_case
expect_fail "base...HEAD" "private workspace references"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d public-diff contract case(s) failed\n' "$failures" >&2
  exit 1
fi

echo "PASS: public-diff executable contract"
