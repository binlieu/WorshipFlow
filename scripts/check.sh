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

echo "== OK"
