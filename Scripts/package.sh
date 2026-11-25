#!/bin/zsh
# Builds MacEye and packs it into a zip file for a release.
# Usage: Scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${MACEYE_BUILD_DIR:-$PWD/build}"
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MacEye.xcodeproj/project.pbxproj | head -1)

./build.sh

APP="$OUT/Release/MacEye.app"
ZIP="$OUT/MacEye-$VERSION.zip"

codesign --verify --deep --strict "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Package: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
