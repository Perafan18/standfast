#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="${STANDFAST_WATCHDOG_TEST_FILTER:-RunnerKitTests.watchdogTimeoutSurvivesAStalledGlobalDispatchPool}"
MARKER="STANDFAST_WATCHDOG_POOL_REGRESSION_PASSED"
OUTPUT="$(mktemp "${TMPDIR:-/tmp}/standfast-watchdog.XXXXXX")"

if [ -n "${STANDFAST_WATCHDOG_TEST_FILTER:-}" ]; then
  echo "watchdog test filter override: $FILTER"
fi

cleanup() {
  rm -f -- "$OUTPUT"
}
trap cleanup EXIT

cd "$ROOT"
set +e
STANDFAST_WATCHDOG_POOL_REGRESSION=1 swift test --filter "$FILTER" 2>&1 \
  | tee "$OUTPUT"
pipeline_status=("${PIPESTATUS[@]}")
set -e

[ "${pipeline_status[0]}" -eq 0 ] || exit "${pipeline_status[0]}"
[ "${pipeline_status[1]}" -eq 0 ] || exit "${pipeline_status[1]}"

marker_count="$(grep -Fxc "$MARKER" "$OUTPUT" || true)"
if [ "$marker_count" -ne 1 ]; then
  echo "::error::watchdog regression executed $marker_count times; expected exactly once" >&2
  exit 1
fi

echo "watchdog regression executed exactly once"
