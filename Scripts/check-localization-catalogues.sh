#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: check-localization-catalogues.sh SOURCE_ROOT APP" >&2
  exit 2
fi

SOURCE_ROOT="$1"
APP="$2"

fail() {
  echo "check-localization-catalogues.sh: $*" >&2
  exit 1
}

for language in en es; do
  source_catalogue="$SOURCE_ROOT/Sources/Standfast/Resources/$language.lproj/Localizable.strings"
  [ -f "$source_catalogue" ] || fail "source $language catalogue is missing"

  for shape in loose nested; do
    case "$shape" in
      loose)
        packaged_catalogue="$APP/Contents/Resources/$language.lproj/Localizable.strings"
        ;;
      nested)
        # Swift Build (the default from Swift 6.4) nests a real macOS bundle;
        # the native build system leaves the catalogues flat inside it.
        nested_root="$APP/Contents/Resources/Standfast_Standfast.bundle"
        if [ -d "$nested_root/Contents/Resources" ]; then
          nested_root="$nested_root/Contents/Resources"
        fi
        packaged_catalogue="$nested_root/$language.lproj/Localizable.strings"
        ;;
    esac

    [ -f "$packaged_catalogue" ] || fail "$shape $language catalogue is missing"
    cmp -s "$source_catalogue" "$packaged_catalogue" \
      || fail "$shape $language catalogue differs from source"
  done
done
