#!/bin/bash
# UI-005a: builds the app, runs it once against a throw-away library with the design-capture hook, and compares every picture
# with the design. Run by hand. Output pictures go to $OUT (default: a scratch folder); the numbers are printed.
# The run uses a COPY of the built app under a throw-away bundle id, a temporary --library and --silent-audio, window outputs only;
# nothing of the owner's library or saved state is touched. Stops only the process it started.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCRATCH="${WF_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/wf-design.XXXXXX")}"
mkdir -p "$SCRATCH"
OUT="${OUT:-$SCRATCH/out}"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$SCRATCH/dd" build -quiet > "$SCRATCH/build.log" 2>&1 || { grep -E "error:" "$SCRATCH/build.log" | head -20; exit 1; }
APP_SRC=$(ls -d "$SCRATCH"/dd/Build/Products/Debug/*.app | head -1)
APP="$SCRATCH/Capture.app"
rm -rf "$APP"; cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.worshipflow.designcapture.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
rm -rf "$SCRATCH/library"; LIB="$SCRATCH/library/Library.sqlite"; mkdir -p "$SCRATCH/library"
UI_SNAPSHOT_DIR="$OUT" UI_SNAPSHOT_PREFIX=UI-005a UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_SDI=1 UI_SNAPSHOT_CLIP="$ROOT/TestMedia/loop-1080p5994.mov" \
  "$BIN" --library "$LIB" --silent-audio &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; [ -f "$OUT/ui-snapshots.log" ] && break; sleep 2; done
sleep 2; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
echo "pictures in $OUT"
D=docs/UI/screens
PRE="${CMP_PREFIX:-$OUT/cmp}"
for pair in "01-operator-show:show-dark" "01b-operator-show-quick-edit:show-quick-edit" "09-operator-show-light:show-light" "08-components:components-dark" "10-components-light:components-light"; do
  d="${pair%%:*}"; a="${pair##*:}"
  echo "== $d vs $a"
  scripts/compare-design.sh "$D/$d.png" "$OUT/UI-005a-$a.png" "$PRE-$a" "${TOL:-24}" "$( [[ $d == 08* || $d == 10* ]] && echo components || echo show )"
done
