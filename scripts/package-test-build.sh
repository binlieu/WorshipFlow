#!/bin/bash
# Builds a Release app and packs it with the tester guide into dist/ for sending to a hardware tester.
# The app is ad-hoc signed (no Apple Developer account): the tester approves it once in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-release"
STAMP="$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
OUT="dist/WORSHIPFLOW-hardware-test-$STAMP"
xcodegen generate --quiet
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" build -quiet
APP="$DD/Build/Products/Release/WORSHIPFLOW.app"
codesign --verify --deep --strict "$APP"
rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUT"
ditto "$APP" "$OUT/WORSHIPFLOW.app"
cp docs/hardware-test-guide.md "$OUT/READ ME FIRST.md"
( cd dist && ditto -c -k --sequesterRsrc --keepParent "$(basename "$OUT")" "$(basename "$OUT").zip" )
echo "Packaged: $OUT.zip"
