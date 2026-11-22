#!/bin/bash
# FIX-M: builds the debug app, runs it once against a throw-away library with the drag replay hook (UI_SNAPSHOT_FIXM) and prints its numbers.
# Run by hand; check.sh does not call it. Uses a COPY of the built app under a throw-away bundle id, a temporary --library and --silent-audio;
# the owner's library and saved state are never touched. Stops only the process it started. Env: WF_SCRATCH, WF_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-drags.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="$SCRATCH/out"; rm -rf "$OUT"; mkdir -p "$OUT"
DD="${WF_DERIVED_DATA:-$SCRATCH/dd}"
source "$ROOT/scripts/lib-measure-build.sh"
APP_SRC=$(measure_build "$DD" "$SCRATCH/build.log") || exit 1
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.dragmeasure.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=FIXM UI_SNAPSHOT_FIXM=1 \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio > "$SCRATCH/run.log" 2>&1 &
PID=$!
for _ in $(seq 1 240); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
grep -h "fixm\|fixo" "$OUT/ui-snapshots.log" 2>/dev/null || { echo "no log; see $SCRATCH/run.log"; tail -20 "$SCRATCH/run.log"; }
