# FIX-A report: render, output and media engine review fixes

Date: 2026-11-20. Scope: `Sources/RenderEngine`, `Sources/OutputEngine`, `Sources/MediaEngine` and new test files `EngineReviewFixTests.swift` in `RenderEngineTests`, `OutputEngineTests`, `MediaEngineTests`. Nothing in `App/`, `OperatorCore`, `Domain`, `Persistence` or their tests was touched. No git state changed.

Result: `./scripts/check.sh` exits 0. Package tests: 653 tests in 109 suites passed (550 before; the other agent's work accounts for part of the increase). My three targets alone (scratch package, run 8 times): 130 tests in 29 suites passed every time.

## Method notes

- Every finding has a test written before the fix. Where the finding was about new API (warm-up, health, flush counter, window-fit decision) I first added a do-nothing stub so the test compiled and failed on its assertions, then implemented. For R4 and R5 I wrote the fix before the test by mistake, then temporarily neutralised the fix (`OutputWindow.applyOutputPolicy`, `OutputWindowFit.decide`), recorded the failures below, and restored it.
- Pre-fix output was captured in `/private/tmp/claude-501/scratch/{render,output,media}-prefix.txt` and is quoted below in short form.
- While the other agent's tests did not compile, I ran my targets in a scratch package outside the repository (`/private/tmp/claude-501/scratch/pkg`, symlinks to the live sources and my test directories). The final runs are the real `./scripts/check.sh`.
- Three small test seams exist in production code and are documented where they sit: `ImageDecoder.statProbe` (which thread asks for a modification date), `AVFoundationCallProbe` and `TrackedLock` (whether an AVFoundation call is made under the lock), and an injectable clock in `MediaFrameResolver`.

## R2: an unrenderable layer aborts the frame

- Fixed. `TextRasterizer.rasterize` no longer throws for size: width and height are clamped to `maxDimension` (16384) and the bitmap to `maxBitmapBytes` (512 MB), keeping the top-left part (`RasterizedText.clipped`). `Compositor.encode` skips a text layer, text-box object or shape that cannot be drawn and records a de-duplicated message; `Compositor.renderProblems` holds the last frame's list (empty again once a frame has none; thread-safe). Reported through `OutputTarget.renderProblems`, `MetalOutput`, `OutputRenderer.renderProblems` and `ScreenReadout.renderProblems`.
- Failed before (RenderEngineTests): `zeroSizeTextLayerIsSkippedAndTheRestPresents`, `textBoxObjectThatCannotBeLaidOutIsSkippedToo`, `textTallerThanTheLimitIsClippedNotThrown`, `rasteriserClipsAtTheLimitInsteadOfThrowing`, `problemsAreReportedDeduplicatedAndClearedWhenTheyGoAway`: `Caught error: .invalidSize`. OutputEngineTests: `theOperatorReadoutCarriesTheOutputsRenderProblems` (`readouts().first?.renderProblems → []`), `aFrameWithAnImpossibleLayerIsStillSubmitted` (`renderer.renderProblems.count → 0`, the stub). All pass now.
- Still unverified: the problem text is not shown anywhere in the app yet (needs wiring, see "New API").

## R4 (canHide): output windows and Hide

- Fixed. New `OutputWindow` (NSWindow subclass) used by `DisplayOutput` and `WindowOutput`: `canHide = false`, `hidesOnDeactivate = false`, and `performClose` ignores a close that arrives during a key event (Command-W). The title-bar close button of a `WindowOutput` still works (mouse event). `DisplayOutput` was already not `.closable`.
- Failed before (OutputEngineTests): `windowOutputWindowIsExcludedFromHide`, `displayOutputWindowIsExcludedFromHide` (`window.canHide → true`), `aKeyboardCloseIsIgnoredButTheTitleBarButtonStillWorks` (`allowsClose(during: .keyDown) → true`; recorded with the fix temporarily removed). Pass now.
- Unverified: real Command-H / Hide Others / Command-W against a running app with an output open. The decision is a pure function plus window properties; the key routing through the SwiftUI menu was not exercised. The Hide menu and Quit confirmation are FIX-B's.

## R5: no re-check after a display reconfiguration

- Fixed. `OutputWindowFit.decide(windowFrame:windowDisplayID:target:name:afterReframe:)` is pure: `.none`, `.reframe(frame)` or `.fault(message)`. `DisplayOutput.reconcileGeometry()` calls it on `didChangeScreenParametersNotification` (and on a new `NSWindow.didChangeScreenNotification`), re-frames with `setFrame`, calls `syncDrawableSize()` so the drawable follows, decides again with `afterReframe: true`, and a surviving mismatch finishes the output with the fault message (the coordinator shows it as a faulted screen). Missing display still finishes via `availabilityProblem()` first.
- Failed before (recorded with `decide` neutralised to `.none`): `aDisplayThatChangedSizeGetsItsWindowReframed`, `aDisplayThatMovedGetsItsWindowReframed`, `aWindowOnTheWrongDisplayIsMovedBackThenFaultedIfItStays`, `aReframeThatDidNotTakeIsAFault`, `aMissingDisplayIsAFault`. Pass now.
- Unverified: the handler itself (`reconcileGeometry`, the observers, `setFrame`, the drawable resize) needs a real second display or a resolution change, which I did not do. Only the decision is unit tested.

## R7: file-system calls on the render thread

- Fixed. In `.background` mode `Compositor.imageTexture` no longer calls `modificationDate`; once a second it asks the loader to re-check (`requestInBackground(path, since:)`), which stats on its own thread and answers `unchanged` or new pixels. A failed reload keeps the previous texture, keeps the old modification date (so it tries again) and the path is in `unavailableImagePaths`. `.synchronous` (offscreen, previews) still stats inline by design.
- Failed before: `renderThreadNeverStatsTheFile` (`log.callsOnRenderThread → 2`), `failedReloadKeepsThePreviousTextureAndReportsTheProblem` (image vanished: red channel not > 240 after the failed reload). `changedFileIsStillReloadedInTheBackground` was a guard and passed before and after. Pass now.
- Unverified: behaviour on a really sleeping or disconnected volume; the test simulates a failed read with a garbage file.

## R9 (reporting): clip that fails or stalls after opening

- Fixed (reporting only; the app's reaction is a follow-up). `VideoPlayerSource.playbackHealth` (`.healthy`, `.failed(reason)`, `.stalled`) and `setOnHealthChange`. Failure comes from KVO on the current item's status, on the `AVPlayerLooper` status, and `failedToPlayToEndTime`. `.stalled` is set when the watchdog has re-seeked 3 times in a row without the time moving past the kick point (`isUnrecoverable`); it clears if the clip moves again. `MediaRegistry.availability(of:)` returns `.notOpen / .starting / .delivering / .failed(why) / .stalled` per asset id, `availabilitySnapshot()`, and `setOnAvailabilityChange` fires on failure, stall, recovery and when a still finishes decoding. `unavailableAssetIDs` now also includes assets whose player failed or stalled.
- Failed before (MediaEngineTests, deliberately broken `.mov` and `.png` files): `aBrokenFileIsReportedAsFailedAfterOpening`, `aBrokenLoopingFileIsReportedToo`, `theHealthCallbackFiresOnce`, `aBrokenForegroundClipIsReportedPerAssetId` (`unavailableAssetIDs → []`, no callback), `aMissingFileIsReportedAtOnce`, `aGoodClipStartsThenDelivers` (`.notOpen` instead of `.starting`), `aStillIsDeliveringOnceDecodedAndFailedWhenItCannotBe`, `snapshotListsEveryOpenAsset`, `stallRecoveryGivesUpAfterRepeatedFailures`. Pass now.
- Unverified: the stall path end to end. A player that is told to play and genuinely does not advance cannot be produced reliably; only the threshold function is tested. `.delivering` means "an output has pulled at least one frame", so a clip reads `.starting` while no screen is open.

## R10: images pop in late, decoded per screen

- Fixed. New process-wide `SharedImageStore` (decoded pixels, one decode per file, concurrent callers for the same path wait for one decode, bounded to 32 images / 192 MB, LRU). A compositor with an empty slot takes an already-decoded image from the store at once, with no file-system call, so a second screen shows it in its first frame. `Compositor.prepare(scene:)` (synchronous, for a compositor you own off the render thread) and `ImageWarmer.warm(scene:)` / `warm(scenes:)` (async, decode into the shared store, pinned for 60 s against eviction, returns the unreadable paths).
- Failed before: `secondScreenReusesTheDecodeAndDrawsOnItsFirstFrame` (first frame green 0, decode count 2), `warmedImageIsInTheVeryFirstFrame`, `warmingReportsAFileItCannotRead` and `prepareSceneLoadsEveryImageKindIntoThisCompositor` (against stubs). Pass now. `imageDecodeCount` now counts decodes this compositor's loader performed; an image another screen already decoded does not count.
- Unverified: the app does not call the warm-up yet; real decks with many large images (memory: the store holds pixels and each screen holds a texture).

## R14: texture cache never flushed

- Fixed in `MediaFrameResolver`: `CVMetalTextureCacheFlush` at most every 2 seconds (`flushInterval`), clock injectable. Test `theTextureCacheIsFlushedPeriodicallyNotEveryFrame` failed against the stub (`flushCount → 0`), passes now. `PreviewRenderer` in `App/` is FIX-B's. Unverified: memory growth over a long run.

## R16: shader compilation per output on the main thread

- Fixed. `SharedGPU` builds the Metal library and each pixel-format pipeline once per device and shares them; `Compositor.warmUp(device:)` and `OutputCoordinator.warmUp()` (returns at once, runs on a background task) let the app do it at launch.
- Failed before: `openingManyCompositorsCompilesTheShadersOnce` (`shaderCompileCount → 13`, was 9: four more compiles for four compositors). Passes now (0 compiles).
- Timing (offscreen, this machine): before, four more compositors cost 2.5 ms with 4 compilations; after, 0.7 to 1.6 ms with 0. The first compile in a fresh process costs about 67 ms (measured in `openingManyCompositorsCompilesTheShadersOnce`). The gain is small here because the Metal system shader cache makes repeat compiles cheap; the real saving is the first compile moving off the main thread once the app calls `warmUp()`. Windows are still built on the main thread, once per output (unchanged, unavoidable in AppKit).

## R18: lock held across AVFoundation calls

- Fixed in `VideoPlayerSource`: `latestPixelBuffer`, `watchForStall` and `attachOutput` copy what they need under the lock and call AVFoundation outside it; `stop()` bumps an epoch so a frame fetched just before it is not stored after it. KVO observations replace the old unlocked ones.
- Failed before: `playerCallsAreMadeOutsideTheSourcesLock` (`callsUnderLock → 209`), `loopingSourceSwapsItsOutputWithoutTheLockToo` (`→ 300`). Pass now. Unverified: the actual deadlock was "plausible, unlikely" and never reproduced; the test proves the call sites, not an absence of deadlock.

## Files

Changed: `Sources/RenderEngine/{Compositor,ImageLoading,TextRasterizer}.swift`, `Sources/OutputEngine/{DisplayOutput,WindowOutput,MetalOutput,OutputRenderer,OutputCoordinator,OutputTarget,MediaFrames}.swift`, `Sources/MediaEngine/{VideoPlayerSource,MediaRegistry}.swift`.
Created: `Sources/RenderEngine/{SharedGPU,ImageWarmer}.swift`, `Sources/OutputEngine/OutputWindow.swift`, `Tests/RenderEngineTests/EngineReviewFixTests.swift`, `Tests/OutputEngineTests/EngineReviewFixTests.swift`, `Tests/MediaEngineTests/EngineReviewFixTests.swift`.
(all under `/Volumes/Storage/chilt/worshipflow/Packages/WorshipFlowKit/`)

## New API for the app to call

1. Launch: `OutputCoordinator.warmUp()` (or `Compositor.warmUp()`), once, before any screen opens.
2. Preview scene: `await ImageWarmer.warm(scene:)` (or `warm(scenes:)` for every screen's preview) whenever the preview scene changes; it returns the unreadable image paths. Call it before the scene is triggered.
3. Operator readout: `ScreenReadout.renderProblems: [String]` per screen (new, defaulted). Show it next to `unavailableImagePaths`.
4. Media: `MediaRegistry.availability(of:)`, `availabilitySnapshot()` and `setOnAvailabilityChange(_:)` (hop to the main actor in the handler). For a foreground clip that reads `.failed` or `.stalled`, the app can show it and end the foreground so the words come back (SceneComposer / R9 follow-up).
5. `OutputTarget.renderProblems` is a new protocol requirement with a default `[]`, so existing conformers compile unchanged.

## Not verified

Real display hot-plug, resolution change and mirroring (R5 handler); Command-W, Hide and Hide Others against the running app (R4); a genuinely stalled player (R9 stall path); a sleeping network volume (R7); long-run texture cache and image memory (R10, R14); data races under Thread Sanitizer; the app wiring above. The full `swift test` and `check.sh` passed with the other agent's work in the tree at the time of the final run; their changes after that were not re-run.
