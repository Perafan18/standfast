#!/bin/bash
# Fails when newly added lines expose local workspace or private knowledge-base
# references. Existing history stays outside the contract by design.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
DIFF_SCOPE="${1:-main...HEAD}"

if ! git rev-parse --verify "${DIFF_SCOPE%%.*}^{commit}" >/dev/null 2>&1; then
  echo "FAIL: cannot resolve diff scope: $DIFF_SCOPE" >&2
  exit 1
fi

added_lines="$(
  git diff --unified=0 "$DIFF_SCOPE" -- . \
    | sed -n '/^+++ /d; /^+/s/^+//p'
)"
added_docs="$(
  git diff --unified=0 "$DIFF_SCOPE" -- '*.md' '*.html' \
    | sed -n '/^+++ /d; /^+/s/^+//p'
)"

# Split the markers so this executable contract does not introduce the very
# strings it rejects from the public diff.
p1="/""Users/"
p2="Obsi""dian"
p3="va""ult"
p4="iC""loud"
p5="[""["

matches=""
for marker in "$p1" "$p2" "$p3" "$p4"; do
  found="$(printf '%s\n' "$added_lines" | grep -Fni "$marker" || true)"
  if [ -n "$found" ]; then
    matches="${matches}${matches:+$'\n'}${found}"
  fi
done
found="$(printf '%s\n' "$added_docs" | grep -Fni "$p5" || true)"
if [ -n "$found" ]; then
  matches="${matches}${matches:+$'\n'}${found}"
fi

if [ -n "$matches" ]; then
  echo "FAIL: public diff introduces private workspace references:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "PASS: public diff contains no private workspace references"
