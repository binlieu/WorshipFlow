# UI-005j report: Show measured and closed against the mockup's rectangles

Feature ID UI-005j. Brief `AI/specs/UI-005j-show-geometry.md`. Level: **Implemented**, measured in a debug build on the seeded design library at 1440 x 900 (dark and light). Not Hardware Verified, not Live-Service Verified. No model, schema or behaviour change beyond the items under "Where the extras went".

## The three tools (run by hand; `check.sh` does not call them; short guide in `docs/hands-on-checklist.md`)

1. `scripts/design-rects` (+ `design-rects.swift`): loads `docs/UI/mockups/01-operator-show.html` in a `WKWebView` at 1440 x 900, injects `Vendor/Inter/InterVariable.ttf`, writes every visible element (path, text, rectangle, font size, weight, line height, colour, background, border, radius). Its render was compared with `01-operator-show.png` by eye: the same picture; the one difference is that slide 1's caption wraps in the HTML render ("sound" on a third line) where the PNG has two lines. The PNG wins; that thumbnail's inner text is not compared anyway.
2. `App/Sources/DesignProbe.swift` (debug only): `.wfRect("id")` puts an invisible, non-hit-testable `NSView` behind a view (not an accessibility identifier; labels untouched). The ui-snapshots hook writes `<prefix>-<name>.rects.json` with each tagged view's rectangle in window points (fractions from SwiftUI's own layout, whole-point origin from the hosting view). Font size, weight and radius in the dump are the values declared at the tag site, not read back from drawing.
3. `scripts/compare-rects.py` + `scripts/design-map-show.json`: joins by the mapping, prints per region the mapped count and how many are within 1 point on left, top, right and bottom, the worst per region, `--all --bad --rects` for every element still out, and `--unmapped` for both unmapped lists. Entries may skip an edge where the content differs (each says why).

## Before and after (dark; the light capture gives the same counts, 242 / 207)

"Before" is the tree at 6b1ccbd with only the tags added (title block untaggable there, so those two count as not drawn), measured with the final mapping.

| Region | Mapped (before / after) | Within 1 pt before | Within 1 pt after |
|---|---|---|---|
| toolbar | 20 / 23 | 6 | 16 |
| sidebar | 32 / 32 | 1 | 31 |
| centre (header, section labels, cards) | 65 / 65 | 2 | 54 |
| dock (tabs, tiles, controller) | 47 / 51 | 5 | 42 |
| inspector | 51 / 52 | 0 | 50 |
| transport bar | 18 / 19 | 4 | 14 |
| total | 233 / 242 | 18 | 207 |

("Mapped before" is lower where an element did not exist yet: title block, tb, second divider, volume parts.)

Worst remaining, in points (app minus design; edges L T R B):
- toolbar: timers capsule L -2.7 (cascade of five words each 0.5 to 1 pt wider: SwiftUI rounds text up); timer icon L -2.7, name L -2.7, value R -1.1.
- sidebar: LIBRARIES label R -1.9 (letter-spaced text 62.0 wide, 63.9 in the mockup).
- centre: PREVIEW tag R -2.0, LIVE tag R -1.3; title R +1.4; Arrangement field L +1.4; wrapped-section grid bottom +1.2 (one fractional point from whole-point rounding of card heights); Reflow, Quick edit and the view switch +1.0.
- dock: tile names "Soft particles" R -2.1 and "Deep blue drift" R -2.0; layer switch L +1.5; Loop pill R +1.3; tabs Videos L -1.2.
- inspector: stage message field R +1.5; Audio tab R +1.1.
- transport: text block R -1.6; Previous L -1.4; Go Live L -1.3.

Pixel comparison, for reference only: Show dark 20.3 % before, 15.2 % after; light 22.1 % before, 15.3 % after (regions after: toolbar 10.2, sidebar 8.7, playlist 8.6, centre 17.8, dock 18.3, inspector 16.0, transport 12.9). What remains in the difference picture is text anti-aliasing, the slide artwork (UI-005h), the seed's content and the seed's rainbow clip.

Pictures: `AI/reports/UI-005j-show-dark.png`, `-show-dark-side.png` (design left, app right), `-show-dark-diff.png`, and the same three for light (resized to stay under 1 MB).

## What was wrong (causes, not offsets)

