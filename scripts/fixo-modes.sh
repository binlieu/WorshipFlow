#!/bin/bash
# FIX-O: builds the debug app, runs it once against a throw-away library with the mode-by-mode show hook (UI_SNAPSHOT_FIXO_MODES) and prints, per mode and command, what did not follow.
# Run by hand; check.sh does not call it. Uses a COPY of the built app under a throw-away bundle id, a temporary --library and --silent-audio;
# the owner's library and saved state are never touched. Stops only the process it started. Env: WF_SCRATCH, WF_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-modes.XXXXXX")}"
mkdir -p "${SCRATCH:?}/out/x"
OUT="${SCRATCH:?}/out"
rmdir "$OUT/x"
rm -f "$OUT/ui-snapshots.log"
DD="${WF_DERIVED_DATA:-${SCRATCH:?}/dd}"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DD" build -quiet > "$SCRATCH/build.log" 2>&1 || { grep -E "error:" "$SCRATCH/build.log" | head -20; exit 1; }
APP_SRC=$(ls -d "$DD"/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "${APP:?}"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.modesrun.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "${SCRATCH:?}/library"; mkdir -p "$SCRATCH/library"
# Started directly (the screen may be locked: the app then never becomes active, and the hook delivers its mouse events to the view under the
# pointer itself instead of through the window, see RealPointer.directToView). Stops only the process it started.
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=FIXO_MODES UI_SNAPSHOT_FIXO_MODES=1 \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio > "$SCRATCH/run.log" 2>&1 &
PID=$!
for _ in $(seq 1 240); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
grep -h "fixo-modes" "$OUT/ui-snapshots.log" 2>/dev/null || { echo "no log; see $SCRATCH/run.log"; tail -20 "$SCRATCH/run.log"; }
