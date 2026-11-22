#!/usr/bin/env python3
"""UI-005h tool: pixel comparison of the app's three role compositions (wf-looks-probe looks) with the panels of docs/UI/screens/07-output-looks.png.
Run by hand; check.sh does not call it. Needs Pillow.

usage: scripts/compare-looks.py <looks dir from wf-looks-probe> <out prefix> [tolerance 0-255, default 24]

The design picture is 2880 wide for a 1440 pt page; its four panels (audience, stage, broadcast fill over a checkerboard, key) are cut out at
2x and the app's 1920 x 1080 pictures are scaled to the same size. The share of pixels whose largest channel differs by more than the tolerance
is printed per panel, also without the corner the app does not draw (the audience watermark). The fill panel is not compared pixel by pixel:
the plate is 86 % opaque and the design's checkerboard is not the preview's. Writes <out prefix>-<panel>.png: design | app | difference."""
import sys
from PIL import Image, ImageChops

DESIGN = 'docs/UI/screens/07-output-looks.png'
# Panel rectangles in the design picture (x0, y0, x1, y1), found by scanning for the panels' outlines.
PANELS = {'audience': (64, 312, 1414, 1071), 'stage': (1466, 312, 2816, 1071), 'broadcast-fill': (64, 1267, 1414, 2026), 'broadcast-key': (1466, 1267, 2816, 2026)}
APP = {'audience': 'audience.png', 'stage': 'stage.png', 'broadcast-fill': 'broadcast-composite.png', 'broadcast-key': 'broadcast-key.png'}

def share(a, b, tol, box=None):
    d = ImageChops.difference(a, b).convert('RGB')
    if box: d = d.crop(box)
    px = list(d.getdata())
    bad = sum(1 for p in px if max(p) > tol)
    return 100.0 * bad / len(px), sum(sum(p) / 3 for p in px) / len(px)

def main():
    if len(sys.argv) < 3: print(__doc__); sys.exit(2)
    src, prefix = sys.argv[1], sys.argv[2]
    tol = int(sys.argv[3]) if len(sys.argv) > 3 else 24
    design = Image.open(DESIGN).convert('RGB')
    for name, box in PANELS.items():
        d = design.crop(box)
        w, h = d.size
        a = Image.open('%s/%s' % (src, APP[name])).convert('RGB').resize((w, h), Image.LANCZOS)
        region = None; note = ''
        if name == 'audience':
            region = None
            full = share(d, a, tol)
            # Without the watermark's corner (the design draws one, the app does not: product decision, listed as open).
            mark = (int(w * 0.90), int(h * 0.82), w, h)
            masked = a.copy(); masked.paste(d.crop(mark), mark[:2])
            sans = share(d, masked, tol)
            print('%-15s differing >%d: %.2f %% of all pixels; %.2f %% without the watermark corner; mean abs difference %.2f' % (name, tol, full[0], sans[0], sans[1]))
        elif name == 'broadcast-fill':
            # The plate is 86 % opaque, so the checkerboard shows through it, and the design's checkerboard (square size and greys) is not the
            # preview's: a pixel difference would measure the checkerboards. The side-by-side is for the eye; the boxes are in compare-rects.py.
            print('%-15s not compared pixel by pixel (the checkerboards differ); see the side-by-side and the rectangles' % name)
        else:
            r = share(d, a, tol)
            print('%-15s differing >%d: %.2f %% of all pixels; mean abs difference %.2f' % (name, tol, r[0], r[1]))
        diff = ImageChops.difference(d, a).convert('L').point(lambda v: 255 if v > tol else int(v * 0.4))
        scale = 640 / w
        size = (640, int(h * scale))
        sheet = Image.new('RGB', (640 * 3 + 20, size[1]), (7, 19, 33))
        sheet.paste(d.resize(size, Image.LANCZOS), (0, 0)); sheet.paste(a.resize(size, Image.LANCZOS), (650, 0)); sheet.paste(diff.convert('RGB').resize(size), (1300, 0))
        sheet.save('%s-%s.png' % (prefix, name), optimize=True)

main()
