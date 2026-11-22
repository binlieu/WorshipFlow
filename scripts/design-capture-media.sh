#!/bin/bash
# UI-005d: builds the app, runs it once against a throw-away library with the Media design-capture hook (UI_SNAPSHOT_UIMEDIA) and
# prints the rectangle comparison with scripts/design-map-media.json for dark and light. Run by hand; check.sh does not call it.
# Uses a COPY of the built app under a throw-away bundle id, a temporary --library and --silent-audio; the owner's library and saved
# state are never touched. Stops only the process it started. Env: WF_SCRATCH (scratch folder), WF_DERIVED_DATA (build folder),
# UI_SNAPSHOT_CLIP (a test clip; default TestMedia/loop-1080p5994.mov), COMPARE_ARGS (passed to compare-rects.py, e.g. "--all --bad --rects").
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-media.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="$SCRATCH/out"; rm -rf "$OUT"; mkdir -p "$OUT"
DD="${WF_DERIVED_DATA:-$SCRATCH/dd}"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DD" build -quiet > "$SCRATCH/build.log" 2>&1 || { grep -E "error:" "$SCRATCH/build.log" | head -20; exit 1; }
APP_SRC=$(ls -d "$DD"/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.mediacapture.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
CLIP="${UI_SNAPSHOT_CLIP:-$ROOT/TestMedia/loop-1080p5994.mov}"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=UI-005d UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_UIMEDIA=1 UI_SNAPSHOT_SDI=1 UI_SNAPSHOT_CLIP="$CLIP" \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio &
PID=$!
for _ in $(seq 1 180); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures in $OUT"
[ -f "$SCRATCH/design05.json" ] || scripts/design-rects docs/UI/mockups/05-media-audio.html "$SCRATCH/design05.json" >/dev/null 2>&1
for m in dark light; do
  echo "== media $m"
  python3 scripts/compare-rects.py "$SCRATCH/design05.json" "$OUT/UI-005d-media-$m.rects.json" scripts/design-map-media.json ${COMPARE_ARGS:-}
done
