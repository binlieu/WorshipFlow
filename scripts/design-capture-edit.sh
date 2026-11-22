#!/bin/bash
# UI-005c: builds the app (own derived-data folder), runs it once against a throw-away library with the Edit design capture, and compares the
# app's tagged rectangles with the mockup's (docs/UI/mockups/02-editor.html) through scripts/design-map-edit.json. Run by hand.
# The run uses a COPY of the built app under a throw-away bundle id, a temporary --library and --silent-audio; nothing of the owner's library or
# saved state is touched. Stops only the process it started. Output (pictures, rectangle dumps) goes to $OUT.
# usage: [WF_DERIVED_DATA=<folder>] [WF_SCRATCH=<folder>] [SKIP_BUILD=1] scripts/design-capture-edit.sh [compare-rects options: --all --bad --rects --unmapped]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-design-edit.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="${OUT:-$SCRATCH/out}"
DD="${WF_DERIVED_DATA:-$SCRATCH/dd}"
rm -rf "$OUT"; mkdir -p "$OUT"
if [ -z "${SKIP_BUILD:-}" ]; then
  xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$DD" build -quiet > "$SCRATCH/build.log" 2>&1 || { grep -E "error:" "$SCRATCH/build.log" | head -20; exit 1; }
fi
APP_SRC=$(ls -d "$DD"/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.designcapture.edit.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=UI-005c UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_EDIT=1 UI_SNAPSHOT_SDI=1 UI_SNAPSHOT_CLIP="${UI_SNAPSHOT_CLIP:-$ROOT/TestMedia/loop-1080p5994.mov}" \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures in $OUT"
# The design's rectangles (cached per scratch folder), with the Edit mockup's `div.win.nobar` renamed so compare-rects.py's region rules apply.
DESIGN="$SCRATCH/design-edit.json"
if [ ! -f "$DESIGN" ]; then
  scripts/design-rects docs/UI/mockups/02-editor.html "$SCRATCH/design-raw.json" > /dev/null
  sed 's/div\.win\.nobar\[0\]/div.win[0]/g' "$SCRATCH/design-raw.json" > "$DESIGN"
fi
for mode in dark light; do
  echo "== $mode"
  python3 scripts/compare-rects.py "$DESIGN" "$OUT/UI-005c-edit-$mode.rects.json" scripts/design-map-edit.json "$@"
done
