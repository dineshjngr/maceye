#!/bin/zsh
# Runs the checks in Tests/main.swift. No app is launched and nothing is installed.
# Usage: Scripts/test.sh [folder for comparison pictures]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${MACEYE_BUILD_DIR:-$PWD/build}"
mkdir -p "$OUT/tools"

xcrun swiftc -O \
  Shared/Theme.swift Shared/EyeRenderer.swift \
  MacEye/Config.swift MacEye/EyeLayers.swift \
  Tests/main.swift \
  -o "$OUT/tools/maceye-tests"

"$OUT/tools/maceye-tests" "$@"
