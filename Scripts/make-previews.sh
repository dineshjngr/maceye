#!/bin/zsh
# Draws the preview pictures used in the README into docs/images.
# They come straight from the eye renderer, so they contain no screen captures.
# Usage: Scripts/make-previews.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${MACEYE_BUILD_DIR:-$PWD/build}"
mkdir -p "$OUT/tools" docs/images

xcrun swiftc -O Shared/Theme.swift Shared/EyeRenderer.swift Scripts/preview/main.swift -o "$OUT/tools/make_previews"
"$OUT/tools/make_previews" docs/images
cp MacEye/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png docs/images/icon.png
