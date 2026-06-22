#!/bin/zsh
# Rasterize docs/icon.svg into Resources/AppIcon.icns (run when the SVG changes).
# Uses only built-in macOS tools: QuickLook (qlmanage) to rasterize the SVG, sips to resize,
# and iconutil to assemble the .icns.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/docs/icon.svg"
OUT="$ROOT/Resources/AppIcon.icns"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1024px master from the SVG.
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/icon.svg.png"
[[ -f "$MASTER" ]] || { echo "Failed to rasterize $SVG" >&2; exit 1; }

# Standard iconset: name -> pixel size.
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
typeset -A sizes=(
    icon_16x16.png        16
    icon_16x16@2x.png     32
    icon_32x32.png        32
    icon_32x32@2x.png     64
    icon_128x128.png     128
    icon_128x128@2x.png  256
    icon_256x256.png     256
    icon_256x256@2x.png  512
    icon_512x512.png     512
    icon_512x512@2x.png 1024
)
for name in ${(k)sizes}; do
    sips -z ${sizes[$name]} ${sizes[$name]} "$MASTER" --out "$ICONSET/$name" >/dev/null
done

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
