# UI-005c report: Edit measured and closed against the mockup's rectangles

Feature ID UI-005c. Brief `AI/specs/UI-005-mode-geometry.md`. Design `docs/UI/screens/02-editor.png`, `docs/UI/mockups/02-editor.html`. Level: **Implemented**, measured in a debug build on the seeded design library at 1440 x 900, dark and light. Not Hardware Verified, not Live-Service Verified. No model, schema or behaviour change (see "Behaviour that moved").

## Tools

`scripts/design-capture-edit.sh` builds (own derived-data folder), runs one throw-away copy of the app with `--library` in a scratch folder and `--silent-audio`, captures Edit (`UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_EDIT=1`, `App/Sources/EditDesignCapture.swift`) and prints the comparison. `scripts/design-map-edit.json` is the mapping (113 entries, 23 of them the shared toolbar, copied from Show's map with the chosen segment moved to Edit). The mockup's root class is `div.win.nobar`, which `compare-rects.py` does not strip, so the script renames it before the comparison (the shared script is untouched). Capture state: Amazing Grace open, slide 3 live, slide 4 edited, one text box on slide 4 with the design's frame, 72 pt, weight 600, shadow 0/4/16, selected. The design's two lyric boxes are the theme's words in the app, not objects; the seeded box stands for the selected one, so the canvas draws the words twice (the picture content is not compared).

## Before and after (dark; the light capture gives the same counts)

"Before" is the tree at 99c97a9 with only tags added (the old inspector sat inside the centre column and had no mapped parts, so its 45 elements count as not drawn).

| Region | Mapped (before / after) | Within 1 pt before | Within 1 pt after |
|---|---|---|---|
| toolbar (shared bar) | 23 / 23 | 16 | 16 |
| filmstrip (sidebar) | 13 / 21 | 0 | 21 |
| centre (bar, strip, canvas, handles, caption) | 9 / 24 | 0 | 18 |
| inspector | 0 / 45 | 0 | 42 |
| total | 45 / 113 | 16 | 97 |

Filmstrip and canvas geometry (frame, safe guide, selection box, all eight handles) are matched; the inspector's every row, field, tab, segment, swatch and checkbox is within 1 point except the three below. Worst remaining (app minus design, points, edges L T R B):
- toolbar (shared, not in this slice's files): timers capsule L -2.7 and the four elements after it: the live chip ("LIVE My chains a...") that `ContentView` draws in the bar when the transport bar is hidden and something is live is not in the design's Edit bar and pushes the timers left (the same 2.7 pt is in the "before" run, so it is not caused by this slice).
- centre: live-strip note L -2.8 R -7.7 and "Slide 3 is live." R -2.8 (the app's 12 pt bold text is 80.0 wide, the PNG's about 80.7, the HTML dump's 82.8: the sources disagree, the picture wins); title-safe label R +1.5; Shape button L +0.6 R +1.4 and Image L +1.4 R +1.0 (text widths: SwiftUI's Inter text is up to 1 point wider per word, cumulative along the row).
- inspector: Top / Mid / Bot track R +1.7, Mid L +0.8 R +1.5, Bot L +1.5 R +1.7 (same text-width cause in 3 words).

Pixel comparison, reference only: the dark capture differs from `02-editor.png` in 7.6 % of pixels above tolerance 24 (canvas words, slide thumbnails and the seed's prop are content). Pictures: `AI/reports/UI-005c-edit-dark.png`, `-edit-dark-side.png` (design left, app right), `-edit-dark-diff.png`, `-edit-light.png` (the design has no light picture for Edit; light is measured by rectangles only), and two looked-at states outside the design: `-edit-slide-tab-dark.png`, `-edit-shape-dark.png`.

## Causes fixed

- Column widths 208/flexible/variable to 200 / 920 / 320; the old inspector lived inside the centre.
- `ScrollView` reserves the classic scroller's 17 pt when a mouse is connected even with `.scrollIndicators(.hidden)`; `.never` takes none (the 175 pt thumbnails were 158).
- Rows wider than the inspector (Align + Top/Mid/Bot is 300 wide in the mockup too) pushed the whole column wider; rows are now fixed at 295 and overflow as the mockup does.
- The bar is 47 pt tall because of the design's 30 pt preview switch; the strip is 29; sections are 1 + 10 + 16 + 6 + rows + 10; headings are 16 pt lines; the canvas is 800 wide and centred, radius 2, `--shadow`.
- Selection: 1.5 pt `sel` blue, no fill, eight 8 pt handles centred 1 pt inside the edge (the model's drag only knows the bottom right; the other seven resize from a local frame and write once with `setFrame` on release, one undo step).

## The L rows left out (open, need a feature slice) and where their room is

| Row | Design | Why not drawn | Room kept |
|---|---|---|---|
| E12 | Video button | no video object in `SlideObject` | 76.1 pt gap in the bar |
| E13/E14 | divider and Align menu | no align operations in `SlideEditorModel` | 1 + 90.3 pt gap |
| E16 | Audience / Stage / Broadcast preview | the canvas has one scene; needs a per-role scene in the canvas | bar height 47 and the space at the right |
| E17 | Zoom 62% | canvas has no zoom | same |
| E19 | "Saved 2 s ago" | no last-saved time on the editor model | none needed |
| E35 | Fit (Shrink to fit box) | no fit mode on `TextObject` | a blank 30 pt row |
| E38 | Background fill (text) | not in the model for text | a blank 30 pt row |
| E40 | Layers list | objects have no names, hidden flag or roles; props and background are not objects | the section's place (holds Appearance) |
| E22.. | second lyric box | the words are the theme's, not objects | n/a |

Built although the audit called them L or M: Style (a pop-up over `TextStyle.weight`, which UI-005h added; set through the model's public `edit`), Arrange menu (the four order commands that existed), eight handles, title-safe guide, caption (real theme name and slide count), Colour as swatch + hex, Shadow as one field "x · y · blur", Outline as checkbox + colour + width, Position in pixels of 1920 x 1080.

## Where the extras went

- Words fields (first language, second language, speaker notes): Slide tab, stacked, with the note that editing changes the preview only.
- Theme pop-up and Themes...: Theme tab. Section order pop-up and Section orders...: Slide tab. Add slide, Reflow..., Edit live slide...: Slide tab (Add slide is also the + in the filmstrip header).
- Undo, Redo, Duplicate, Delete: icon buttons at the right of the object bar (the preview switch's place). The old Insert menu is dropped (Text, Shape, Image in the bar do the same).
- Opacity, and the old inspector's "Add another" buttons (dropped, same as the bar): Opacity is in an Appearance section under Position, where Layers would be.
- The six preset colours and the system colour panel: a popover from each swatch.
- Font: a text field with a chevron menu of the installed families (a name that is not installed is drawn in the warning colour with a tooltip, replacing the orange paragraph).
- Shape and image objects keep their controls in the same section chrome (Fill, Outline, Corners; image path and Fit/Fill).

## Behaviour that moved (no model change)

Shadow's default when switched on is the design's 0 / 4 / 16 (was 4 / 4 / 8). Outline's checkbox sets width 2 or 0. The unselected object's box is dashed at 25 % white (was 35 %). `SlideEditor` in `CentrePane.swift` (not mine) is now unused; `SlideObjectsEditor` stays as a thin shim so that file still compiles; the coordinator may delete both.

## Shared-file lines added

- `UISnapshotDesign.swift`: one commented line before the Show captures: `if ProcessInfo...["UI_SNAPSHOT_EDIT"] != nil { await runEditDesignScenario(...); return }`.
- `ModeViews.swift`: `EditModeView` cut out (now `EditMode.swift`); nothing else touched.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` regenerated by `xcodegen` (four new files); the coordinator should regenerate after the merge instead of merging this file by hand.

## Wanted in the shared files

`EditSegmented` (full-width segments, side padding option) as an option of `WFSegmented`; `EditCheckbox` with a probe id as an option of `WFCheckboxStyle`; the live chip in `ContentView`'s bar should not displace the timers in a mode without a transport bar (or the design's Edit toolbar needs it moved); `InterFont` text is up to 1 pt wider per word than the mockup's render (suspect `cv11`, which `ctFont` does not switch on although its comment says so).

## Docs entries for the coordinator

Change log: `UI-005c: Edit matched to 02-editor: 200/920/320 columns, object bar, live strip, centred 800 pt canvas with title-safe guide and eight-handle selection, inspector tabs Object / Slide / Theme in design fields, Style pop-up, Colour hex, Shadow and Outline rows, Position in pixels; words fields, theme and section-order controls moved into the Slide and Theme tabs. 97 of 113 mapped rectangles within 1 pt (see AI/reports/UI-005c-report.md).`

Known issues: `Edit: not built, no feature: Video object, Align, Audience/Stage/Broadcast preview, Zoom, Saved-ago, Fit, text Background fill, Layers list (UI-005 audit E12, E14, E16, E17, E19, E35, E38, E40). Toolbar live chip displaces the timers 2.7 pt in modes without a transport bar. Eight-handle resize other than the bottom right corner redraws the picture on release, not while dragging. Not verified: VoiceOver on the new inspector, keyboard Tab order through the new fields.`

Hands-on checklist: `Edit: select a text box, drag each of the eight handles and press Command-Z once (one step each); type a hex colour, "0 4 16" in the shadow field and "2" in the outline field; switch Object / Slide / Theme; type words in the Slide tab and see the filmstrip follow; pick a weight in Style.`

## Not verified

Eight-handle dragging, the hex, shadow and outline fields' parsing, the Style pop-up on a live service, the Slide and Theme tabs' controls and the font menu were built and looked at in captures (slide tab and shape object) but not driven by hand; no UI test. Narrower windows (the canvas scales down, the rows do not). Other font families' weights. VoiceOver.

## Check

`./scripts/check.sh` exited 1 twice, both times in the package tests (2720 tests in 423 suites; first run 8 issues, second 5), all in timing-sensitive suites in code this slice does not touch (`MIDIRouterTests` both times, plus `ToolProcessRunnerTests`, `VideoPlayerSourceTests` and `ScriptureLibraryTests` once each) while three other agents were building. `swift test --filter MIDIRouterTests` alone passes (17 tests). The check stops at the package tests, so xcodegen and the app build were run by hand: `xcodegen generate` and `xcodebuild ... build` (Debug) both succeeded with no errors, and that build is the one measured above.
