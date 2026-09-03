#!/usr/bin/env bash
# Rasterizes assets/icon/hubble_icon.svg to the PNGs flutter_launcher_icons
# expects, then regenerates platform icons. Requires rsvg-convert or
# ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."
src=assets/icon/hubble_icon.svg
out=assets/icon/hubble_icon.png
if command -v rsvg-convert >/dev/null; then
  rsvg-convert -w 1024 -h 1024 "$src" -o "$out"
elif command -v magick >/dev/null; then
  magick -background none "$src" -resize 1024x1024 "$out"
elif command -v convert >/dev/null; then
  convert -background none "$src" -resize 1024x1024 "$out"
else
  echo "install librsvg (rsvg-convert) or ImageMagick" >&2
  exit 1
fi
dart run flutter_launcher_icons
echo "icons regenerated from $src"
