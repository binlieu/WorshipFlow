#!/bin/bash
# Builds a Release app and packs it with the tester guide into dist/ for sending to a hardware tester.
# The app is ad-hoc signed (no Apple Developer account): the tester approves it once in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${WF_PACKAGE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-package}"   # its own folder, so packaging never rebuilds an app that is running
STAMP="$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
OUT="${WF_PACKAGE_OUT:-dist/WorshipFlow-hardware-test-$STAMP}"      # WF_PACKAGE_OUT: a scratch location, so a trial run leaves nothing in dist/
xcodegen generate --quiet
# UI-004: the file system ignores case, so an app left from before the rename ("WORSHIPFLOW.app") would keep its capitals on disk
# when the new build is written over it. Remove the old product first so the new one is created as "WorshipFlow.app".
rm -rf "$DD/Build/Products/Release"/*.app
# FIX-S: the derived-data folder holds a "WorshipFlow" app; keep Spotlight and Launchpad from listing it next to the installed one.
mkdir -p "$DD" && touch "$DD/.metadata_never_index"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" build -quiet
APP="$DD/Build/Products/Release/WorshipFlow.app"
[ -d "$APP" ] && ls "$DD/Build/Products/Release" | grep -qx "WorshipFlow.app" || { echo "Expected WorshipFlow.app in the build products" >&2; exit 1; }
# FIX-AC (LIB-004d): the test build carries the King James Version (Bibles/KJV.json, an allow-list of that one name) when this Mac has it, and the
# app is signed again (same identity, entitlements and flags) because a file was added to its Resources. Nothing else from Bibles/ is ever copied.
. scripts/lib-bundle-translations.sh
bundle_translations Bibles "$APP"
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,requirements "$APP"
check_bundled_translations "$APP" || { echo "Refusing to package: see above." >&2; exit 1; }
codesign --verify --deep --strict "$APP"
# FIX-Q: the packaged app must carry none of the measuring hooks (they exist only in Debug or with the WF_MEASURE condition).
if strings "$APP/Contents/MacOS/WorshipFlow" | grep -E 'UI_SNAPSHOT_(DIR|FIXQ)' >/dev/null; then
  echo "The packaged app contains measuring-hook strings (UI_SNAPSHOT_...)" >&2; exit 1
fi
rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUT"
ditto "$APP" "$OUT/WorshipFlow.app"
cp docs/hardware-test-guide.md "$OUT/READ ME FIRST.md"
( cd "$(dirname "$OUT")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$OUT")" "$(basename "$OUT").zip" )
# FIX-S: the unzipped folder holds another "WorshipFlow.app" that Spotlight and Launchpad would list. The zip has the same content; keep only that.
[ -f "$OUT.zip" ] && rm -rf "$OUT"
# The Release app in the derived-data folder is the same app again; the zip is the product, so it goes too.
rm -rf "$DD/Build/Products/Release"/*.app
echo "Packaged: $OUT.zip"
