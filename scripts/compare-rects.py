#!/usr/bin/env python3
"""UI-005j tool 3: compares the design's rectangles (scripts/design-rects) with the app's (the ui-snapshots dump, App/Sources/DesignProbe.swift)
through a mapping file (scripts/design-map-show.json). Run by hand; check.sh does not call it.

usage: scripts/compare-rects.py <design.json> <app.rects.json> <map.json> [--top N] [--all] [--region NAME] [--rects] [--bad] [--unmapped]

Mapping file: {"entries": [{"d": "<design path without the leading div.win[0]>>", "a": "<app identifier>"}],
               "ignore_design": [{"match": "<regex on the design path>", "reason": "..."}],
               "ignore_app": [{"match": "<regex on the app identifier>", "reason": "..."}]}
Every design element must be mapped or matched by an ignore_design rule (with its reason); every app identifier that is not mapped is
listed (an owner's extra or a defect). The edges compared are left, top, right and bottom in points; an element is "within 1 point" when
all four differ by at most 1.0. Font size, weight and radius are compared where the app declares them at the tag site.
"""
import json, re, sys

def load(path): return json.load(open(path))

def region(path):
    if path.startswith('div.tb'): return 'toolbar'
    if path.startswith('div.tp'): return 'transport'
    if 'div.dock' in path: return 'dock'
    if path.startswith('div.body[1]>div.side.r'): return 'inspector'
    if path.startswith('div.body[1]>div.side'): return 'sidebar'
    if path.startswith('div.body[1]>div.main'): return 'centre'
    return 'window'

def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    opts = {a: True for a in argv if a.startswith('--')}
    top = 5
    if '--top' in argv:
        i = argv.index('--top'); top = int(argv[i + 1]); args.remove(argv[i + 1]); opts.pop('--top', None)
    only = None
    if '--region' in argv:
        i = argv.index('--region'); only = argv[i + 1]; args.remove(argv[i + 1])
    design = load(args[0])
    app_doc = load(args[1])
    mp = load(args[2])
    app = {r['id']: r for r in app_doc['rects']}
    by_path = {}
    for e in design:
        p = e['path']
        if p.startswith('div.win[0]>'): p = p[len('div.win[0]>'):]
        elif p == 'div.win[0]': p = ''
        by_path[p] = e
    rows = []
    mapped_design, mapped_app = set(), set()
    missing = []
    for ent in mp['entries']:
        d = by_path.get(ent['d']); a = app.get(ent['a'])
        if d is None:
            print('MAP ERROR: design path not found:', ent['d'], file=sys.stderr); continue
        mapped_design.add(ent['d'])
        if a is None:
            missing.append(ent); continue
        mapped_app.add(ent['a'])
        edges = [a['x'] - d['x'], a['y'] - d['y'], (a['x'] + a['w']) - (d['x'] + d['w']), (a['y'] + a['h']) - (d['y'] + d['h'])]
        skip = ent.get('skip', '')      # edges not compared because the content differs (the entry says why)
        worst = max(abs(v) for i, v in enumerate(edges) if 'LTRB'[i] not in skip)
        issues = []
        if 'fontSize' in a and 'fontSize' in d and ent.get('font', True) and abs(a['fontSize'] - d['fontSize']) > 0.01: issues.append('font %.0f vs %.0f' % (a['fontSize'], d['fontSize']))
        if 'fontWeight' in a and 'fontWeight' in d and ent.get('font', True) and abs(a['fontWeight'] - d['fontWeight']) > 0.01: issues.append('weight %.0f vs %.0f' % (a['fontWeight'], d['fontWeight']))
        if 'radius' in a and abs(a['radius'] - min(d['radius'], d['w'] / 2, d['h'] / 2)) > 0.5 and ent.get('radius', True): issues.append('radius %.1f vs %.1f' % (a['radius'], min(d['radius'], d['w'] / 2, d['h'] / 2)))
        rows.append({'d': ent['d'], 'a': ent['a'], 'region': region(ent['d']), 'edges': edges, 'worst': worst, 'ok': worst <= 1.0 + 1e-6 and not issues,
                     'pos_ok': worst <= 1.0 + 1e-6, 'issues': issues, 'text': by_path[ent['d']].get('text', ''),
                     'dr': (d['x'], d['y'], d['w'], d['h']), 'ar': (a['x'], a['y'], a['w'], a['h'])})
    ign = [(re.compile(r['match']), r['reason']) for r in mp.get('ignore_design', [])]
    unmapped_design = []
    for p, e in by_path.items():
        if p in mapped_design or p == '': continue
        why = next((reason for rx, reason in ign if rx.search(p)), None)
        unmapped_design.append((p, e, why))
    iga = [(re.compile(r['match']), r['reason']) for r in mp.get('ignore_app', [])]
    unmapped_app = []
    for i in sorted(app):
        if i in mapped_app: continue
        why = next((reason for rx, reason in iga if rx.search(i)), None)
        unmapped_app.append((i, why))
    regions = ['toolbar', 'sidebar', 'centre', 'dock', 'inspector', 'transport']
    print('%-10s %7s %9s %9s' % ('region', 'mapped', 'within 1', 'all ok'))
    tot = [0, 0, 0]
    for r in regions:
        rr = [x for x in rows if x['region'] == r]
        n, p, k = len(rr), sum(1 for x in rr if x['pos_ok']), sum(1 for x in rr if x['ok'])
        tot[0] += n; tot[1] += p; tot[2] += k
        print('%-10s %7d %9d %9d' % (r, n, p, k))
    print('%-10s %7d %9d %9d' % ('total', *tot))
    if missing: print('\nmapped but not drawn in the app (%d):' % len(missing)); [print('  ', m['a'], '<-', m['d']) for m in missing]
    shown = [x for x in rows if (only is None or x['region'] == only)]
    shown.sort(key=lambda x: -x['worst'])
    limit = len(shown) if '--all' in opts else top
    print('\nworst %s (edges L T R B, app minus design, points):' % ('all' if '--all' in opts else str(top) + ' per region'))
    if '--all' in opts:
        sel = [x for x in shown if not x['ok']] if '--bad' in opts else shown
    else:
        sel = []
        for r in regions:
            sel += [x for x in shown if x['region'] == r and not x['ok']][:top]
    for x in sel:
        print('  %-9s %-28s %-24s L%+6.1f T%+6.1f R%+6.1f B%+6.1f %s' % (x['region'], x['a'], (x['text'] or x['d'].split('>')[-1])[:24], *x['edges'], '; '.join(x['issues'])))
        if '--rects' in opts: print('            design x%.1f y%.1f w%.1f h%.1f   app x%.1f y%.1f w%.1f h%.1f' % (*x['dr'], *x['ar']))
    if '--unmapped' in opts or '--md' in opts:
        print('\nunmapped design elements without a rule: %d' % sum(1 for _, _, w in unmapped_design if w is None))
        for p, e, w in unmapped_design:
            if w is None: print('   UNEXPLAINED', p)
        reasons = {}
        for p, e, w in unmapped_design:
            if w: reasons.setdefault(w, 0); reasons[w] += 1
        for w, n in reasons.items(): print('   %4d  %s' % (n, w))
        print('\nunmapped app elements: %d' % len(unmapped_app))
        for i, w in unmapped_app: print('   %-40s %s' % (i, w or 'UNEXPLAINED'))

if __name__ == '__main__':
    main(sys.argv[1:])
