#!/bin/bash
# Builds a Release app and packs it with the tester guide into dist/ for sending to a hardware tester.
# The app is ad-hoc signed (no Apple Developer account): the tester approves it once in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-package"   # its own folder, so packaging never rebuilds an app that is running
STAMP="$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
OUT="dist/WorshipFlow-hardware-test-$STAMP"
xcodegen generate --quiet
# UI-004: the file system ignores case, so an app left from before the rename ("WORSHIPFLOW.app") would keep its capitals on disk
# when the new build is written over it. Remove the old product first so the new one is created as "WorshipFlow.app".
rm -rf "$DD/Build/Products/Release"/*.app
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" build -quiet
APP="$DD/Build/Products/Release/WorshipFlow.app"
[ -d "$APP" ] && ls "$DD/Build/Products/Release" | grep -qx "WorshipFlow.app" || { echo "Expected WorshipFlow.app in the build products" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUT"
ditto "$APP" "$OUT/WorshipFlow.app"
cp docs/hardware-test-guide.md "$OUT/READ ME FIRST.md"
( cd dist && ditto -c -k --sequesterRsrc --keepParent "$(basename "$OUT")" "$(basename "$OUT").zip" )
echo "Packaged: $OUT.zip"
