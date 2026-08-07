#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
WORKFLOW=.github/workflows/ci.yml

watchdog_contract="$({
  awk '
    /^  watchdog-macos-14:$/ { in_job = 1; next }
    in_job && /^  [[:alnum:]_-]+:$/ { exit }
    in_job && /^    runs-on:/ { runner = $2; next }
    in_job && /- name: Build watchdog test bundle/ { in_step = 1; next }
    in_step && /- name:/ { in_step = 0 }
    in_step && /timeout-minutes:/ { timeout = $2 }
    END { print runner "|" timeout }
  ' "$WORKFLOW"
} || true)"

if [ "$watchdog_contract" != "macos-14|30" ]; then
  echo "FAIL: macOS 14 watchdog job contract is '${watchdog_contract:-missing}', expected macos-14|30" >&2
  exit 1
fi

echo "PASS"
