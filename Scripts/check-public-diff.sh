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
# sed rather than `${added_lines//$published_home/}`: bash 3.2, which is the
# /bin/bash on every Mac, takes minutes over a diff of a few thousand lines,
# and the CI job running this then looks hung.
scannable_lines="$(printf '%s\n' "$added_lines" | sed "s#${published_home}##g")"
scannable_docs="$(printf '%s\n' "$added_docs" | sed "s#${published_home}##g")"

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

# Binary policy is deliberately narrow: the generated application icon, and the
# website's screenshots. Every other added or modified binary fails closed.
#
# The screenshots are the riskiest files in the repository — they are pictures
# of a real Mac, published on the open web. A window title, a wallpaper, a
# stray path in image metadata leaks whatever it happens to contain, and no
# reviewer reads a PNG. So the strings scan below is not a formality for them:
# it is the only automated thing standing between a capture and the internet.
# The image directory is fixed rather than a pattern so a screenshot cannot be
# dropped somewhere unwatched and inherit the exemption.
#
# The path is read from NUL-delimited numstat output so spaces, tabs, and
# renames cannot disguise an unauthorized binary.
binary_is_allowed() {
  case "$1" in
    Resources/AppIcon.png) return 0 ;;
    site/img/*.png)
      # One directory deep and nothing else: `site/img/a/b.png` is not covered.
      case "${1#site/img/}" in */*) return 1 ;; *) return 0 ;; esac
      ;;
  esac
  return 1
}
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
  if ! binary_is_allowed "$path"; then
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
