#!/bin/bash
# Fails when newly added lines expose local workspace or private knowledge-base
# references. Existing history stays outside the contract by design.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
DIFF_SCOPE="${1:-main...HEAD}"

added_lines="$(
  # A distinct content indicator cannot be confused with either a diff header
  # or source content beginning with one or more plus signs. `git diff` also
  # owns validation of the complete range, including ref names containing dots.
  git diff --unified=0 --output-indicator-new='>' "$DIFF_SCOPE" -- . \
    | sed -n '/^>/s/^>//p'
)"
added_docs="$(
  git diff --unified=0 --output-indicator-new='>' "$DIFF_SCOPE" -- '*.md' '*.html' \
    | sed -n '/^>/s/^>//p'
)"

# Split the markers so this executable contract does not introduce the very
# strings it rejects from the public diff.
p1="/""Users/"
p2="Obsi""dian"
p3="va""ult"
p4="iC""loud"
p5="[""["

# One home directory is published on purpose. The website shows a real
# LaunchAgent, and a plist's `WorkingDirectory` is absolute — writing it with a
# tilde would make the figure wrong, and this project does not put a convenient
# lie in front of a reader. `ci` is a placeholder, alongside the invented
# organisation in the same figure.
#
# The exemption is this exact prefix and nothing else, removed before the scan.
# A longer name that merely begins the same way keeps its leading marker and
# still fails, because the trailing separator is part of what is removed; so
# does any real home. It is deliberately not applied to the binary scan below —
# the icon has no reason to name a home directory at all.
published_home="/""Users/ci/"
scannable_lines="${added_lines//$published_home/}"
scannable_docs="${added_docs//$published_home/}"

matches=""
for marker in "$p1" "$p2" "$p3" "$p4"; do
  found="$(printf '%s\n' "$scannable_lines" | grep -Fni "$marker" || true)"
  if [ -n "$found" ]; then
    matches="${matches}${matches:+$'\n'}${found}"
  fi
done
found="$(printf '%s\n' "$scannable_docs" | grep -Fni "$p5" || true)"
if [ -n "$found" ]; then
  matches="${matches}${matches:+$'\n'}${found}"
fi

# Binary policy is deliberately narrow. The generated application icon is the
# only binary artifact kept in this repository; every other added or modified
# binary fails closed. Printable strings from the icon, including textual image
# metadata, are checked against the same private-reference markers. The path is
# read from NUL-delimited numstat output so spaces, tabs, and renames cannot
# disguise an unauthorized binary.
while IFS=$'\t' read -r -d '' added deleted path; do
  if [ -z "$path" ]; then
    # With `-z`, a rename is encoded as an empty path followed by the old and
    # new paths in separate NUL-delimited fields. Policy applies to its target.
    IFS= read -r -d '' _old_path
    IFS= read -r -d '' path
  fi
  if [ "$added" != "-" ] || [ "$deleted" != "-" ]; then
    continue
  fi
  if [ "$path" != "Resources/AppIcon.png" ]; then
    echo "FAIL: public diff introduces unauthorized binary: $path" >&2
    exit 1
  fi
  if [ ! -f "$path" ]; then
    echo "FAIL: allowed binary must remain present: $path" >&2
    exit 1
  fi
  if ! binary_strings="$(strings "$path")"; then
    echo "FAIL: could not inspect allowed binary: $path" >&2
    exit 1
  fi
  for marker in "$p1" "$p2" "$p3" "$p4"; do
    found="$(printf '%s\n' "$binary_strings" | grep -Fni "$marker" || true)"
    if [ -n "$found" ]; then
      matches="${matches}${matches:+$'\n'}binary $path: ${found}"
    fi
  done
done < <(git diff --numstat -z --find-renames "$DIFF_SCOPE" -- .)

if [ -n "$matches" ]; then
  echo "FAIL: public diff introduces private workspace references:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "PASS: public diff contains no private workspace references"
