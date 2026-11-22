# UI-005i report: the operator interface is set in Inter

Feature ID UI-005i. Brief `AI/specs/UI-005i-inter-font.md`. Level: **Implemented**, **Unit Tested** (coverage, fallback, separation of the output path), compared by picture in a debug build. Not Hardware Verified, not Live-Service Verified.

## What was built
- `project.yml`: `Vendor/Inter` as a folder resource, so the app carries `Resources/Inter/{InterVariable.ttf, InterVariable-Italic.ttf, LICENSE.txt, SOURCE.txt}`. Nothing is copied in the repository.
- `App/Sources/InterFont.swift`: registers both files with `CTFontManagerRegisterFontsForURL(.process)` in `applicationWillFinishLaunching`; on failure one `os.Logger` error and the system font is used. Weight and the optical-size axis are set through variation axes; `tnum` is on. A small cache keeps font creation cheap.
- `DesignTokens.swift`: named styles on Inter (`wf(size, weight)`, `wfBody`, `wfControl`, `wfControlStrong`, `wfCaption`, `wfSectionLabel`, `wfBadge`, `wfTag`, `wfSmall`, `wfCallout`, `wfHeadline`, titles) and `wfMono` (system monospaced = SF Mono). The system text styles were mapped to their macOS sizes so no row changed height.
- All `.font(.system(...))` and text-style uses in `App/Sources` replaced (36 files); `.fontWeight` and `.bold()` on text replaced by explicit weights; `.font(.wfBody)` at the root of the workspace, About and hardware test windows so unstyled controls are Inter.
- NOTICE, README third-party section and the About window's notices name Inter; the licence is in the bundle.

## What could not be set in Inter, and why
Menus, the title bar, open and save panels, alerts (`NSAlert` in quit confirmation), the window buttons and system pop-up menus are drawn by the system. Scripts Inter lacks use the system cascade (below). Mono text is SF Mono by design. Not changed on purpose: projected output text, themes, slide thumbnails' rendered text, the theme editor's font-name check (`NSFont(name:)` of a theme's font).
Deviation: `cv11` is off (KI-125), because the design pictures show the double-storey "a"; with cv11 the "a" became single-storey and clearly differed from the pictures.

## Fallback test
`UI005i_InterFontTests` loads the vendored file with CoreText and, for every character of short invented phrases (Vietnamese stacked diacritics, Latin, Cyrillic, Greek; Chinese simplified and traditional, Hmong Latin and Pahawh, Thai, Lao, Khmer, Burmese, Devanagari, Arabic, Hebrew, Korean, Japanese), asks CoreText which font draws it: Inter for the first group, and for the rest a system font with a real glyph (no missing-glyph box) and a line height at most 2 times Inter's. Burmese is the tallest (28.4 pt against 15.7 pt for Inter at 13 pt, 1.8 times; KI-126); the rest are lower. A scratch SwiftUI render of the same phrases in 26 pt rows, Inter against system, is `AI/reports/UI-005i-fallback-scripts.png`: no boxes, no clipping, identical row heights. The test uses no clock and no pixels. No Bible text is used.

## Before and after (share of pixels differing by more than 24 of 255)
"Before" is the tree at bbbea95 with the same seed. Pictures: `AI/reports/UI-005i-<name>.png`, `-side.png` (design left, app right), `-diff.png`.

| Picture | Region | Before | After |
|---|---|---|---|
| show-dark (01) | overall | 19.9 | 20.2 |
| | toolbar | 16.7 | 16.8 |
| | sidebar | 13.1 | 13.5 |
| | playlist | 13.3 | 13.3 |
| | centre | 20.2 | 20.1 |
| | dock | 26.1 | 26.1 |
| | inspector | 22.8 | 23.9 |
| | transport bar | 16.5 | 17.0 |
| show-quick-edit (01b) | overall | 20.8 | 21.0 |
| | toolbar | 16.6 | 16.8 |
| | sidebar | 13.1 | 13.5 |
| | playlist | 13.3 | 13.3 |
| | centre | 20.6 | 20.6 |
| | dock | 26.3 | 26.2 |
| | inspector | 25.7 | 26.6 |
| | transport bar | 16.5 | 17.0 |
| show-light (09) | overall | 21.6 | 22.0 |
| | toolbar | 15.1 | 15.3 |
| | sidebar | 12.8 | 13.3 |
| | playlist | 12.9 | 12.9 |
| | centre | 25.0 | 25.0 |
| | dock | 26.2 | 26.2 |
| | inspector | 22.9 | 24.0 |
| | transport bar | 16.5 | 17.0 |
| components-dark (08) | overall | 12.7 | 13.1 |
| | buttons | 11.4 | 12.1 |
| | selection | 7.6 | 7.5 |
| | role and status | 15.2 | 16.2 |
| | thumbnail stat | 33.3 | 33.5 |
| | messages | 11.5 | 11.7 |
| | colour | 11.0 | 12.1 |
| | brand | 8.4 | 8.4 |
| components-light (10) | overall | 13.3 | 13.6 |
| | buttons | 11.6 | 12.2 |
| | selection | 7.3 | 7.2 |
| | role and status | 15.5 | 16.6 |
| | thumbnail stat | 36.2 | 36.4 |
| | messages | 11.5 | 11.7 |
| | colour | 10.9 | 12.0 |
| | brand | 8.3 | 8.3 |

The numbers did not fall; they rose by a few tenths of a point in text-heavy regions. Honest reading: the tool counts pixels, and text is thin, so a font change moves few pixels either way; and the system font at these sizes is close to Inter, so the old text already overlapped the design's text about as well. The pictures show the glyph shapes now match the design (the "G", "1", "a" and the digit widths); the remaining differences are glyph positions (different hinting and baseline than a browser's) and the content differences listed in UI-005a. Because the figures do not support a claim of improvement, none is made; what is claimed is that the font is Inter, rows kept their height, and nothing was truncated by the change.

## What was looked at (dark and light)
Before and after crops of the toolbar, sidebar, playlist, grid, dock, controller row, transport bar, inspector and Quick edit, dark and light: no new truncation (the "Ove...teal" label and "Arrangem..." were truncated before), no clipped descenders, sidebar, playlist and grid row positions are the same. In the inspector's Quick edit text sits about 1 pt higher in a few rows (header "Slide 4 of 9" and its labels): a one-point shift in line metrics (Inter's ascent and descent differ from SF's), no row got taller. Components sheets were compared by number only, not cropped.

## Existing tests changed
None. `UI004_AboutInfoTests` still passes (it checks `contains`, and the added notice has no "@" or path). New: `UI005i_InterFontTests` (5 tests).

## Checks
See the final message for both `./scripts/check.sh` exit statuses and the test count.

## Not verified
Hardware, live service, VoiceOver, the packaged Release bundle's font copy (only the Debug bundle was inspected: the four files are in `Contents/Resources/Inter`), the system alert and menu fonts, the Hardware Test window and the sheets' rendering in a running app (they inherit the root font; checked by reading, only the main window and Quick edit by picture), AppKit text fields' variable-weight rendering beyond the pictures, Burmese in a real library row, and the Components board's crops.
