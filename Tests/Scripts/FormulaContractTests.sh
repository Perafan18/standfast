#!/bin/bash
# What Formula/standfast.rb must keep telling build-app.sh and the user.
#
# Nothing here can run `brew install`: the formula points at a release that may
# not exist yet, and installing would touch this Mac's Cellar.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
FORMULA=Formula/standfast.rb

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() { printf 'PASS: %s\n' "$1"; }

install_block="$(awk '
  /^  def install$/ { found = 1; next }
  found && /^  end$/ { exit }
  found { print }
' "$FORMULA")"
[ -n "$install_block" ] || fail "the formula has no install method to check"

# Each setting must be in place before build-app.sh runs, not merely present.
expect_set_before_build() {
  local setting="$1" why="$2"
  local order
  order="$(printf '%s\n' "$install_block" | awk -v setting="$setting" '
    index($0, setting) { seen = 1 }
    index($0, "system \"./Scripts/build-app.sh\"") { print (seen ? "before" : "after"); exit }
  ')"
  if [ "$order" = before ]; then
    pass "$why"
  else
    fail "$why: $setting is not set before build-app.sh runs"
  fi
}

# Homebrew's own sandbox-exec around the build makes SwiftPM's nested one fail.
expect_set_before_build 'ENV["STANDFAST_SWIFTPM_SANDBOX"] = "0"' \
  "the build does not nest SwiftPM's sandbox inside Homebrew's"
# A Developer ID in the user's keychain must not sign what Homebrew installs.
expect_set_before_build 'ENV["SIGN_IDENTITY"] = "-"' \
  "what Homebrew installs is signed ad-hoc"

caveats="$(awk '
  /^  def caveats$/ { found = 1; next }
  found && /^  end$/ { exit }
  found { print }
' "$FORMULA")"
[ -n "$caveats" ] || fail "the formula has no caveats to check"

# Spotlight and Launchpad skip a symlinked app, which is why Homebrew dropped
# `brew linkapps`; only a real bundle in /Applications is found by name.
if printf '%s\n' "$caveats" | grep -Eq 'ln -[a-z]*s[a-z]* .*/Applications'; then
  fail "the caveat links the app into /Applications, where Spotlight ignores it"
elif ! printf '%s\n' "$caveats" \
  | grep -Fq 'ditto "#{opt_prefix}/Standfast.app" /Applications/Standfast.app'; then
  fail "the caveat no longer says how to put a real copy in /Applications"
else
  pass "the caveat copies the app into /Applications instead of linking it"
fi

# From the macOS 27 SDK on, SwiftUI's `@State` is a macro whose plugin ships
# only inside Xcode.app, so a Command Line Tools-only build fails at the first
# `@State`. The formula has to ask for Xcode before it downloads anything.
if grep -Eq '^  depends_on xcode: \[[^]]*:build\]' "$FORMULA"; then
  pass "the formula asks for Xcode to build, which SwiftUI's macros need"
else
  fail "the formula does not require Xcode, and the Command Line Tools cannot build the app"
fi

# ─────────────────────────────────────────────────────────────────────────────
if [ "$failures" -ne 0 ]; then
  printf '\n%s formula contract assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll formula contract assertions passed\n'
