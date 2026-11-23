#!/bin/bash
# UI-007c: runs the debug build once against a throw-away library with the UI-007c scenario (Layers, lock and hide, Fit, Background fill, a video
# object: poster in Edit, playing on Live, closed on Stop) and prints what it observed. A COPY of the built app under a throw-away bundle id, a
# temporary --library and --silent-audio; nothing of the owner's library or saved state is touched. Stops only the process it started.
# The test clip is read by path from the main checkout's TestMedia (absent from a worktree): set UI_SNAPSHOT_CLIP to another movie to use one.
# usage: WF_DERIVED_DATA=<folder> [WF_SCRATCH=<folder>] [SKIP_BUILD=1] scripts/ui007c-run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-ui007c.XXXXXX")}"
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
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.designcapture.ui007c.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=UI-007c UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_UI007C=1 UI_SNAPSHOT_CLIP="${UI_SNAPSHOT_CLIP:-/Volumes/Storage/chilt/worshipflow/TestMedia/loop-1080p5994.mov}" \
  "$BIN" --library "$SCRATCH/library/Library.sqlite" --silent-audio > "$SCRATCH/run.log" 2>&1 &
PID=$!
for _ in $(seq 1 180); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures and log in $OUT"
grep -h "ui007c" "$OUT/ui-snapshots.log" "$SCRATCH/run.log" 2>/dev/null | sort -u || true
