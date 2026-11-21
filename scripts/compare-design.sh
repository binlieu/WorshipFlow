#!/bin/bash
# UI-005a: pixel comparison of an app capture against a design picture. Run by hand; check.sh does not call it.
# Usage: scripts/compare-design.sh <design.png> <app.png> <out-prefix> [tolerance]
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="${TMPDIR:-/tmp}/wf-compare-design"
mkdir -p "$tmp"
if [ ! -x "$tmp/compare-design" ] || [ scripts/compare-design.swift -nt "$tmp/compare-design" ]; then
  swiftc -O scripts/compare-design.swift -o "$tmp/compare-design"
fi
"$tmp/compare-design" "$@"
