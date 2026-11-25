#!/bin/zsh
# Builds MacEye. The finished app is at build/Release/MacEye.app.
#
# Usage: ./build.sh          build
#        ./build.sh run      build, then open the app
#
# Set MACEYE_BUILD_DIR to build somewhere else. Do this if the project lives in a folder
# that iCloud Drive or another sync service manages: those services add file attributes
# to app bundles, and code signing then fails.
set -euo pipefail
cd "$(dirname "$0")"

OUT="${MACEYE_BUILD_DIR:-$PWD/build}"

ICONSET="MacEye/Assets.xcassets/AppIcon.appiconset"
if [[ ! -f "$ICONSET/Contents.json" ]]; then
  echo "Drawing the app icon…"
  mkdir -p "$OUT/tools"
  xcrun swiftc -O Shared/Theme.swift Shared/EyeRenderer.swift Scripts/icon/main.swift -o "$OUT/tools/make_icon"
  "$OUT/tools/make_icon" "$ICONSET"
fi

echo "Building…"
xcodebuild -project MacEye.xcodeproj -target MacEye -configuration Release \
  SYMROOT="$OUT" OBJROOT="$OUT/obj" -quiet build

echo "Built: $OUT/Release/MacEye.app"

if [[ "${1:-}" == "run" ]]; then
  pkill -x MacEye 2>/dev/null || true
  open "$OUT/Release/MacEye.app"
fi
