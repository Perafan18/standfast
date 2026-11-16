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
# An HTML parser decodes character references in attribute values before it
# ever sees a URL, so decode the ASCII ones first. Two passes because an
# iframe `srcdoc` is parsed again: `&amp;quot;` becomes `&quot;` for the
# outer document and a real quote for the inner one. Named references are
# matched case-insensitively (&QUOT; is its own entity). Without this,
# `https:&#47;&#47;host` is invisible to every grep.
decoded_text="$(
  perl -0777 -pe '
    for my $pass (1..2) {
      s/&#([0-9]+);?/$1 < 128 ? chr($1) : $&/ge;
      s/&#[xX]([0-9a-fA-F]+);?/hex($1) < 128 ? chr(hex($1)) : $&/ge;
      s/&quot;/"/gi;
      s/&apos;/chr(39)/gei;
      s/&colon;/:/gi;
      s/&sol;/\//gi;
      s/&Tab;/\t/gi;
      s/&NewLine;/\n/gi;
      s/&amp;/&/gi;
    }
  ' "$PAGE"
)"
# JSON and JS string escapes are the next layer a browser decodes before
# loading: an escaped or unicode-escaped solidus is a slash there, and a
# special-scheme URL
# parser also reads a backslash as a slash. Normalise both spellings in the
# scan copies so `extract_urls` judges the host the browser will use.
decoded_text="$(
  printf '%s' "$decoded_text" | perl -0777 -pe '
    s/\\u([0-9a-fA-F]{4})/hex($1) < 128 ? chr(hex($1)) : $&/ge;
    s/\\/\//g;
  '
)"
# CSS and JS also treat a comment as a token separator (`@import/**/"…"`).
# HTML does not: markup between `/*` and `*/` at document level is live. So
# block comments are flattened only in the extra copies used for CSS/JS
# contexts, never in the copies the tag scans read.
# Tags and attributes may be split across lines. The checks below only ever
# extract URLs, never report line numbers, so scan one flattened copy of the
# page instead of letting a newline become a hiding place.
page_text="$(printf '%s' "$decoded_text" | tr '\n' ' ')"
# URL parsers also delete tab and newline characters *inside* a URL, so a
# second copy with those removed catches `https://` split from its host.
compact_text="$(printf '%s' "$decoded_text" | tr -d '\t\r\n')"
code_text="$(printf '%s' "$page_text" | perl -0777 -pe 's{/\*.*?\*/}{ }gs')"
code_compact_text="$(printf '%s' "$compact_text" | perl -0777 -pe 's{/\*.*?\*/}{ }gs')"
# Import maps carry their module URLs as JSON strings, with no attribute or
# call for the context patterns below to anchor on. Pull those blocks out on
# their own so every URL inside one is judged as a load.
importmap_text="$(
  printf '%s' "$decoded_text" | perl -0777 -ne '
    while (/<script\b[^>]*\btype\s*=\s*["\x27]?importmap["\x27]?[^>]*>(.*?)<\/script\s*>/gis) {
      print "$1\n"
    }
  '
)"

# Loading a resource is stricter than linking to it: GitHub is a fine place
# for a reader to choose to go, and no place for this page to fetch code,
# fonts or images from. `srcset`, CSS and the network APIs are load paths
# just as much as a plain `src`.
# Extract each URL on its own before applying the one-host allowance. A
# line-level filter would let an allowed canonical or OG URL launder any
# other load sharing its line or hiding in its query string, and a srcset
# has to be read candidate by candidate rather than only at its first URL.
extract_urls() {
  # Case-insensitive like the context greps that feed it: a browser reads
  # `HTTPS://` exactly as happily as the lowercase spelling, and a leading
  # `//` inherits this page's HTTPS scheme on GitHub Pages.
  grep -oiE "(((https?|wss?)://)|//)[^\"'[:space:],)]+" || true
}

single_url_pattern="(<(script|link|img|source|video|audio|iframe|embed|object|track|input|base)[^>]+(src|href|data|poster)[[:space:]]*=[[:space:]]*${quote_class}?[[:space:]]*(https?://|//)[^\"'[:space:]]*)"
srcset_pattern="(<(img|source)[^>]+srcset[[:space:]]*=[[:space:]]*\"[^\"]*\"|<(img|source)[^>]+srcset[[:space:]]*=[[:space:]]*'[^']*'|<(img|source)[^>]+srcset[[:space:]]*=[[:space:]]*[^\"'[:space:]>]+)"
context_pattern="((url\(|fetch\(|WebSocket\(|EventSource\(|import[[:space:]]*\(|Worker[[:space:]]*\(|SharedWorker[[:space:]]*\(|addModule[[:space:]]*\(|serviceWorker[[:space:]]*\.[[:space:]]*register[[:space:]]*\()[^)]*|@import[[:space:]]*\"[^\"]*\"|@import[[:space:]]*'[^']*'|import[[:space:]]*${quote_class}[^\"']*${quote_class}|from[[:space:]]*${quote_class}[^\"']*${quote_class})"

load_urls="$(
  {
    printf '%s' "$page_text" | grep -oiE "$single_url_pattern" || true
    printf '%s' "$page_text" | grep -oiE "$srcset_pattern" || true
    printf '%s' "$page_text" | grep -oiE "$context_pattern" || true
    printf '%s' "$compact_text" | grep -oiE "$single_url_pattern" || true
    printf '%s' "$compact_text" | grep -oiE "$srcset_pattern" || true
    printf '%s' "$compact_text" | grep -oiE "$context_pattern" || true
    printf '%s' "$code_text" | grep -oiE "$context_pattern" || true
    printf '%s' "$code_compact_text" | grep -oiE "$context_pattern" || true
    printf '%s' "$importmap_text"
  } | extract_urls | sort -u
)"
subresources="$(
  printf '%s\n' "$load_urls" \
    | grep -viE '^((https?:)?//)perafan18\.github\.io/' || true
)"
note_matches "external subresources:" "$subresources"

links="$(
  {
    printf '%s' "$page_text" \
      | grep -oiE "href[[:space:]]*=[[:space:]]*${quote_class}[[:space:]]*((https?:)?//)[^\"']*${quote_class}" || true
    printf '%s' "$compact_text" \
      | grep -oiE "href[[:space:]]*=[[:space:]]*${quote_class}[[:space:]]*((https?:)?//)[^\"']*${quote_class}" || true
  } | grep -vEi "${quote_class}[[:space:]]*((https?:)?//)(github\\.com|perafan18\\.github\\.io)/" || true
)"
note_matches "unexpected outbound links:" "$links"

if [ -n "$failures" ]; then
  echo "FAIL: the page depends on an unexpected host:" >&2
  printf '%s\n' "$failures" >&2
  exit 1
fi

echo "PASS: the page depends on no other host"
