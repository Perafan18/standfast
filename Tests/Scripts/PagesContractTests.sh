#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/Scripts/check-site-hosts.sh"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/standfast-pages-contract.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT

failures=0
case_number=0

run_case() {
  local name="$1"
  local expected="$2"
  local html="$3"
  case_number=$((case_number + 1))
  local file="$FIXTURES/case-$case_number.html"
  printf '%s\n' "$html" >"$file"
  local output
  if output="$("$CHECK" "$file" 2>&1)"; then
    if [ "$expected" = pass ]; then
      printf 'PASS: %s\n' "$name"
    else
      printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
      failures=$((failures + 1))
    fi
  elif [ "$expected" = fail ]; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s unexpectedly failed\n%s\n' "$name" "$output" >&2
    failures=$((failures + 1))
  fi
}

run_case "relative subresources and the project's own links are allowed" pass '
  <link rel="canonical" href="https://perafan18.github.io/standfast/">
  <img src="img/a.png" srcset="img/a.png 1x, img/a@2x.png 2x">
  <a href="https://github.com/Perafan18/standfast">Source</a>
  <style>.x { background: url("img/a.png") }</style>
  <script>fetch("/local")</script>
'

run_case "an external srcset is rejected" fail '
  <source srcset="https://cdn.example/a.png 1x">
'

run_case "an external stylesheet resource is rejected" fail '
  <style>@import url("https://fonts.example/site.css");</style>
'

run_case "an external fetch is rejected" fail '
  <script>fetch("https://telemetry.example/collect")</script>
'

run_case "an unexpected outbound link is rejected" fail '
  <a href="https://example.com/elsewhere">Elsewhere</a>
'

run_case "an external script with single quotes is rejected" fail "
  <script src='https://cdn.example/app.js'></script>
"

run_case "an allowed URL on the same line does not launder an external script" fail '
  <link rel="canonical" href="https://perafan18.github.io/standfast/"><script src="https://cdn.example/app.js"></script>
'

run_case "an offsite candidate later in srcset is rejected" fail '
  <source srcset="img/a.png 1x, https://cdn.example/a@2x.png 2x">
'

run_case "an allowed URL inside a query string does not launder the host" fail '
  <script src="https://cdn.example/app.js?next=https://perafan18.github.io/standfast/"></script>
'

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d Pages contract case(s) failed\n' "$failures" >&2
  exit 1
fi

echo "PASS: Pages executable contract"
