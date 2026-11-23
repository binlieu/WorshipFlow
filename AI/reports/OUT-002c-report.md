# OUT-002c report: the first time a slide is shown, the output no longer does its first-use work on the render thread

Feature IDs: OUT-002, KI-007. Model: Sonnet. Verification: Implemented, Unit Tested (offscreen counts). Not run in a soak (the coordinator runs that).

## 1. Cause (confirmed before any change)

The soak cycles `SoakDeck.slides`: **6 distinct slides** (`App/Sources/SoakConfig.swift`), 117 advances in 600 s. The six drops at 0.234, 5.234, 10.350, 15.450, 20.533 and 25.650 s are the first show of slides 1 to 6; the 111 later advances (every slide already seen) dropped nothing.

What the output's `Compositor` does the first time it draws an unseen slide, on the render thread (`OutputRenderer.tick` -> `Compositor.encode`):

- a **fit computation** (`TextFitter.status`, Core Text measure) once per slide (`fitComputationCount`),
- a **Core Text rasterisation** per text layer (`rasterizationCount`), here two (primary and secondary line),
- then the texture upload.

Measured by `Packages/WorshipFlowKit/Tests/RenderEngineTests/OUT002c_FirstUseCostTests.swift` (written first; counts asserted, time printed only):

- a slide of the soak's shape at 1920x1080, unseen: first frame 2 rasterisations + 1 fit; the same scene again: 0 and 0 (counts unchanged). Printed offscreen frame time 35 to 43 ms first, 14 to 15 ms second: the difference, about 20 to 29 ms, is more than one 60 Hz refresh (16.7 ms), so one missed refresh (33.33 ms interval) per first show, as in the log.
- the soak's six real slides composed through `ShowState` and `PublishedScenes` and drawn on one compositor, no gate: **12 rasterisations and 6 fits** (`OUT002c_SoakDeckTests`).
- The app does have a warmer (`TextWarmer`, `ImageWarmer`, called from `AppModel.scheduleImageWarm`), but it warms the **selected (preview) slide, 300 ms after the show changed**. In the soak, `.trigger` selects and goes live in one step, so the warm runs for the slide that is already on screen, after the output has drawn it cold. That is why the existing warm did not help here (read from the code; not measured in the live app).

Also: the first drop at 0.234 s is the first scene of the run (output start-up); see "Not done".

### The lone drop at 531.733 s

The evidence does not identify it. What I could check:

- **Video loop point: not supported.** The soak's clip (`TestMedia/loop-1080p5994.mov`) is 20.004 s long and the report's final player time (19.64 s at 600 s) puts loop points at about 0.24 + k x 20.004 s, i.e. 520.4 s and 540.4 s: nothing at 531.7 s, and the earlier loop points (20.25, 40.25 s ...) show no drops.
- **Cache eviction or size limit: not supported.** The lyric cache holds 64 entries, the soak uses 12; the shared stores are far from their byte limits; memory was flat (133 to 181 MB).
- **A slide advance:** advances come about every 5.1 s (the six drop spacings are 5.00 to 5.12 s), so the 104th advance would be near 530.6 to 531.7 s, within the cadence drift. It could be an advance, but advance times are not logged, and a later advance of an already-seen slide cost nothing for the other 110.
- **A system event** (WindowServer, another process, display power/colour work): cannot be confirmed or excluded from this log.

Confidence: low. I would treat it as one unexplained miss of one refresh (0.003 % of frames). A soak that also logs each advance time (a small reporting change, not done here) would show whether it coincides with an advance.

## 2. Change

New `Packages/WorshipFlowKit/Sources/OutputEngine/ScenePreparationGate.swift`:

- `ScenePreparation.needsWork(incoming:shown:)`: true when the incoming scene has a non-ticking text layer, or an image path, that the scene on screen does not. Blackout, Clear, and a clock/timer tick (`ticks` layers) need nothing.
- `ScenePreparationGate.sceneToDraw(_:width:height:)`, called once per frame from the render thread: returns the scene to draw. Same scene as on screen: returned untouched (no request). New scene that needs work: asks the preparer once, keeps returning the scene on screen, and returns the new one in one frame when the preparation has finished. **Bounded: after 3 held frames (`defaultMaxHeldFrames`) it switches anyway**, drawing as before, so a command is never held back for long and never lost. The first scene an output ever draws, Blackout and Clear are returned at once.
- Ordering and cancel: each request carries a token; a newer scene replaces the pending one (the older was never shown and is never drawn), a late finish of a replaced or already-shown request is ignored, Blackout/Clear cancels the pending wait. A scene is only ever replaced by a newer one, so the published order is kept.
- `BackgroundScenePreparer`: one background worker, **one-slot mailbox** (only the newest request is kept, however many scenes arrive, so the queue cannot grow), skips a request that is no longer wanted. It runs `TextWarmer.warmNow` (Core Text raster + fit into `SharedTextStore`) and the new `ImageWarmer.warmNow` (decode into `SharedImageStore`) at the output's real drawable size. Existing store limits (192 MB text, LRU fits, image store) unchanged.
- `OutputRenderer`: one line hooks the gate in (`gate.sceneToDraw(sceneProvider(), ...)`); the gate is created in `init`.
- `RenderEngine/ImageWarmer.swift`: `warmNow(scene:)` added (same loads as the async `warm`, on the calling thread), `SceneDescription.imagePaths` made `public`. No behaviour change for existing callers.

Why this shape: it fixes the cause at the one place all window/display outputs share, uses the existing warmers and stores (no new cache), and keeps command-to-publication unchanged (the gate is downstream of the scene provider; only the display of a cold scene can lag by at most 3 frames, 50 ms at 60 Hz, instead of dropping one frame).

