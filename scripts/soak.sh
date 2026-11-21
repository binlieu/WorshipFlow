#!/bin/bash
# Phase 0 timing check (NFR-01). Run when the chosen display is free: it covers that display for the duration.
# Usage: scripts/soak.sh [seconds=3600] [screen-index=1]
# Set the display to 60 Hz first (System Settings > Displays), or the result does not count.
set -euo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-3600}"; SCREEN="${2:-1}"
DD="$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-release"
[ -f TestMedia/loop-1080p5994.mov ] || ./scripts/make-test-media.sh
xcodegen generate --quiet
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" build -quiet
REPORT="AI/reports/soak-screen${SCREEN}-${SECS}s-$(date +%Y%m%d-%H%M).log"
"$DD/Build/Products/Release/WORSHIPFLOW.app/Contents/MacOS/WORSHIPFLOW" \
  --soak "$SECS" --screen "$SCREEN" --video "$PWD/TestMedia/loop-1080p5994.mov" --report "$PWD/$REPORT"
echo "Report: $REPORT"
