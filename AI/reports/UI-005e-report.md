# UI-005e report: Stage mode measured and closed against `04-stage.html`

Feature ID UI-005e. Level: **Implemented**, measured in a debug build at 1440 x 900 (dark and light) on a seeded library. Not Hardware Verified, not Live-Service Verified. No model, schema or behaviour change except the three small functions listed under "Extras" (all use existing `StageModel` calls).

## Tools

`scripts/design-rects docs/UI/mockups/04-stage.html` (the dump's root is `div.win.nobar[0]`; replace it with `div.win[0]` before comparing, `sed 's/div.win.nobar\[0\]/div.win[0]/g'`, because `compare-rects.py` strips only the first form), `scripts/design-capture-stage.sh` (builds, runs the Stage scenario in `App/Sources/UISnapshotStage.swift`, writes pictures and `.rects.json`; needs `WF_SCRATCH`, and `CLIP=<path to loop-1080p5994.mov>` when the worktree has no `TestMedia`), `scripts/design-map-stage.json` (82 mapped entries; the 23 toolbar entries are the Show map's).

The scenario opens Stage with a layout named Band whose elements sit where the design draws them (percent of the screen), two more layouts (Speaker, Clock only), the stage message sent, the first element selected. The built-in layout cannot be moved, so a custom layout is what makes the canvas boxes comparable.

## Before and after (dark; light gives the same counts)

"Before" is the old view with four region tags (the old view had no element tags; untagged elements count as not drawn).

| Region | Mapped | Within 1 pt before | Within 1 pt after |
|---|---|---|---|
| toolbar (shared, same as Show) | 23 | 16 | 16 |
| sidebar (layout list, cards, stage message) | 17 | 0 | 15 |
| centre (bar, canvas boxes and labels, caption) | 20 | 0 | 18 |
| inspector (element rows, element list, assigned to) | 22 | 0 | 22 |
| total | 82 | 16 | 71 |