- The system List gave every 22 pt playlist header a 24 pt row (minimum row height), drifting everything after it: `defaultMinListRowHeight`.
- Columns: content is 255 and 371 wide (the 1 pt border is outside it), so every row was 1 pt wide and started 1 pt off.
- CSS line boxes: the mockup's text boxes are 16 pt tall whatever the size; SwiftUI's are the font's height. Added `wfLine()` (16 pt) on labels, captions, counts, tab and button text; this also fixed section headers (14 + 5 + 9 gap became 16 + 5, 9 between sections), card captions and the dock strip.
- Paddings that left out the 1 pt border: `.btn` 11, `.field` 9, `.pill` 9, `.kbd` 5 and 16 tall, `.badge` 7 x 2 (20 tall), `.btn.lg` 17, `.seg` track padding 3, tab 7 + 16 + 9 (32 tall), toolbar timers 9, SIM badge.
- Show's header: the mockup's controls run to the column's edge (14 pt past its padding); the Add-to-playlist icon added width; the Arrangement field was squeezed to 110 pt; icon segments were 24 high (20 in the design).
- Inspector: the extras row between the monitors and LOOK pushed everything 27 to 40 pt down; the monitor pictures were inset 4 to 5 pt by ring padding; the Look buttons were 74 wide (equal 66.25 now) and the chevron absent; prop rows showed dimmed off pills; badges were 14 tall.
- Dock: a 6 pt resize handle took room (now overlaid on the top edge); header 40 (46 in the picture, where the tab rules leak into the layer switch, replicated and documented in `WFSegmented(tabLike:)`); tile captions 14 (16).
- Transport: the text block filled the row (the design's hugs its text and a spacer pushes the buttons right), Clear carried an `esc` hint, the dividers were 26 and one was missing, health text spacing.
- Fonts: the optical-size axis was set to the size; the browser that drew the design uses 4/3 of it (17 px title 124.0 wide, matching the mockup's 123.6).
- The system toolbar could not be placed: the app now draws the 52 pt toolbar itself (`ContentView.operatorToolbar`, `WindowChrome.swift`): no title bar (`.windowStyle(.hiddenTitleBar)` plus full-size content), drag by the bar, the three system buttons placed at the design's centres.

## Where the extras went

- Edit live slide, the live background override with Drop, Configure…: one row pinned at the bottom of the inspector (shown only when a live slide exists, an override is on, or no screen is enabled).
- Add text prop…: a + at the right of the Props tab line (tooltip and label kept).
- Header Add to playlist icon: removed from the header; the song row's context menu (and the bin tile's) still has Add to playlist.
- Open/Close screens button: floats in the free room right of the mode switcher and takes none.
- "Stage screens only" caption: kept, right-aligned in the Stage message label line.
- Clear's `esc` hint: removed (the menu entry "Clear words (Escape)" and the tooltip say it).
- Prop target pills that are off: no longer drawn in the row; the context menu "Show on" adds or removes a screen (flagged KI-136, touches FIX-H item 10).
- Slide-grid row gap stays 8 where the mockup has 0 (KI-135).

## Unmapped elements and reasons

Design side (0 without a reason): window buttons 4 (system-drawn, grey because the capture window is not key); icon glyph boxes 55 (SF Symbols draw to their own metrics; the control containing each is compared); picture contents 26 (slide and monitor text, drawn by the output renderer: UI-005h); wrappers 18 (title block, columns, sections, rows); status dots 4; bin caption rows 7; transport key hints 4 (inside compared buttons); health dot 1; meter fills 2 (live level); bin durations 6 (the seed's six other tiles are pictures); Scripture count 1 (model has none, the app shows its key hint); "× 2" 1 (the seed plays the chorus once).
App side: column boxes 3 (compared through rows); prop and monitor-caption sub-texts 6; the two extras above. Not tagged: the bottom extras row, tags on idle slides and tiles.
Content skips (edges not compared, with reasons in the mapping file): library counts L (5 songs, not 214), title and subtitle R and mode switcher L R (the subtitle reads "WorshipFlow · Songs"), tile 0 name R (seeded name carries ".mov"), scrub fill and knob, volume fill and knob.

## Seed changes (debug hook only)

Chorus lines and their Vietnamese lines now match the design's two-line slides; the clip file is named so the controller reads "Waves — teal.mov".

## Existing tests changed

None. No test asserted a layout number.

## Checks

`./scripts/check.sh` exit 0 both runs (package tests: 2606 in 408 suites passed; domain boundary; xcodegen; app build). Run twice; see the final message.

## Not verified

Quick edit's tab, Cues and Audio tabs, the Show states other than the seeded one (cleared, blackout, collapsed dock, search), the other modes' toolbars (Edit, Media, Stage, Cues, Screens use the same bar; their own slices measure them), full screen and window behaviour of the hidden title bar (KI-134), VoiceOver on the new bar. The mockup's 14 pt overrun of Show's header is reproduced (right padding 0), which at other window widths is absorbed by the spacer. A live-slide Quick edit popover and the Clear menu were not re-checked.
