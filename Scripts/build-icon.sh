#!/bin/bash
# Builds the macOS icon family from the checked-in 1024×1024 source.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$ROOT/Resources/AppIcon.png}"
OUTPUT="${2:-$ROOT/.build/Standfast.icns}"

fail() {
  echo "build-icon.sh: $*" >&2
  exit 1
}

[ -f "$SOURCE" ] || fail "$SOURCE is missing"
format="$(sips -g format "$SOURCE" 2>/dev/null | awk '/format:/ { print $2 }')"
[ "$format" = "png" ] || fail "$SOURCE is $format, not PNG"
has_alpha="$(sips -g hasAlpha "$SOURCE" 2>/dev/null | awk '/hasAlpha:/ { print $2 }')"
[ "$has_alpha" = "no" ] || fail "$SOURCE must be an opaque PNG (hasAlpha=$has_alpha)"
dimensions="$(sips -g pixelWidth -g pixelHeight "$SOURCE" 2>/dev/null \
  | awk '/pixelWidth:/ { width = $2 } /pixelHeight:/ { height = $2 } END { print width "x" height }')"
[ "$dimensions" = "1024x1024" ] || fail "$SOURCE is $dimensions, not 1024x1024"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/standfast-icon.XXXXXX")"
ICONSET="$WORK/Standfast.iconset"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"

render() {
  local name="$1"
  local pixels="$2"
  sips -z "$pixels" "$pixels" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
render icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o "$WORK/Standfast.icns"
cp "$WORK/Standfast.icns" "$OUTPUT"
