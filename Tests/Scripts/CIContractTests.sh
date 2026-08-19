#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
WORKFLOW=.github/workflows/ci.yml

# Nothing in this workflow is rented. Decided on 2026-08-19: the minimum-OS
# watchdog was the last GitHub-hosted job, and it went with the rest.
#
# What that gave up, written here because a deleted job leaves no trace of
# itself: this project no longer compiles under an older Xcode, nor runs
# anything on an actual macOS 14. Both have bitten it before — the Swift 6
# interoperability failures with `UserNotifications` were exactly that class.
# What survives is compile-time availability: `Package.swift` targets
# `.macOS(.v14)`, so an API newer than the deployment target still fails the
# build, on every machine, for free.
rented="$(awk '
  /^  [[:alnum:]_-]+:$/ { job = $1 }
  /runs-on:/ && !/self-hosted/ { print job, $0 }
' "$WORKFLOW")"
if [ -n "$rented" ]; then
  echo "FAIL: these jobs still rent a runner:" >&2
  printf '  %s\n' "$rented" >&2
  exit 1
fi

# The regression itself did not go anywhere. It is the reason that job existed,
# and it runs on every push — just on a Mac that is already paid for.
grep -q 'RunWatchdogRegression.sh' "$WORKFLOW" \
  || { echo "FAIL: nothing runs the watchdog regression any more" >&2; exit 1; }

# ── Where the work runs ──────────────────────────────────────────────────────
#
# The premise of the product, applied to the product: these are Pedro's Macs,
# and a build of Standfast has no business paying GitHub to rent one. It also
# stopped being affordable — three GitHub-hosted macOS jobs on every push spent
# 236 minutes in August and exhausted the account's Actions budget.
#
# There is no exception any longer: the minimum-OS watchdog was the last rented
# job and went with the rest on 2026-08-19. What that gave up is written above
# the `rented` check below.
for job in test package hygiene; do
  runner="$(awk -v job="  $job:" '
    $0 == job { found = 1; next }
    found && /^  [[:alnum:]_-]+:$/ { exit }
    found && /runs-on:/ { $1 = ""; print; exit }
  ' "$WORKFLOW" | tr -d ' ')"
  case "$runner" in
    *self-hosted*) ;;
    *)
      echo "FAIL: job '$job' runs on '${runner:-missing}', not the self-hosted Mac" >&2
      exit 1
      ;;
  esac
done

# The packaging job's subject is the *fallback* signature: that a build with no
# Developer ID still gets a real bundle identity, and that `notarize.sh` refuses
# to send it to Apple. On a GitHub runner that came free, because there was no
# certificate to find. On the release manager's own Mac there is one, and
# without this the job would sign every throwaway build with the release
# certificate and then fail its own next step for the reason that the bundle
# was not ad-hoc after all.
package_block="$(awk '
  /^  package:$/ { found = 1; next }
  found && /^  [[:alnum:]_-]+:$/ { exit }
  found { print }
' "$WORKFLOW")"
if ! printf '%s' "$package_block" | grep -q 'SIGN_IDENTITY: "-"'; then
  echo "FAIL: the packaging job no longer forces an ad-hoc signature" >&2
  exit 1
fi

echo "PASS"
