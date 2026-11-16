#!/bin/bash
# Fails when the published page loads a subresource from another host, calls
# one from inline code, or links somewhere other than this project's GitHub
# home and the site's own address.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
PAGE="${1:-site/index.html}"

failures=""

note_matches() {
  local label="$1"
  local found="$2"
  if [ -n "$found" ]; then
    if [ -n "$failures" ]; then
      failures+=$'\n'
    fi
    failures+="$label"
    failures+=$'\n'
    failures+="$found"
  fi
}

quote_class='["'\'']'

# Loading a resource is stricter than linking to it: GitHub is a fine place
# for a reader to choose to go, and no place for this page to fetch code,
# fonts or images from. `srcset`, CSS and the network APIs are load paths
# just as much as a plain `src`.
subresource_pattern="(<(script|link|img|source|video|audio|iframe|embed|object|track|input)[^>]+(src|href|srcset|data)[[:space:]]*=[[:space:]]*${quote_class}?https?://)"
subresource_pattern+="|(url\\([[:space:]]*${quote_class}?https?://)"
subresource_pattern+="|(@import[[:space:]]+(url\\([[:space:]]*)?${quote_class}?https?://)"
subresource_pattern+="|((fetch|WebSocket|EventSource)\\([[:space:]]*${quote_class}(https?|wss?)://)"

subresources="$(
  grep -inE "$subresource_pattern" "$PAGE" \
    | grep -vE 'https://perafan18\.github\.io/' || true
)"
note_matches "external subresources:" "$subresources"

links="$(
  grep -oiE "href[[:space:]]*=[[:space:]]*${quote_class}https?://[^\"']*${quote_class}" "$PAGE" \
    | grep -vEi "${quote_class}https://(github\\.com|perafan18\\.github\\.io)/" || true
)"
note_matches "unexpected outbound links:" "$links"

if [ -n "$failures" ]; then
  echo "FAIL: the page depends on an unexpected host:" >&2
  printf '%s\n' "$failures" >&2
  exit 1
fi

echo "PASS: the page depends on no other host"
