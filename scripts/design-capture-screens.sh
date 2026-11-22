#!/bin/bash
# UI-005f: captures the Screens mode in the seeded design state (dark and light, with rectangles) from an already built Debug app.
# Usage: WF_DD=<derived data folder of a finished Debug build> [WF_SCRATCH=<folder>] scripts/design-capture-screens.sh
# Run by hand. Runs a COPY of the app under a throw-away bundle id with a temporary --library and --silent-audio, window outputs and
# the simulated card only; nothing of the owner's library is touched; stops only the process it started. Pictures: $OUT (default $WF_SCRATCH/out).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-screens.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="${OUT:-$SCRATCH/out}"
rm -rf "$OUT"; mkdir -p "$OUT"
APP_SRC=$(ls -d "${WF_DD:?set WF_DD}"/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.designcapture.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=UI-005f UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_SDI=1 UI_SNAPSHOT_SCREENS=1 UI_SNAPSHOT_CLIP="${WF_CLIP:-$ROOT/TestMedia/loop-1080p5994.mov}" \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures in $OUT"
