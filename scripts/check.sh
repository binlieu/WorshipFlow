#!/bin/bash
# Project quality gate: package tests, project generation, app build.
# Exits non-zero on the first failure. Needs no connected video hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== package tests"
swift test --package-path Packages/WorshipFlowKit

echo "== domain boundary"
if grep -rnE '^import (AppKit|SwiftUI|Metal|MetalKit|AVFoundation|CoreVideo|QuartzCore)' Packages/WorshipFlowKit/Sources/Domain; then
  echo "Domain must not import UI, media or hardware frameworks" >&2; exit 1
fi

echo "== generate project"
xcodegen generate --quiet

echo "== app build"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "${WF_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-check}" \
  build -quiet

# FIX-Q: the Release build is part of the gate (compile only). A release-only compile error (a data-race diagnostic the debug compiler does not
# raise) once reached packaging unseen. Its own derived-data folder (next to the Debug one, or WF_DERIVED_DATA_RELEASE): sharing one folder made each
# configuration rebuild the packages for the other, so the Release step took 150 s every run. The build is timed so its cost is visible.
echo "== app build (Release, compile only)"
RELEASE_START=$SECONDS
DD="${WF_DERIVED_DATA_RELEASE:-${WF_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-check}-release}"
xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" build -quiet
echo "release build took $((SECONDS - RELEASE_START)) s"

echo "== the Release app carries none of the measuring hooks"
# The timing hooks are compiled only in Debug or with the WF_MEASURE condition (scripts/lib-measure-build.sh). Their environment names must not be in the shipped binary.
RELEASE_BIN="$(ls -d "$DD"/Build/Products/Release/*.app | head -1)/Contents/MacOS/WorshipFlow"
[ -x "$RELEASE_BIN" ] || { echo "Release binary not found" >&2; exit 1; }
if strings "$RELEASE_BIN" | grep -E 'UI_SNAPSHOT_(DIR|FIXQ)' >/dev/null; then
  echo "The Release app contains measuring-hook strings (UI_SNAPSHOT_...): a hook is not behind DEBUG or WF_MEASURE" >&2; exit 1
fi

echo "== OK"
