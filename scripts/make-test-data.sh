#!/bin/bash
# TESTDATA-001: generates TestData/ (100 solid and 100 gradient 1920x1080 backgrounds, 100 synthetic songs) for performance testing.
# Deterministic (fixed seed). Needs python3 with Pillow. TestData/ is git-ignored: the repository carries no images.
# Put the result into a library with wf-test-data-import (see Packages/WorshipFlowKit/Sources/TestDataImportTool).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -c "import PIL" 2>/dev/null || { echo "Pillow is not installed for python3 (pip3 install pillow)" >&2; exit 1; }
python3 scripts/make-test-data.py "$@"
