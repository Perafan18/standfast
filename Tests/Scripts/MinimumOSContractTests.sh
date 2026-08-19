#!/bin/bash
# The oldest macOS this app claims to run on, and the four places that say so.
#
# Nothing in the build links them. `Package.swift` decides what the compiler
# enforces; `Info.plist` decides what macOS will let a user install; the README
# and the landing page are what somebody reads before downloading it. Bump one
# and the rest keep promising the old number — an app that installs on a system
# it can no longer run on, described by a page that was right last month.
#
# This is the same trap the version/formula check next door exists for, and it
# matters more since 2026-08-19: the job that compiled against an older Xcode on
# an actual macOS 14 is gone, so the declared minimum is now enforced by the
# compiler and by nothing else. Agreement between these four is what is left.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# `.macOS(.v14)` — the deployment target the compiler checks every API against.
package="$(sed -n 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1/p' Package.swift | head -n 1)"
[ -n "$package" ] || fail "Package.swift declares no macOS platform"

# `14.0` — what macOS itself reads before allowing an install.
plist="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist \
  2>/dev/null || true)"
[ -n "$plist" ] || fail "Info.plist has no LSMinimumSystemVersion"
plist_major="${plist%%.*}"

# The two sentences a person reads. Matched loosely on purpose: the prose may
# be reworded, and what has to stay true is the number in it.
readme="$(sed -n 's/.*macOS \([0-9][0-9]*\) or later.*/\1/p' README.md | head -n 1)"
[ -n "$readme" ] || fail "README.md no longer states a minimum macOS"

site="$(sed -n 's/.*macOS \([0-9][0-9]*\) or later.*/\1/p' site/index.html | head -n 1)"
[ -n "$site" ] || fail "site/index.html no longer states a minimum macOS"

for pair in "Info.plist:$plist_major" "README.md:$readme" "site/index.html:$site"; do
  where="${pair%%:*}"
  found="${pair##*:}"
  [ "$found" = "$package" ] \
    || fail "$where says macOS $found, Package.swift says $package"
done

echo "PASS: macOS $package, everywhere that says so"
