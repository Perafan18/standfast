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

run_case "an uppercase scheme is still an external load" fail '
  <script src="HTTPS://cdn.example/app.js"></script>
'

run_case "an unquoted srcset is still inspected" fail '
  <source srcset=https://cdn.example/a.png>
'

run_case "an external load split across lines is rejected" fail '
  <script
    src="https://cdn.example/app.js"></script>
'

run_case "a protocol-relative external load is rejected" fail '
  <script src="//cdn.example/app.js"></script>
'

run_case "an external base retargeting relative loads is rejected" fail '
  <base href=https://cdn.example/assets/>
  <img src="a.png">
'

run_case "a newline inside a URL does not hide its host" fail '
  <script src="https://
cdn.example/app.js"></script>
'

run_case "a parenthesis-free CSS import does not drag later links in" pass '
  <style>@import "local.css";</style>
  <a href="https://github.com/Perafan18/standfast">Source</a>
'

run_case "HTML entities in a URL do not hide its host" fail '
  <script src="https:&#47;&#47;cdn.example/app.js"></script>
'

run_case "an entity-encoded scheme is still an external load" fail '
  <script src="&#104;ttps://cdn.example/app.js"></script>
'

run_case "leading space inside a quoted URL is still an external load" fail '
  <script src=" https://cdn.example/app.js"></script>
'

run_case "a static module import is an external load" fail '
  <script type="module">import "https://cdn.example/app.js";</script>
'

run_case "a dynamic module import is an external load" fail '
  <script type="module">await import("https://cdn.example/app.js");</script>
'

run_case "numeric entities without semicolons do not hide a host" fail '
  <script src="https:&#47&#47cdn.example/app.js"></script>
'

run_case "a spaced dynamic import is still an external load" fail '
  <script type="module">await import ("https://cdn.example/app.js");</script>
'

run_case "quote entities inside srcdoc do not hide a script host" fail '
  <iframe srcdoc="<script src=&quot;https://cdn.example/app.js&quot;></script>"></iframe>
'

run_case "uppercase and double-encoded quote entities do not hide a host" fail '
  <iframe srcdoc="<script src=&amp;quot;https://cdn.example/app.js&QUOT;></script>"></iframe>
'

run_case "a CSS import without a space is still an external load" fail '
  <style>@import"https://cdn.example/site.css";</style>
'

run_case "a CSS import separated by a comment is still an external load" fail '
  <style>@import/**/"https://cdn.example/site.css";</style>
'

run_case "a module import without a space is still an external load" fail '
  <script type="module">import"https://cdn.example/app.js";</script>
'

run_case "a video poster is an external load" fail '
  <video poster="https://cdn.example/poster.png"></video>
'

run_case "HTML between slash-star markers is still live markup" fail '
  /* <script src="https://cdn.example/app.js"></script> */
'

run_case "an import map module is an external load" fail '
  <script type="importmap">{"imports":{"app":"https://cdn.example/app.js"}}</script>
  <script type="module">import "app";</script>
'

run_case "a Worker module is an external load" fail '
  <script>new Worker("https://cdn.example/worker.js");</script>
'

run_case "a SharedWorker module is an external load" fail '
  <script>new SharedWorker("https://cdn.example/worker.js");</script>
'

run_case "JSON slash escapes in an import map do not hide its host" fail '
  <script type="importmap">{"imports":{"app":"https:\/\/cdn.example\/app.js"}}</script>
'

run_case "JSON unicode escapes in an import map do not hide its host" fail '
  <script type="importmap">{"imports":{"app":"https:\u002f\u002fcdn.example/app.js"}}</script>
'

run_case "escaped backslashes in a fetch URL do not hide its host" fail '
  <script>fetch("https:\\/\\/cdn.example/x")</script>
'

run_case "an escaped script close does not truncate an import map" fail '
  <script type="importmap">{"imports":{"x":"<\/script>","app":"https://cdn.example/app.js"}}</script>
'

run_case "a unicode greater-than escape does not invent a tag boundary" fail '
  <script data-x="&#92;u003e" src="https://cdn.example/app.js"></script>
'

run_case "JS hex escapes in a fetch URL do not hide its host" fail '
  <script>fetch("https:\x2f\x2fcdn.example/x")</script>
'

run_case "CSS hex escapes in an import URL do not hide its host" fail '
  <style>@import url("https:\2f\2fcdn.example/site.css");</style>
'

run_case "backslashes in an attribute URL do not hide its host" fail '
  <script src="https:\\cdn.example/app.js"></script>
'

run_case "a backslash protocol-relative attribute URL does not hide its host" fail '
  <img src="\\cdn.example/a.png">
'

run_case "an escaped newline inside a fetch URL does not hide its host" fail '
  <script>fetch("https:\u000a\u002f\u002fcdn.example/x")</script>
'

run_case "an escaped greater-than does not cut off a backslash src" fail '
  <script data-x="\u003e" src="https:\\cdn.example/app.js"></script>
'

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d Pages contract case(s) failed\n' "$failures" >&2
  exit 1
fi

echo "PASS: Pages executable contract"
