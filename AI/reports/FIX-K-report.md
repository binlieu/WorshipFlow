# FIX-K report: the owner's hands-on findings on build 115

Feature IDs UI-005c, UI-005d, MEDIA-010, SLIDE. Brief `AI/specs/FIX-K-hands-on-build-115.md`. Order followed: 3, 1, 5, 6, 2, 7 (items 4's Stage half is not in this task). Level: **Implemented, Unit Tested** and driven in the running debug build with real mouse and key events (events sent through `NSApp.sendEvent`, debug hook `UI_SNAPSHOT_FIXK`, `App/Sources/UISnapshotFixK.swift`). Not Hardware Verified, not Live-Service Verified. No wall-clock assertions in the suite.

## Item 3: Edit, boxes cannot be dragged

**Two causes, one regression and one gap.**
1. Regression (objects). Every drag gesture on the canvas was measured in the box's own local coordinate space. Since UI-004 the box follows the pointer, so its local space moves under the pointer and the gesture sees the pointer cover only half the distance. Real mouse events on build-115-equivalent code: 150 px dragged moved the box 75 px (0.094 of 800), a 160 px drag moved it 80 px for any number of events above one (1 event: 160). The handles had the same fault. A model-level test cannot see it (the model is handed the translation). Fix: one named coordinate space on the canvas (`SlideCanvasSpace`), every `DragGesture` of the canvas uses it. After: 150 px moved 0.188 = 150 px; every variant (1, 2, 4, 30 events, gaps of 1, 16, 60 ms) moved the full 160 px.
2. Gap (lyric boxes). The first and second language's words are the theme's, not objects: there was no box to click at all (UI-005c report). They are now boxes (below the objects, so an object over the words is hit first).
3. Found on the way: `beginInteraction()` did not reset the history when it was the first edit of a presentation, so a drag that opened the interaction then cleared itself and wrote at once. Fixed (`resetHistoryIfPresentationChanged()` first); the new lyric drag test caught it.

**Design.** `SlideContent.textFrames: SlideTextFrames?` (first and second language, fractions of the frame = the theme's coordinate space, so it holds at every output size; Fit still applies inside it). Migration v14 adds `slide.textFrames TEXT` (additive; NULL means the theme's frames; a slide without one composes and encodes exactly as before, proven in tests for the built-in and Classic themes). The audience screen uses it; the broadcast look (plated) and the stage keep their own (KI-166). Carried by re-flow (same match as notes and backgrounds; listed as a loss in the re-flow sheet), program export and import (also in the "same presentation" comparison), undo and redo, `updateSlide`. Inspector: Position fields, "Reset to theme position", "Apply to all slides in this song" (each slide its own undo step); the box's context menu has the same two. Arrow keys nudge the selected object or lyric box 1 point of 1920 x 1080 (Shift 10) in Edit; a run of nudges is one undo step; with nothing selected the arrows move the slide selection as before. Dragging, resizing and nudging write once and make one undo step; Live is never changed (tested).
"Carried by duplicate": the app has no duplicate-slide or duplicate-presentation command (only object duplicate); `SlideContent` is a value, tested that a copy carries the frames. Nothing to wire.

**Real-mouse run (item 3), 800 x 450 canvas, 200-slide song for the timing rows.**
- Added text box and rectangle: mouse down, 30 dragged, up: moved 0.188 x 0.133 as asked; the first press selected it; handles 7, 4 and 0 each moved their own edges by the pointer's travel; live words unchanged.
- First-language lyric box: dragged (clamped at the slide edge as designed: x 0.05 to 0.10, y +0.133), selected, slide 2 got its own frame, other slides' frames and the live slide unchanged; its handles 7, 4, 0 moved their edges by the pointer's travel; real Right then Shift-Down key events moved it +1/1920 and +10/1080; Reset to theme position and Undo worked; a click on an unselected second-language box selected it; a click on an object over a lyric box selected the object; a click beside the canvas selected nothing.
- The coordinator's hint (Stage: per-box gestures never ran under an overlay with a canvas tap) did not apply here: the same real-event run shows Edit's per-box gestures run and select; the cause here was the coordinate space. I did not rewrite to a single pointer layer.

## Item 1: clear icons

Reproduced in the running app (the old rule copied into the hook; build 115 = the old rule): with the show live and the background not cleared, `Clear background` was enabled whatever was selected, and its glyph was always the "photo" glyph. Sending a bin video live to the background layer (the layer switch's default; a double click or Return) put the clip on the background layer and lit the background icon, whose glyph is "photo": step 3 of the run printed `background[photo glyph] ON` for a video. With the layer switch on foreground the clip went to the foreground layer and the "film" icon lit (correct). Glyphs in 115: lyric `text.alignleft`, background `photo`, foreground `film`, music `music.note`, all `rectangle.slash`.
Fix: pure `ClearIconState.state(for:live:)` (OperatorCore `ClearIcons.swift`): enabled only for what is live on that layer (a bin choice, else the live slide's own background; the theme's own loop does not light it, KI-167), glyph film / photo / plain layer glyph, tooltip like "Clear background video: Waves, ⌃⌥B". A one-click selection in the bin lights nothing (run: step 2 all layer icons off). 8 tests, every layer and kind.

## Items 5, 6, 2 (owner overrides, recorded in the change log)

5: the LIVE chip and the live slide's words are gone from the toolbar in every mode (AUD, STG, BRD pills unchanged; keys unchanged). 6: the mode switcher is directly after the title block. 2: the transport bar's Clear is a plain button (no chevron, no menu); its commands stay on the five icons, their keys and the Show menu (test reads the menu bar source). Pure `ToolbarLayout` + source tests. Design maps (`scripts/design-map-{show,media,cues,edit}.json`): `tb.modes` and the transport entries moved by Clear's missing chevron (`tp.previous`, `tp.golive`, `tp.next`, `tp.sep.0`, `tp.clear`) carry `"skip": "LR"` with "owner override, 2026-11-21". Show comparison re-run (design-capture without the SDI simulator, so the Show inspector monitors differ by the design's own SDI row, not from this task): toolbar 23 mapped / 16 within 1 pt (same as UI-005j), transport 19 / 16 (was 14), total 172 of 236 (inspector 13 of 46 only because the run had no simulated SDI card; not caused by this task).

## Item 7: every drag, measured before and after

200 slides, 107 bin items, debug build, this Mac, real mouse events (40 or 30 events 16 ms apart). Cost per event = time inside `sendEvent` plus how late the main thread woke (the run loop was busy drawing). Database commits come from the new `LibraryStore.commitCount`; output publications from a debug counter.

| Drag | Before: median / 95th / max (ms), events over 8 ms | After |
|---|---|---|
| Sidebar column strip | 71.6 / 117.6 / 136.1, 40 of 40 | 2.4 / 7.5 / 9.5, 1 (the release, which lays the window out once) |
| Inspector column strip | 54.5 / 78.7 / 82.3, 39 of 40 | 2.3 / 5.4 / 10.6, 1 (the release) |
| Dock height strip | 3.9 / 5.0 / 5.4, 0 | 2.3 / 6.0 / 7.0, 0 (one commit, on release) |
| Volume slider | 3.7 / 7.8 / 9.0, 1 | 2.1 / 5.6 / 5.9, 0 |
| Edit: lyric box, object, handle | 2.4 / 3.0 / 3.1 and 2.4 / 2.5 / 2.5 (after the item 3 fix; before it the drag did not work) | same |
During every real-pointer drag: database commits 0 (except the dock strip's and sidebar's release write, 1) and output publications 0.

Causes found (main thread per event): the column strips assigned the width to `app.ui` on every event, which re-laid out the whole Show window including the 200-slide grid and the bin (55 to 70 ms). Fixed: `ColumnDrag` (pure, tested) holds the proposed width, a 2 pt guide line follows the pointer, the width applies on release. The Edit canvas already wrote nothing per event (UI-004) and still does; the dock strip and slider were already light.

Drops (heartbeat on the main thread, handler called directly; **not a real pointer**): slide reorder 25 ms total, 21 ms longest stall, 2 commits (flush then the move); playlist reorder 14 ms / 11 ms, 1 commit (after: 6.5 / 6.9); song into the playlist 19 / 15, 1 commit (7 / 8); bin tile onto a slide 0.4 ms (a 12 to 14 ms stall from the background's thumbnail redraw); a Finder file onto the bin 800 ms total (probing and thumbnail, off the main thread) with a 25 to 29 ms stall, 2 commits. Publications 0 for all (the output gate). The after numbers differ from before only by run-to-run noise (nothing in those paths changed).

**Not measured with a real pointer**: the system's drag session itself (`.draggable` drag image, hover loop, `isTargeted` highlight on the dock, the playlist `List.onMove`, dropping files from Finder). Synthetic events cannot start AppKit's drag loop, so the drag image's cost and the per-event hover cost are unknown; the drop handlers are called directly. Slide grid and filmstrip cells are keyed by index (an arrangement can repeat a slide's id), so a reorder redraws every cell: not changed (KI-168). The target "no hitch over 8 ms per drag event" is met for every real-pointer drag except the one release of a column strip (about 50 ms, the one layout); the drops' stalls of 7 to 29 ms are over it and are left (KI-168). Not changed: the playlist split strip (not measured, KI-169).

## Item 4: what the Stage editor needs (for a later brief)

Its lyric text box is the current-slide element (`StageElement .currentSlide`) with the second language as a sub-frame (`StageSecondLanguage.frame`, `onElement`), so it is not a separate box today: the editor needs (1) a selectable, draggable and resizable box for the second language's frame as well as the element, (2) every drag gesture measured in a fixed canvas space (the cause here; the Stage agent found its own variant), (3) the transient frame kept apart during a drag and one write and one undo step on release (copy the `beginInteraction` / `dragFrames` / `endInteraction` shape of `SlideEditorModel`), (4) arrow-key nudging in the layout's 1920 x 1080 points through the key router, (5) a real-mouse test (down, dragged, up) in its report.

## Tests (new files `FIXK_*.swift`; 53 in this task's suites)

`FIXK_TextFramesTests` (Domain), `FIXK_TextFramesStoreTests` (v14 with `prefix(13)` and unchanged slides, reflow carry, damaged value), `FIXK_TextFramesPackageTests`, `FIXK_LyricBoxTests` (select, drag, resize, handles, typed fields, reset, apply to all, nudge, each object kind: one write and one undo step per drag, resize and nudge, Live unchanged), `FIXK_CanvasGestureSourceTests`, `FIXK_ClearIconTests`, `FIXK_ToolbarTests`, `FIXK_DragCounterTests` (zero commits and publications during a drag, ColumnDrag).
Seen failing first: the gesture-space guard (`offenders: ["line 172", "line 239"]`, the two `DragGesture(` lines), the toolbar source tests (chip present, spacer before the switcher, menu and chevron in the transport bar, `showClearMenuPreview` present), and the real-mouse run of the old code (half the distance, nothing selected without a pause); the first lyric drag test failed at runtime on the `beginInteraction` bug above; everything else failed to compile on a symbol the fix introduces (`SlideTextFrames`, `LyricBox`, `ClearIconState`, `ToolbarLayout`, `ColumnDrag`, `nudgeSelection`, `commitCount`).

**Existing tests changed** (only what the migration forces; none asserted the Clear menu, the chip or the centred switcher, so no test of those was edited): `UI005hTests/UI005h_MigrationV13Tests.swift` lines asserting `applied.last == "v13"` (now `prefix(13).last`, v14 follows), in two places. Nothing else.

## Also changed

`LibraryStore.commitCount` (Persistence), `AppModel.debugPublishCount` (debug), the hook block in `UISnapshotRun.swift`, `UISnapshotMedia010.swift` (the Clear-menu preview picture removed), `ImportSheet.swift` (re-flow loss text), docs (change log, KI-166 to KI-170, hands-on checklist, data dictionary). No file under `docs/UI`, `docs/adr`, `AI/specs`, `Vendor`, `sdk`, `dist`, `.claude` or the Stage and Screens files was touched. xcodegen regenerated `WORSHIPFLOW.xcodeproj/project.pbxproj` (one new file).

## Not verified

VoiceOver and Tab order on the lyric boxes and the new inspector rows; other window sizes; the real system drag (see above); the lyric boxes with a plated theme (none are offered); a theme with no second language; light mode; hardware: none (Implemented, Unit Tested, driven in the debug build only).

## Check

See the final message: `./scripts/check.sh` twice; results recorded below.

CHECK_RESULTS_PLACEHOLDER
