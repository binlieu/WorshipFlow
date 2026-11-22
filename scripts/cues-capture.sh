#!/bin/bash
# UI-005g: builds the app and runs it once against a throw-away library to capture the Cues mode (cues-dark, cues-light, with their
# rectangle dumps) at 1440 x 900 points. Same arrangement as scripts/design-capture.sh: a COPY of the built app under a throw-away
# bundle id, a temporary --library and --silent-audio, window outputs only; nothing of the real library or saved state is touched.
# Stops only the process it started. Run by hand. Env: WF_SCRATCH (work folder), OUT (pictures), UI_PREFIX (default UI-005g).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-cues.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="${OUT:-$SCRATCH/out}"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$SCRATCH/dd" build -quiet > "$SCRATCH/build.log" 2>&1 || { grep -E "error:" "$SCRATCH/build.log" | head -20; exit 1; }
APP_SRC=$(ls -d "$SCRATCH"/dd/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.cuescapture.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=${UI_PREFIX:-UI-005g} UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_SDI=1 UI_SNAPSHOT_CUESDESIGN=1 \
  UI_SNAPSHOT_CLIP="${CLIP:-$ROOT/TestMedia/loop-1080p5994.mov}" \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures in $OUT"