Option 2 (prepare the next slide when one goes live): **not done.** The gate already makes a cold advance cost no dropped frame; the app-level warm sizes its guess at 1920x1080 and cannot be unit tested in the package, so it adds risk for a small further gain (it would only remove the up-to-3-frame hold). Recommended as a separate small task if the hold is noticed.

SDI: `SDIOutput`, `SDIFrameRenderer`, the scheduler and Fill/Key pairing are untouched; the gate is only in `OutputRenderer` (window and display outputs).

## 3. Tests written first and their failing output

Red phase (gate as a pass-through skeleton, before the implementation): `swift test --filter OUT002c_ScenePreparationTests`: 12 of 14 tests failed on assertions, for the right reason (no request ever made, `m.count -> 0 == 1`, scene returned at once instead of the previous one, `compositor.rasterizationCount -> 1 == 0`, `compositor.fitComputationCount -> 1 == 0`, background queue `queue.count -> 0 == 1`, `warmed.items -> [] == ["job 499"]`). The two that passed against the skeleton were the trivial ones (stale request not prepared; same bytes).

After the implementation, and after a first full check found `RenderProblemReportingTests.aFrameWithAnImpossibleLayerIsStillSubmitted` (existing, not edited) failing because the very first frame was held: the gate now draws the first scene at once (tests adjusted to that rule; the existing test passes unedited). `OUT002c_SoakDeckTests.throughTheGate...` was written after the implementation; its counterpart without the gate (12 rasterisations, 6 fits) is the control.

Files: `Tests/RenderEngineTests/OUT002c_FirstUseCostTests.swift` (2), `Tests/OutputEngineTests/OUT002c_ScenePreparationTests.swift` (14), `Tests/UI005hTests/OUT002c_SoakDeckTests.swift` (2). Covered: no first-use work on the render call (counts); published order with a late earlier completion; a newer scene cancels an older never-shown one; Blackout never waits and an old completion cannot bring the slide back; the wait is bounded (3 frames) also with a new scene every frame; unchanged scene never re-requested; clock tick and resize not gated; bytes identical with and without the gate; queue holds one request however many are published; stale request skipped. No wall-clock assertions. The digest suites (`FIXQ_PublishedScenesDigestTests`, `SYS015_ScenesDigestTests`, `UI007c_RenderDigestTests`) and every existing test pass unedited.

Offscreen soak-deck result (step 4): the soak's six slides on one compositor: **without the gate 12 rasterisations and 6 fits on the render call; through the gate 0 and 0.**

## 4. Check

`./scripts/check.sh`: **exit 0**; package tests **3,507 passed** in 552 suites (3,488 before plus 19 new: 2 + 14 + 2 = 18 OUT002c tests and one counted differently by the runner; the new OUT002c suites ran 18 and passed), Debug and Release app builds succeeded, "the Release app carries none of the measuring hooks" OK. Swift 6 strict concurrency clean in both configurations (the script builds both). No timing-flaky suite failed, so no re-run was needed.

An earlier full check (before the first-scene rule) failed once: the existing `RenderProblemReportingTests.aFrameWithAnImpossibleLayerIsStillSubmitted` (3,506 tests, 1 issue), because the gate held the very first frame. Fixed by drawing an output's first scene at once (see section 3); the test was not edited.

## 5. Files

- New: `Packages/WorshipFlowKit/Sources/OutputEngine/ScenePreparationGate.swift`
- Changed: `Packages/WorshipFlowKit/Sources/OutputEngine/OutputRenderer.swift` (gate member, init, one call in `tick`), `Packages/WorshipFlowKit/Sources/RenderEngine/ImageWarmer.swift` (`warmNow`, `imagePaths` public)
- New tests: the three files above. This report.

## 6. Text for the coordinator (docs not edited)

- Change log: "fix(OUT-002c): window and display outputs prepare the text and images of a scene they have not shown (Core Text, fit, decode) on a background queue and keep drawing the previous scene until it is ready, at most 3 frames; the first show of each soak slide no longer costs one missed refresh. Blackout, Clear, the first scene and clock ticks are never held."
- KI-007: six of the seven drops of the 600 s soak (0.234 to 25.650 s) were the first show of each of the soak's six slides; fix landed, to be confirmed by a new 10-minute soak on a 60 Hz display (expect at most the start-up drop and no drop at 5.2, 10.4 ... 25.6 s). The drop at 531.7 s is unexplained (loop point and cache eviction not supported by the evidence).

## 7. Not done / stopped short

- The first scene of a run (output start-up) is still drawn cold: an existing test (`aFrameWithAnImpossibleLayerIsStillSubmitted`, not to be edited) requires the first frame to draw the scene, and an output has nothing else to show. The 0.234 s drop is therefore probably still there.
- Texture creation and upload of the prepared bitmaps, gradient/plate/shape bitmaps and object text layers are still done on the render thread (only lyric text layers and images are prepared). Counted only for Core Text and fit; not measured as time in a live output.
- Next-slide warm in the app (option 2), see above.
- No soak on a real display (rule); no live frame timing measured.

## 8. Not verified

- Any effect on real dropped frames: no soak ran; only offscreen counts show the first-use work is gone from the render call.
- That the output compositor's drawable size always equals the size the warm used (it is read from `layer.drawableSize` at the same tick, so it should; not observed live).
- The 3-frame limit against a real cold preparation time under load (about 20 to 30 ms offscreen here); if it takes longer the scene is drawn cold as before.
- Image-bearing scenes through the gate (only the path logic is tested; a missing file does not hold the gate beyond the limit).
- Release build timing; hardware/SDI (untouched); Hardware Verified and Live-Service Verified: Not Verified.
