#!/usr/bin/env python3
"""UI-005f: runs scripts/compare-rects.py for the Screens mockup (03). Two things differ from Show: the mockup's root is `.win.nobar`, and
its regions are different. This wrapper renames the root in the design dump and puts the elements in the Screens regions:
toolbar, list (the left column), map (header, diagram, footer), form (selected screen header and fields), stats (counters), previews.
Same arguments and output as compare-rects.py (the region names are printed in place of its Show names).

usage: scripts/compare-rects-screens.py <design.json> <app.rects.json> [--top N] [--all] [--bad] [--rects] [--unmapped]
"""
import importlib.util, io, json, os, re, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('compare_rects', os.path.join(here, 'compare-rects.py'))
cr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cr)

def region(path):
    if path.startswith('div.tb'): return 'toolbar'          # the toolbar
    if path.startswith('div.body[1]>div.side[0]'): return 'sidebar'      # printed as "list"
    if path.startswith('div.body[1]>div.main[1]>div.bar[0]') or path.startswith('div.body[1]>div.main[1]>div.map[1]') or path.startswith('div.body[1]>div.main[1]>div.row[2]'): return 'centre'      # "map"
    if path.startswith('div.body[1]>div.main[1]>div.stat[6]'): return 'inspector'      # "stats"
    if path.startswith('div.body[1]>div.main[1]>div[7]'): return 'transport'      # "previews"
    if path.startswith('div.body[1]>div.main[1]'): return 'dock'      # "form" (the selected screen's header and fields)
    return 'window'
cr.region = region
NAMES = {'sidebar': 'list', 'centre': 'map', 'dock': 'form', 'inspector': 'stats', 'transport': 'previews'}

def main(argv):
    design = json.load(open(argv[0]))
    for e in design:
        e['path'] = e['path'].replace('div.win.nobar[0]', 'div.win[0]')
    tmp = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False)
    json.dump(design, tmp); tmp.close()
    mp = os.path.join(here, 'design-map-screens.json')
    rest = argv[2:]
    out = io.StringIO(); old = sys.stdout; sys.stdout = out
    try:
        cr.main([tmp.name, argv[1], mp] + rest)
    finally:
        sys.stdout = old; os.unlink(tmp.name)
    text = out.getvalue()
    for k, v in NAMES.items():
        text = re.sub(r'(?m)^(  )?%s(?=\s)' % k, lambda m: (m.group(1) or '') + v, text)
    print(text, end='')

if __name__ == '__main__':
    main(sys.argv[1:])
