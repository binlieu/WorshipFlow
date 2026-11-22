#!/bin/bash
# FIX-Q: builds the app (WF_CONFIG=Debug, the default, or WF_CONFIG=Release with the WF_MEASURE measuring condition), runs it once against a
# throw-away library with the FIX-Q hook (UI_SNAPSHOT_FIXQ) and prints what it logged: Next, Previous, Go Live, Blackout and Clear with 200 slides
# and 100 bin items, each repeated (UI_SNAPSHOT_FIXQ_RUNS, default 20): the call's main-thread time, the longest stall, the time from the command to
# the screens being handed the new scene, and the phases of the call. Run by hand; check.sh does not call it. Uses a COPY of the built app under a
# throw-away bundle id, a temporary --library and --silent-audio; the owner's library and saved state are never touched. Stops only the process it
# started. Env: WF_SCRATCH, WF_DERIVED_DATA, WF_CONFIG.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-fixq.XXXXXX")}"
mkdir -p "${SCRATCH:?}"
OUT="$SCRATCH/out"; rm -rf "$OUT"; mkdir -p "$OUT"
DD="${WF_DERIVED_DATA:-$SCRATCH/dd}"
source "$ROOT/scripts/lib-measure-build.sh"
APP_SRC=$(measure_build "$DD" "$SCRATCH/build.log") || exit 1
APP="$SCRATCH/Capture.app"
rm -rf "${APP:?}"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.fixqrun.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "${SCRATCH:?}/library"; mkdir -p "$SCRATCH/library"
# FIXQ_LOOP=next|golive repeats the command 300 times and samples the process (the call tree goes to $SCRATCH/sample.txt) instead of measuring.
LOOPENV=(); [ -n "${FIXQ_LOOP:-}" ] && LOOPENV=(UI_SNAPSHOT_FIXQ_LOOP="$FIXQ_LOOP")
env UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=FIXQ UI_SNAPSHOT_FIXQ=1 ${LOOPENV[@]+"${LOOPENV[@]}"} \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio > "$SCRATCH/run.log" 2>&1 &
PID=$!
if [ -n "${FIXQ_LOOP:-}" ]; then
  for _ in $(seq 1 150); do grep -q "fixq loop .* starts" "$SCRATCH/run.log" 2>/dev/null && break; sleep 2; done
  sample $PID 8 1 -file "$SCRATCH/sample.txt" > /dev/null 2>&1 || true
fi
for _ in $(seq 1 300); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
grep -h "fixq" "$OUT/ui-snapshots.log" 2>/dev/null || { echo "no log; see $SCRATCH/run.log"; tail -20 "$SCRATCH/run.log"; }