Worst remaining (app minus design, points, edges L T R B):
- toolbar: timers capsule L -2.7, timer icon L -2.7 R -2.7, name L -2.7 R -1.8, value L -1.8 R -1.1 (shared bar, same cause as in the Show report: text widths cascade); sermon separator, icon, name about -1.1.
- centre: STAGE badge R -1.5 (shared `Badge`: tracked upper-case text is about 0.1 pt per character narrower than the browser's); NEXT SLIDE label R -1.1 (own label, tracking 0.7 instead of the CSS 0.6 closes most of it).
- sidebar: STAGE LAYOUTS label R -1.4 (shared `SectionLabel`, same cause); Clear L +0.5 R +1.1 (text width 0.6 wider than the browser's).

Pictures (dark and light): `AI/reports/UI-005e-stage-dark.png`, `-stage-light.png`, `-stage-dark-side.png` (design left, app right), `-stage-dark-diff.png` (11.6 % of pixels differ by more than 24 levels, for reference only: the canvas text is drawn by the compositor, the thumbnails show real sample text, the toolbar title differs). No light design picture exists for Stage; the light capture is checked by the same rectangles.

## What was wrong (causes)

- Columns were 240 / 320 wide, the layout list was a scroll of 320-pt-wide previews, the header was 48 pt, the right column had 20 pt padding and a different section structure; Elements rows were 28 pt, Assigned to listed only screens that already used the layout.
- The canvas was 720 pt, drawn with accent-filled boxes and no labels; the design is 820 pt, black with a shadow, dashed 1 pt boxes with their name above, the selected one solid 1.5 pt.
- Stage message was a one-line field with a history button and a status row; the design's is a 48 pt field with Send and Clear on one row.

## Where the extras went

- Name / rename of the layout: the bar's title is editable (Return or leaving the field renames) when the layout is the operator's own.
- "Built in, Duplicate to edit": a line under the screens note in the inspector (the Duplicate and Delete… buttons are under the layout list).
- Duplicate, Delete…: buttons after the last card in the layout list. **Timers**: a Timers… button there opens the old timers panel in a sheet (the plan's default was a sheet from the toolbar timer chip; the toolbar is a shared file, so the sheet is opened from the list instead).
- Notes element button: left of Current in the bar (the design has no Notes). The design's Video button place at the right end of the bar is kept empty so the rest lines up.
- Alignment, position and size in percent, Delete element: a "Position and size" section below Assigned to.
- Font-size stepper: in the place of the design's Auto-fit.
- Recent messages: a clock icon at the right end of the Stage message label.
- The built-in Standard layout is listed after the operator's own layouts (the design shows only presets).
- Notes is seeded in the Section's place in the capture so the element list lines up; it is an app-only element.

## L rows left out (open, need a feature slice)

Video element and Video button; Section element (canvas box, list row); Auto-fit; per-element eye (hide); second-language colour row (its row space is kept); Band, Speaker and Clock-only presets (the app has Standard; the capture creates the three as ordinary layouts); the design's caption text about 1920 x 1080 and a 64 px lyric minimum (the app enforces neither; the existing caption about dragging is shown in its place). The element handles: only the bottom-right corner handle exists in the editor, so only that is drawn (10 pt, selected element, editable layouts); not eight.

## Unmapped elements

Design: 0 without a reason. 4 window controls (system); 30 icon glyph boxes; 14 picture contents (sample words in the canvas and thumbnails); the others are wrappers, the left-out rows above, chevrons and dots inside compared controls. App: Notes button, Notes element (box, label, list row), the Standard card (3 tags).

## Seed notes

The canvas shows the compositor's real drawing of the layout: with the Band frames the second-language line and the NEXT label of a copied Standard layout land over each other (they are positioned relative to their element and Band's current element is much taller than Standard's). That is the layout model's behaviour, not this slice's; the design's HTML canvas shows idealised text.

## Docs entries for the coordinator

Change log: "UI-005e: Stage mode matches 04-stage.html (82 mapped elements, 71 within 1 point; rest listed in AI/reports/UI-005e-report.md). Layout list with preview cards and the stage message at the bottom, the bar, an 820 pt canvas with named dashed boxes, the inspector (Shows, Size, Weight, Colour), the element list and Assigned to with a per-screen switch. Own layouts are listed before the built-in one. Timers open in a sheet from a Timers… button under the layout list."

Known issues: "UI-005e open: Video element, Section element, Auto-fit, per-element hide, second-language colour, Band/Speaker/Clock presets (need feature slices); only the bottom-right resize handle exists; Timers sheet is opened from the layout list, not from the toolbar chip (toolbar is shared); `Badge` and `SectionLabel` tracked text about 1.5 pt narrower than the design (shared components, tracking 0.1 pt too small); Stage's capture needs TestMedia from the main folder when run in a worktree."

Hands-on checklist: "Stage: pick a layout card; rename the layout in the bar; Duplicate and Delete…; Timers… sheet; add each element with the bar buttons; drag a box and its corner handle; Shows / Size (type and stepper) / Weight / Colour (swatch and hex); element list selects the box; the Assigned to switch moves a stage screen to this layout; Send and Clear in the Stage message; the built-in layout shows the buttons disabled."

## Shared-file lines

`App/Sources/UISnapshotRun.swift`: one commented block (6 lines) calling `runStageDesignScenario` when `UI_SNAPSHOT_STAGE` is set. `ModeViews.swift`: `StageModeView` cut out (moved to `StageMode.swift`), nothing else touched. Wanted in the shared files: `SectionLabel` and `Badge` tracking 0.7 per 10 to 11 pt (measured: 0.1 pt per character narrower than the browser).

## Checks and not verified

`./scripts/check.sh` exit 0, package tests 2811 in 441 suites passed (run once; no timing failures). Not verified: operating the editor by hand (drag, handle, rename, sheet, switches were built and compile but only the static capture was inspected); VoiceOver; the layout with a real stage screen on hardware; window widths other than 1440; the Standard (read-only) state beyond compiling.

## Follow-up: every Stage box draggable and resizable (second commit)

The owner, on build 115: "stage tab also text box doesn't work for the lyric".

**What happened before, measured.** The debug hook `UI_SNAPSHOT_STAGE_DRAG=1` (`App/Sources/UISnapshotStageMouse.swift`) sends real mouse down, dragged and up events to the window. The harness itself was checked first: a click on a layout card changed the element list. On an operator-made layout (Band), on the code of the first commit: a press and an 8-step drag on the current-slide box, the next-slide box and the clock box moved nothing (stored frames identical, 0 writes, the drawn box did not move), and a plain click on a box did not select it (the inspector heading stayed "ELEMENT — CURRENT SLIDE"). No AppKit view was in the way (the hit test lands on the hosting view). The cause was in SwiftUI: every box carried its own tap and drag gestures inside an overlay that also carried a canvas-wide tap, and none of the box gestures ran. The fix does not depend on finding which modifier was to blame: the boxes no longer take events at all. The same wiring is in the old code the owner tested, which also writes the model on every mouse move, so even a working drag would have republished to the stage screens on every step.

**Fix.** One pointer layer over the canvas (`App/Sources/StageCanvasView.swift`) hits-tests itself with `StageCanvasEditing.hit`: the selected box's handles first (eight, drawn like the slide editor's: 8 pt white, 1.5 pt blue edge, 16 pt grab area), then the smallest box under the point. A drag is held in the view (`StageCanvasEditing.Drag`); outline, handles and the compositor picture are drawn from the dragged frame in the same frame (the picture redraws at once while dragging); the model is not touched until release, when `StageCanvasEditing.commit` writes once and registers one undo step (Command-Z undoes it, redo works). Arrow keys nudge 1 point (Shift 10) through a small key-catching view that takes focus on a press and reports itself to the key router as a control that keeps the arrows (so the show's arrow keys do not also move the slide selection); one write and one undo step per key press. The second-language line and the NEXT label are relative to their element (FIX-J) and moved with it in the picture (test below). A built-in layout: a press selects, a drag draws and writes nothing, and the caption row says "Built in. Duplicate to edit." with a Duplicate button.

**Real-mouse run now (Band layout, 820 x 461 pt canvas):**

| What | Before the drag | After release | During the drag | Writes during / after |
|---|---|---|---|---|
| (a) current-slide box moved by 60 x 40 pt | x0.040 y0.090 | x0.113 y0.177 | box drawn following the pointer: yes | 0 / 1 |
| (b) next-slide box moved by -40 x -30 pt | x0.040 y0.600 | x0.000 y0.535 (stops at the screen's edge) | yes | 0 / 1 |
| (c) clock box moved by -50 x 20 pt | x0.740 y0.090 | x0.679 y0.133 | yes | 0 / 1 |
| clock from the bottom-right handle | w0.220 h0.150 | w0.257 h0.193 | yes | 0 / 1 |
| clock from the top-left handle | x0.679 y0.133 | x0.703 y0.155, w0.232 h0.172 | yes | 0 / 1 |
| current from the right handle | w0.660 | w0.611 | yes | 0 / 1 |
| current from the top handle | y0.177 h0.420 | y0.231 h0.366 | yes | 0 / 1 |
| next from the bottom, then the bottom-left handle | h0.220 | h0.177, then x0.030 w0.630 h0.166 | yes | 0 / 1 each |
| a click on a box (no movement) | | selects it (inspector heading changes), no write | | 0 / 0 |
| arrows on the selected box: Left, then Shift+Down | x0.030 y0.535 | x0.029; then y0.557 (1 pt and 10 pt) | | one write each |
| one Command-Z (the undo action) | y0.557 | y0.535 (the Shift+Down only) | | |
| built-in Standard, drag on the lyric box | | stored frame unchanged, box not drawn moving, caption shows the note | | 0 / 0 |

The other four handles (top-right, left, bottom-right on other boxes, and so on) are covered by the maths tests; the real-mouse run exercised six of the eight.

**Tests** (`Packages/WorshipFlowKit/Tests/OperatorCoreTests/UI005e_StageCanvasEditingTests.swift`, 14, written first and seen failing against stubs, then passing): which element a point picks (overlap: the smallest wins, later on a tie; handles first, only when editable, all eight at their centres); each handle moves only its own edges; minimum size and the screen's edges; the move clamp; nudge 1 and 10 points and the clamp; a drag is measured from the press, touches no model and finishes with two frames or nothing; `commit` writes once with one undo step, undo restores and registers a redo, an unchanged frame writes nothing, the built-in layout is never written; the second-language line and NEXT label shift by the same amount as their elements. The mouse-driven behaviour above is the integration evidence; there is no automated UI test of it.

**No model or schema change.** New pure logic is in a new OperatorCore file (`StageCanvasEditing.swift`) used only by the Stage view; `StageModel` is unchanged.

**Rectangle comparison, re-run:** 82 mapped, 71 within 1 point (toolbar 16/23, sidebar 15/17, centre 18/20, inspector 22/22), unchanged; the eight handles are app-only and listed in the map's ignore rules. Check: `./scripts/check.sh` exit 0, package tests 2825 in 442 suites passed.

**Not verified:** a real hand on a trackpad (the events are synthetic, sent to the window); cursor shapes (no resize cursor is set); dragging while a stage screen is on (the screens are updated by the same publish as before, once per release); the arrow keys with the canvas focused while another control was clicked after it (focus leaves with Escape or when another responder takes it); the Edit canvas, which the owner reports the same way but is not in this slice.

Docs entries: Change log: "FIX-K (Stage): every element box on the Stage canvas can be selected, dragged, resized from eight handles and nudged with the arrows; the layout is written once on release as one undo step; a built-in layout says 'Built in. Duplicate to edit' with a Duplicate button." Known issues: "Stage canvas: no resize cursors; the Edit canvas has the same unfixed per-box gesture wiring (reported by the owner)." Hands-on checklist: "Stage: select, drag and resize each box (all eight handles, lyric boxes included) on your own layout; Command-Z undoes one drag; arrow keys nudge 1 pt, Shift 10; on Standard a drag changes nothing and Duplicate is offered."
