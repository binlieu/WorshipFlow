#!/bin/bash
# OUT-001: generate TestMedia/loop-1080p5994.mov, a 20 s 1920x1080 59.94 fps H.264 clip that loops cleanly.
# Every colour term is periodic over exactly 20 s, so the last frame flows into the first.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }
mkdir -p TestMedia
OUT="TestMedia/loop-1080p5994.mov"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=black:s=1920x1080:r=60000/1001" \
  -vf "format=gbrp,geq=r='128+110*sin(2*PI*(X/W+T/20))':g='128+110*sin(2*PI*(Y/H*2+T/10))':b='128+110*sin(2*PI*(X/W-Y/H-T/20))',format=yuv420p" \
  -frames:v 1199 -c:v libx264 -preset veryfast -crf 18 -profile:v high -pix_fmt yuv420p \
  -r 60000/1001 -movflags +faststart "$OUT"
echo "wrote $OUT"
