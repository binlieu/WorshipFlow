# FIX-N report: fixes from the review of FIX-K and the Stage canvas

Feature IDs FIX-K, UI-005e. Level: Implemented, Unit Tested; keys driven in the running debug build (`scripts/fixn-keys.sh`, hook `UI_SNAPSHOT_FIXN`, `App/Sources/UISnapshotFixN.swift`). Not Hardware Verified, not Live-Service Verified. `./scripts/check.sh` run twice: exit 0 and exit 0, 2961 package tests each (2956 + 5 new before the last additions; 52 `@Test` in the new FIXN files), app build passes.

## Items (order 1, 3, 2, 4, 5, 6, 7, 8, 9, 10): all done

Test-first record (failing output seen before the code):
- 1: `FIXN_CanvasKeyRoutingTests` did not compile (`.canvas`, `canvasHasSelection:` are new symbols). Runtime failure, in the app as it was (copy of commit 1e5db03): after a click, drag or sheet on the Stage canvas the first responder was `StageKeyView`, router focus `slider`, and Right, Return, Space, B, B, Escape changed nothing.
- 3: `FIXN_StateTagTests` did not compile (`ShowStateTag` new).
- 2: `FIXN_FrameValidation*` (Domain, Persistence, ProgramPackage): 21 + 6 + 1 runtime failures (frames with zero or negative size, outside the canvas, NaN, overhanging, kept as stored).
- 4: `FIXN_ClearIconThemeTests` did not compile (`themeBackgroundKind`, `ClearIconRule.themeBackgroundKind`).
- 5: `FIXN_StageNudgeTests` did not compile (`StageNudgeSession`).
- 6, 7, 8: honest deviation: the code was written before the tests for these. The tests (`FIXN_EditInteractionRuntimeTests`, only old API) were then run against a copy of the old tree: 4 of 6 failed (typed position after an interrupted lyric drag not saved; apply-to-all wrote a slide with no words; apply-to-all not one undo step; re-selecting the same object joined the old nudge run). The routing part of 8 (`canvasLastClicked`, `.nudgeCanvas`) was also written first; its tests pass and its behaviour is in the real-key run below.
- 9: tests added (`FIXN_CopiedSlideFramesTests`, `FIXN_CanvasModesTests`, `FIXN_StagePointerTests`); `FIXK_CanvasGestureSourceTests` untouched. A gesture's coordinate space cannot be tested without a window; it stays covered by the source guard and the FIX-K mouse run.
- Existing test edited: `FIXK_LyricBoxTests.applyToAllSlidesGivesEverySlideThatFrameAndKeepsTheirOtherLanguage`, three assertions, because item 7 says one undo step restores every slide, which is the opposite of what it asserted. Nothing else existing was edited.

Decisions and findings:
- Edit canvas: it has no key view; its arrows come through the router as `moveSelection` and nudge. It never had the Space/Return/B defect (real run, before and after).
- Escape on the Stage canvas is now Clear (KI-183).
- Item 2: decode (`SlideTextFrames.init(from:)`, so database, package and `SlideContent` JSON) and scene composition both validate. `NormalizedRect.clampedToSlide` is the editor's clamp, shared.
- Item 4: `.media` theme counts as "theme video", `.image` as picture (KI-184).
- Item 5: Stage only; Edit already wrote per press into the in-memory slide with one undo step per run, fixed in 8.
- Item 8: `commitCount` and its observer are `#if DEBUG` (release build of Persistence compiled). Other debug-only observers (`debugPublishCount`, `debugLyricComposeCount`) are `#if DEBUG`.

## Real-key run (running app, scratch library, `--silent-audio`, window outputs, process stopped by the script)

The Mac's screen was locked, so the app could never become active and the window swallowed synthetic mouse clicks (events delivered, nothing selected; KI-182). Presses on the canvases were therefore made through the canvas's own press/move/release functions (`StageCanvasDebug`) and the Edit model's interaction calls; every key was a real event through `NSApp.sendEvent`, the key monitor and the responder chain. Each case: Right, Return, Space, B, B again, Escape.
- Before (old tree), Stage after click, after drag, after sheet: first responder `StageKeyView`, router focus `slider`; all six keys did nothing. After a mode change (new view) they worked. Edit and Screens: all worked.
- After, Stage after click, after drag, after sheet closes, after mode change: Return went live on the selected slide, Space advanced, B blacked out and B lifted it, Escape cleared; Right nudged the box 1 point (0.7400 to 0.7412 of the canvas width) and did not move the slide selection; router focus `canvas`.
- After, Edit (text box) after click, drag, sheet, mode change: same keys all worked, Right nudged the box; router focus none.
- After, Screens (no canvas box; the press is selecting a screen) after click, drag, sheet, mode change: all keys worked.
- Held Right x30 on the Stage: stored frame unchanged while held, one write and one republish at release, box moved 30 points.
- Button focused, canvas clicked last: Stage Shift-Down nudged 10 points; Edit Right and Shift-Down nudged; Space did not reach the show (the button keeps it).
- Not seen: the toolbar tag in a picture (the log shows modes `blackout` and `cleared`; the tag is unit tested and builds). A click with a real mouse: hands-on checklist.

## Item 10: MIDI

`orderIsKeptForABurst` failed because of too little patience under load, not a defect. Reproduced on the old tree with 30 busy processes beside the full suite: after 30 s the sink held 1 of 2000 messages (the first one, in order); the main actor, which runs the router's consumer, was starved. With 12 busy processes the burst took 17.3 s (0.02 s idle); in all runs: 2000 received, ports' drop counter 0, no mismatch. The fake and the real ports buffer 65,536 messages (drops beyond that, counted) in one FIFO consumer, so nothing is reordered; the sink is only touched on the main actor. The app is not exposed to loss or reordering; it is exposed to latency while the main thread is busy, like every command. Fix: the test's wait is a 600 s safety net, same assertions plus drop counter and received count; new `FIXN_BurstOrderTests` (5000 messages, and a bounded buffer sheds oldest and counts).

## Files

New: `ShowStateTag.swift`, `StageNudgeSession.swift`, `StagePointerSession.swift` (package); `UISnapshotFixN.swift`, `UISnapshotFixNPress.swift`, `scripts/fixn-keys.sh`; 12 `FIXN_*` test files. Changed: `KeyRouting`, `ClearIcons`, `SlideEditorModel`, `SlideEditing`, `SlideTextFrames`, `SceneComposer`, `LibraryStore`, `AppModel`, `StageCanvasView`, `SlideObjectsEditor`, `EditInspector`, `ContentView`, `MediaClearButtons`, `WorkspaceUIState`, `UISnapshotFixK` (key helper), `UISnapshotRun` (one hook block), `FIXK_LyricBoxTests`, `MIDIRouterTests`, the project file (xcodegen), `docs/16`, `17`, hands-on checklist. Not touched: `docs/UI`, `docs/adr`, `AI/specs`, `Vendor`, `sdk`, `dist`, `.claude`, git state.
