# FIX-L report: two intermittent failures in `./scripts/check.sh`

Feature IDs UI-005h (SDI readback), MEDIA-002 (player tests). Level: **Unit Tested**. Nothing here touches hardware; no hardware claim is made. The app was not run.

## 1. `UI005h_SDIReadbackTests.theFrameTheCardGetsIsTheFrameTheCompositorDraws`

**Cause: font registration in the test process, not the output.** The built-in looks name `InterVariable` (`Theme.outputFontName`). The app registers it at launch (`InterFont.base`, called from `applicationWillFinishLaunching` and `AppModel.init`), before any window or output exists. A test process has no launch: `FIXJ_MultiVerseTests`, `UI005hFixtures.registerInter()` and others register it process-wide when their suite starts. The failing test drew its frame, then rendered the expected picture; if Inter was registered between the two, the text was drawn in the system font first and in Inter second. The compositor keeps the first bitmap in its lyric cache, so the next frame (`again`) differs as well. That is exactly the pair of failures seen (line 24 and line 28).

**Evidence (deterministic reproduction, scratch test, removed).** Unregistered Inter: `SDIFrameRenderer.frame()`, then register the file, then `Compositor.renderImage`, then `frame()` again:
- before-vs-expected and again-vs-expected: the same 81,361 of 921,600 pixels differ, all inside x 252 to 1028, y 272 to 492 (the text box); the background is identical (first bytes 28, 15, 5, 255, the flat dark colour of the failing run's printout). So: the text, not the background, not the whole frame.
- Not shown, so not excluded in the abstract but ruled out by this result: a blit read before the command buffer finished (frame 1 would then be partly stale, not a clean text-face difference; the buffer is read after `waitUntilCompleted`), a reused shared buffer, a text raster that is late. `cachedText` rasterises synchronously, the warm-up (`TextWarmer`) only pre-fills a store the frame would otherwise fill itself, so a frame never draws without its text.
- An existing test (`FIXJ_SDIReadbackSceneChangeTests`) already worked around the same race with the Classic theme and a comment saying so.

**Failure rate.** Before: 1 failure in the two check runs the owner reported (the four earlier runs that day passed); in this session the old assertions passed 30 of 30 alone, 30 of 30 beside the Inter-registering suites, and 8 of 8 whole-package runs, because the window is one test-start moment per process. After: the test registers Inter first (`OutputTestFonts.registerInter()`, which also checks that the output text path resolves Inter, and fails with a clear message when it cannot), so both renders use one face whatever other suites do. Passed 30 of 30 alone, 8 of 8 in the whole package, 3 of 3 in `check.sh`.

**Why 1,114 s.** Swift Testing formatted two 8 MB arrays into the failure message. `PixelDiff.describe(actual, expected, width:)` (new, `Tests/OutputEngineTests/OutputTestSupport.swift`) says in one line how many pixels differ, the bounding box and the first three value pairs; the test asserts `describe(...) == nil`, the same equality, nothing weakened.

**Is the running app exposed?** By reading the code, not by running it: no. Registration comes first in `AppModel.init` and at `applicationWillFinishLaunching`, and nothing in the app registers a font later. If registration fails, every render uses the system font consistently and the launch check (`OutputFont.check`) tells the operator. One limit I left alone (KI-171): the text caches are keyed by the font *name*, so a font registered after text was drawn is not picked up by a compositor that already cached it. Keying by the resolved face would add a Core Text lookup per layer per frame to the live path for a case the app cannot reach; not done.

No engine change, so there is no engine test that "fails without the fix"; the guard is the test's own registration plus the check that fails loudly when Inter is missing.

## 3. `VideoPlayerSourceTests.pauseHoldsAndSeekMovesTheFrame`

The original failure (62 s with no blue frame after a seek while paused) was **not reproduced**: 20 of 20 alone, 20 of 20 under 12 busy loops, 12 of 12 whole `MediaEngineTests` runs under load with two full package runs beside them, and 800 of 800 paused-seek cycles with 8 players at once under load (scratch stress test, removed). So I cannot say whether it was the test's patience or the player; a player stall after a paused seek is neither shown nor excluded (KI-034's watchdog only watches a player told to play). I did not add a speculative player change or raise a timeout.

Found and fixed instead (reproduced once, in the extreme-load run): the test ran its 2 s clip on the wall clock; when the first frame took about two seconds the clip was over before `pause()` (status `.ended`, lines 52 and 55). The test now passes the player a manual clock. And the failure message now carries `diagnostics`, the delivered-frame count, the frame's centre colour and the movie's size and duration, so the next 62 s wait says what the player and the file were doing.

## 4. A third flake, found in my own runs

Run 4 of 8 failed `MEDIA010_RegistryBackgroundAudioTests.unmutingTheBackgroundReachesTheOpenPlayer` with "The file couldn't be saved": the shared hardware H.264 encoder refused the fixture's `AVAssetWriter` while other suites wrote too. Fixture only. `TestMedia.writeMovie` now retries a refused write (three attempts, clean file each time). Under the extreme load (12 busy loops and two full runs at once) two MIDI router tests also timed out; not investigated (KI-173).

## Files

Changed: `Packages/WorshipFlowKit/Tests/OutputEngineTests/UI005h_SDIReadbackTests.swift`, `Tests/MediaEngineTests/VideoPlayerSourceTests.swift`, `Tests/MediaEngineTests/TestMedia.swift`. New: `Tests/OutputEngineTests/OutputTestSupport.swift`. Docs: `docs/16-known-issues.md` (KI-171 to KI-173), `docs/17-change-log.md`. No source (non-test) file changed.

## Verification

`./scripts/check.sh` three times in a row: run 1 exit 0 (107 s), run 2 exit 0 (73 s), run 3 exit 0 (72 s); each ran 2,878 package tests in 450 suites, all passed (about 67 s), domain boundary OK, project generation OK, Debug app build OK (`== OK`). Running `check.sh` regenerates `WORSHIPFLOW.xcodeproj/project.pbxproj`, which shows as modified in the tree.

Not verified: the player after a paused seek in the exact conditions of the 62 s failure; the app's launch order by running it; the MIDI router timeouts under heavy load; any hardware path.
