# OUT-002f report: the preparation gate covers slide objects, and the output-path lows of the fifth review

Feature ID: OUT-002f (REVIEW-5 M6 = KI-278; L17, L18, L20, L21, L22 = KI-279; L19, L23). Model: Sonnet. Branch: the worktree branch (not merged, not pushed).
Verification level claimed: **Implemented** and **Unit Tested** only. Nothing here is a measured improvement; nothing was run on a display.

No migration, no stored type changed. No existing test was edited; none conflicted with a change (the existing OUT-002c, -d, -e and FIX-J suites pass unchanged).

## Gate
`./scripts/check.sh` with the exit status captured: `CHECK_EXIT=0`; package tests "3669 tests in 583 suites passed" (of which 27 new OUT-002f tests across the three new files), domain boundary OK, project generated, Debug app build OK, Release compile OK (release-only hooks check OK). One run only: no timing-flaky suite failed, so no re-run was needed. The build went to a scratch derived-data folder that was deleted afterwards; no app was launched.

## Per item

### 1. M6, text boxes, shapes and fit-to-box text prepared off the render thread: done
- What the code did: `needsWork` looked at lyric text layers and image paths only. `TextWarmer.warmNow` only ran `layoutReport` (lyric text and plate). A text object's fit was computed at draw time and never put in the shared store (`objectFitStatus` read only the compositor's own cache); a shape bitmap was rasterised at draw time into the compositor's own cache.
- Failing tests first (old code): `aNewTextBoxAShapeOrAFitBoxIsSeenByNeedsWork` (4 expectations: `needsWork` false for a new text box, fit box, shape), `aSceneWithANewTextBoxIsHeldUntilItIsPrepared` (the scene was adopted at once, no request), `aWarmedObjectSceneCostsNoLayoutNoFitAndNoShapeBitmapOnTheFirstFrame` (an output's own compositor still did 2 Core Text layouts, 1 object fit, 1 shape bitmap after the warm), `throughTheGateNoTextBoxShapeOrFitBoxCostsAnythingOnTheRenderCall` (same three counters, through the gate with a synchronous preparer).
- Change: `needsWork` also reports a new non-ticking text object or a new shape (an object already on screen, a removed object, a video or image object, and ticking text are not new work). `Compositor.prepareObjects` lays out text boxes, computes their fit and rasterises shapes as a frame would; `TextWarmer.warmNow` calls it after `layoutReport`. `objectFitStatus` now reads the shared fit store and publishes to it when the warmer runs it. Shape pixels have a shared, size-bounded store (`SharedTextStore.shape`, 64 MB, least recently used first); `shapeDraw` reads it and publishes to it from the warmer. The shape's texture is still made on the render thread (a texture upload, no drawing). `ShapeKey` became internal for the store.
- Also covered by tests: a warmed object scene draws the same bytes as an unwarmed one; warming the same scene twice still leaves everything in the stores.
- Soak deck: **not changed.** `App/Sources/SoakConfig.swift` and `OUT002c_SoakDeckTests` keep their six lyric slides, so the soak comparison is untouched. The object cases use their own scene in the OUT002f tests; the coordinator can add a separate object deck to the soak if wanted.
- Not verified: no frame was drawn on a display; whether a real slide change with text boxes drops fewer frames is not measured.

### 2. L17, a prepared scene is not held a frame: done
- Old code: every scene with new words went to the background queue and the old scene was drawn for at least that frame; the worker made a `Compositor()` for each request.
- Failing tests first: `aScenePreparedBeforeGoLiveIsAdoptedOnTheSameTickWithNoRequest` (returned the old scene, one request made), `aPreparedSceneWithAChangedClockIsStillAdoptedAtOnce`, `theWarmerDoesNotMakeACompositorForEachRequest` (5 warms made 5 compositors; the counter `TextWarmer.compositorsCreated` was added in a first, behaviour-free step so this fails by value, not by compile error).
- Change: new `RenderEngine/PreparedScenes.swift`: the warmer notes each scene it prepared (16 most recent, per output size, ticking text left out of the comparison). When a scene changes, the gate asks `PreparedScenes.isPrepared` (also requires every image the scene names to be in the image store) and, if so, adopts at once and makes no request. The check runs when a new request would be made, not on every frame. `TextWarmer` keeps one long-lived compositor under a lock (outputs warming the same words take turns; the second finds it in the stores). That compositor forgets its own caches before each scene (`resetPreparedCaches`), so a store entry that was evicted is made again rather than skipped because the warmer's compositor still held it.
- Guard tests that passed before and after: a scene warmed for another size, and a scene whose image is not in the store, are still prepared first.
- Limit: `PreparedScenes` is a note, not a guarantee. If the bounded shared stores let an entry go after the warm, the scene is drawn with first-use work on the render thread, as before OUT-002c.

### 3. L18, the stage Blackout never waits: done
- Old code: the composer's stage Blackout scene adds a "BLACKOUT" layer that is not on screen, so the gate held it up to 3 frames. Tests `theStageBlackoutSceneIsAdoptedOnTheTickItArrives` and `liftingTheStageBlackoutIsDrawnAtOnceToo` use `SceneComposer.scene(for: .stage, ...)` itself (not a hand-made scene) and failed (held, one request); `theBlackoutWordIsWarmedWithAnySceneThatIsPreparedForAnOutput` failed (1 rasterisation on the render call).
- Change: `needsWork` ignores a text layer that equals `StageComposer.blackoutLayer` in the layer's own colour (visibility of that function made `public`; its output is unchanged, the stage composer is untouched). `ScenePreparation.warm` also prepares that word at the output's size, so it is in the store when Blackout comes.
- Limit: the first stage Blackout before any slide change was prepared for that stage output (the very first scene an output draws is adopted without preparation) rasterises the word on the render thread once (a few characters). Clear: an audience Clear (background removed, words kept) needs no work and is not held; `audienceClearIsNotHeldEither` passed on the old code too (regression guard).

### 4. L20, a preparation that never returns stops costing later scenes: done
- Rule (in the gate's header): a request that was waited for the whole hold (`maxHeldFrames`, its own request, not one replaced by a newer scene) without finishing is taken to be stuck. From then on new scenes are adopted at once and **no request is made**, so no thread and no work is added behind it, until any preparation reports done, or `stallProbeFrames` (600) calls of the gate (its own tick count: 10 s at 60 Hz, and nothing counts while idle) have passed; then one request is tried again and held as usual.
- Failing tests first: `aPreparationThatNeverReturnsStopsCostingLaterScenes` (15 of 20 later scenes held), `holdingResumesAfterTheProbeLimitEvenIfNothingEverReturns`, `holdingResumesWhenAnyPreparationReportsDone`. Passing guards: `aSlowButFinishingPreparationNeverStartsAStall`, and `oneWorkerAndOneWaitingRequestHoweverManyScenesArriveBehindABlockedPreparation` (the real `BackgroundScenePreparer` with a blocking warm: 200 requests, one worker run), and the existing "new scene every frame" test (a replaced request does not count as stuck).
- Not verified: a real stalled network volume (hands-on).

### 5. L21, outputs switching on the same frame: not built; limit written
- A shared preparation would not align the links of different outputs (each has its own display link) and is not a small change. Written into the gate's header: outputs whose scene is already prepared (the usual case after item 2) switch on their own next tick; an unprepared scene can show up to `maxHeldFrames` frames (50 ms at 60 Hz) earlier on one output than another. The shared warm compositor lock and `PreparedScenes` already make a second output find what the first prepared, which removes most of the duplicated warming; this is by reasoning, not measured.

### 6. L22, no allocation or hashing per frame for fit-floor text objects: done
- Old code: `objectFitStatus` built a `FitKey` (array allocation plus hashing of words and style) on every frame. Tests `aFitFloorTextObjectBuildsItsFitKeyOncePerChangeNotOncePerFrame` (10 frames built 10 keys) and `twoFitFloorBoxesEachKeepTheirOwnAnswer` failed on a counter added first (`objectFitKeyBuildCount`).
- Change: the compositor keeps the last answers of up to 16 text boxes (layer, size, status) and returns one after a compare, as the lyric path does. Changed words, a new size or a 17th box build the key once.

### 7. L19, refresh rate follows a window moved to another display: done (small)
- The screen-change handler now calls the same code as the screen-parameters handler (`followScreenRefreshRate`): the rate, the target interval and the link's frame-rate range change together and only when the rate changed. Pure helper `MetalOutput.newRefreshRate(screenMaximum:current:)` is tested (`OUT002f_RefreshRateTests`; on the old code the symbol did not exist, so that test failed to compile). Not verified: a window dragged between real displays.

### 8. L23, `targetTimestamp`: rule corrected from existing evidence; no new run
- The session's screen was locked (the system reported the screen as locked when the run would have started), so the 60-second run was not made, as the brief expected for a hidden window. Evidence used: the hour soak of 2026-11-26 23:18, where `cb` (tick start minus `linkTimestamp`) was steadily near minus one frame period, about -16 ms, on every listed tick. That means `targetTimestamp` is a future time, and an on-time callback runs about one period before it.
- Change: `FrameLateness.classify` takes the callback as due one period before the stamp: late by `start - (linkTimestamp - period)`, still against 1.5 periods (so a callback more than half a period after the stamp is late). Header, the report's rule lines (`FrameEventLog.ruleLines`) and the `cb` description now say so. The existing `aCallbackFarAfterTheLinksOwnTimestampIsAppLate` still passes unchanged (its tick ran 30 ms after the stamp).
- Failing test first: `aCallbackThatRanAfterItsTimeIsAppLateEvenThoughTheTimestampIsStillAheadOfIt` (a callback 30 ms later than due, stamp still 13 ms ahead of it: classified "presented late", should be "app late"). Guards: on-time ticks at minus one period are not late; 15 ms late is not late.
- How to read earlier reports: before this change the "app late" class could be reached only through the start-to-start gap (a callback running after the refresh it was aimed at was the only other way). So earlier "late callbacks" and "app late" counts came from the start-to-start gap alone, and a callback that was late relative to its own schedule but earlier than the stamp was filed as "presented late". The "presented late" figures of earlier soaks may therefore include some app-late callbacks; they cannot be re-split without the tick records.
- Not verified: the one-period figure is the observed value from one soak report at `preferredFrameLatency` 1 on one display, not a documented guarantee, and no fresh run confirmed it.

## Files
Sources: `OutputEngine/ScenePreparationGate.swift`, `OutputEngine/MetalOutput.swift`, `OutputEngine/TickTimeline.swift`, `OutputEngine/FrameEventLog.swift`, `RenderEngine/Compositor.swift`, `RenderEngine/TextStores.swift`, `RenderEngine/PreparedScenes.swift` (new), `Domain/StageLayout.swift` (one `public`).
Tests (new): `OutputEngineTests/OUT002f_GateTests.swift`, `OutputEngineTests/OUT002f_LatenessTests.swift`, `RenderEngineTests/OUT002f_ObjectPreparationTests.swift`.

## Change-log text
OUT-002f (REVIEW-5 M6, L17 to L23): the preparation gate now sees slide objects (a new text box, fit-to-box text or shape is laid out, fitted and rasterised off the render thread, into the shared stores, with the lyric text). A scene the warmer already prepared is adopted on the tick it arrives; the warmer keeps one compositor. The stage Blackout scene is never held. A preparation that never returns no longer delays later scenes (stall rule, probe after 600 gate calls). A fit-to-box text object no longer builds a key per frame. A window output follows the refresh rate of the display it is moved to. The late-callback rule treats the link's target timestamp as a future time. Implemented, Unit Tested; Not Verified on a display.

## Known-issues text (unnumbered)
- Outputs decide alone when a scene that was not prepared is ready: one output can show it up to three frames (50 ms at 60 Hz) before another. Scenes warmed ahead of Go Live switch on each output's own next tick.
- `PreparedScenes` is a note: a bounded store that let an entry go after the warm leaves first-use work on the render thread for that scene.
- The first stage Blackout before any scene was prepared for that stage output rasterises the word "BLACKOUT" once on the render thread. A custom stage layout's warning colour is prepared only after its first Blackout.
- The soak deck still has lyric lines only; text boxes, fit boxes and shapes are covered by unit counters, not by a soak.
- `targetTimestamp` is taken as one period after the due time from one soak report; not confirmed by a fresh run (screen locked on 2026-11-27).
- The shape texture upload and the text texture upload still happen on the render thread; only layout, fit and bitmap drawing moved.

## Hands-on entries
1. Slide with text boxes: Go Live on a slide whose new content is a text box, a "Shrink to fit box" box and a shape (preview it first, then trigger): compare drops at the change with and without the preview step; run the soak with a separate object deck.
2. Stage Blackout: press Blackout with a stage screen open (before and after changing a slide once): the BLACKOUT word and the black audience screen should appear on the same frame.
3. Added latency: Go Live on a warm slide on a window output with a slow-motion capture: the new slide should appear on the tick of the command, not one later.
4. A stalled file: put a slide image on a network volume, drop the connection, change slides repeatedly: only the first change waits (about 50 ms); later changes show at once; reconnect and check that holding resumes.
5. Refresh rate: drag a window-destination output between displays of different rates: the Screens readout should not show a burst of dropped and late frames after the move.
6. Callback timing: run the soak for a minute on a visible display and read `cb` and `m` of the listed ticks: `cb` near minus one period when on time, and a late callback should now be classed "app late".
