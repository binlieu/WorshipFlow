# FIX-C report: second-review fixes in the DeckLink bridge, SDI engine and SDI outputs

Findings: S8, S9, S10, S11, S12, S13, S16 (REVIEW-2-findings.md). Feature IDs: HW-001, HW-002, HW-003, OUT-002.

**Verification level of everything below: Implemented and Unit Tested, or Simulated. Nothing is Hardware Verified.** This Mac has no DeckLink card and no driver. The Objective-C++ bridge was exercised only through stand-ins for the SDK's objects (see "The test seam"); that proves the bridge calls the SDK in the order and with the arguments it intends and handles the HRESULTs it is given, and nothing about how the real SDK or a real card behaves.

Method: failing test first, recorded output, then the fix. "Before" outputs are from a scratch copy of the repository at HEAD plus the new tests (the shared tree's OutputEngine did not build for part of the session because of the other agent's unfinished files, so before/after runs were made in `wf-fixc-a3291d6d78a4` under the session scratchpad). After outputs are from the real tree.

## Results

- Full package suite in the real tree: **1788 tests in 272 suites passed** (baseline was 1641; +147 includes the other agent's new tests and mine). `./scripts/check.sh` did **not** exit 0 in the shared tree at the end: attempt 3 passed the package tests (1809) and failed the app build on `App/Sources/HardwareTestView.swift:232,241` ("switch must be exhaustive"); attempts 4 and 5 (1815 tests) failed only `UI002_PlaylistItemsTests.relaunchOnAHeaderLandsOnTheNextPlayableItem` (OperatorCoreTests), also the other agent's unfinished area. My targets alone: `swift test --filter "SDIEngineTests|DeckLinkSDITests|OutputEngineTests"` = 499 tests in 74 suites passed. See "Not verified".
- Two unrelated tests failed once under machine load (ScriptureStorePerformanceTests fetch timing; MediaAvailabilityTests) and passed on re-run.

## The test seam (new)

To test the bridge without a card: `Sources/DeckLinkC/DeckLinkBridgeFakes.mm` implements scripted `IDeckLinkInput`, `IDeckLinkOutput`, `IDeckLinkKeyer`, `IDeckLink` (with a profile manager and attributes), `IDeckLinkDisplayMode` and `IDeckLinkVideoConversion` exactly as declared in `sdk/`, recording every call. `include/DeckLinkBridgeTesting.h` exposes them to Swift (`DLBFakeInput`, `DLBFakeOutput`, `DLBFakeDevice`, `DLBTesting`). Nothing in the app uses this header. Production code gained only: `DLBConversionFactory` (a function pointer defaulting to `CreateVideoConversionInstance`), an atomic gauge of live input callbacks, and the `DLBTesting` factory section at the end of `DeckLinkBridge.mm`. `DeckLinkSDITests` now depends on `DeckLinkC` (one-token `Package.swift` change).

## S8: SDK stop/disable never from a callback thread. FIXED

- Before (`SDIEngineTests/FIXC_S8_CallbackThreadTests.swift`, fake port with a dedicated callback thread that records any teardown made while a handler runs):
  `aScheduleFailureInsideACompletionFinishesOffTheCallbackThread`: `port.violations → ["stopPlayback", "disable"]` (not empty); `aRemovalReportedFromTheCallbackThreadFinishesOffThatThread`: same.
- Fix (`SDIOutputSession`): a failure (`fail`) marks the session stopped at once, calls `onStop`, and does `port.stopPlayback()` and `port.disable()` on the session's own serial queue `WorshipFlow.sdi.session.teardown`. An owner's `stop()` still tears down inline, and always ends with `teardownQueue.sync {}` so a stop after a failure returns only once the hop finished (so `SDIOutput.finish` may close the port next). `stop()` must not be called from a port callback (documented).
- After: 4 tests pass, including an ordinary stop still being synchronous (`["stopPlayback", "disable"]`) and idempotent `stop()` after failure.
- Bridge side, by reading: no SDK stop, disable or close call is made inside any callback in `DeckLinkBridge.mm` (`ScheduledFrameCompleted`, `ScheduledPlaybackHasStopped`, `VideoInputFormatChanged` (dispatches), `DeckLinkDeviceRemoved`, `ProfileActivated` (now dispatches)). The Swift adapter's failure path (`DeckLinkOutputPort.fail`) only calls the session's handler, which now hops.
- Unverified: what the real SDK does when stop is called from its callback; the fix removes the possibility rather than testing it.

## S9: render ahead off the callback thread. FIXED (with one remaining item, below)

- New `Sources/OutputEngine/SDIRenderAhead.swift`: one render thread per output (`WorshipFlow.sdi.render`, user-interactive QoS) renders into a bounded circular queue (depth `max(3, preroll)`, no per-frame allocation: fixed slot array; frames are the renderer's own ring buffers). `next()` is what the completion path calls: it takes a finished frame under a short lock or answers nil at once, and the existing session logic repeats the last frame and counts the repeat. `SDIOutput.start` starts the thread and waits (bounded, 1 s, on the output's own start queue) for the preroll's worth of frames before the session prerolls, so the first frames are real, not black. `stop()` joins the thread with a 1 s bound; `finish` waits for a start still running on the queue first.
- Two pacings (`SDIRenderPacing`, new defaulted init parameter, source compatible): `.free` (real operation: render ahead, callback never waits) and `.lockstep` (the callback asks the render thread for exactly one frame and waits, so each completion shows the scene as it is now). Default: `.lockstep` only for a simulated card with no clock (the manual-clock tests); `.free` otherwise, including the real DeckLink (not simulated) and the app's simulated card (which has a clock). The 1788-test run shows every pre-existing SDI test passes unchanged, none weakened.
- Ring size: `max(preroll, maxBuffered) + 5 + depth`, each slot now its own allocation (the previous `Array(repeating:count:)` shared one buffer and copied on first write, which `bufferReallocations` counted as 9 in the new free-pacing run before this was changed).
- Before (the new tests against the HEAD behaviour, rendering in the callback): `theCallbackPathDoesNoRendering` failed in both pacings (`calledFrom(callbackThread) → true`; thread names not `WorshipFlow.sdi.render`); `aSlowRendererCausesRepeatsNotLateFrames`: `repeatedFrames → 0` (expected > 30: a slow renderer stalled the callback instead); `sixHundredFramesInFreePacing…`: `bufferReallocations → 9`.
- After: all pass: callback does no rendering (checked against the thread that calls `advance` and the main thread); slow renderer gives repeats, zero late, zero dropped, health ok; 600 frames zero late, zero dropped, zero reallocations, a real rendered frame on the connector; four outputs on four connectors each show their own colour, one render thread each; stop while mid-frame returns promptly, nothing renders after it (400 ms check), and a new output on the same connector starts; unplug ends the render thread; the queue is bounded (3 renders with nobody consuming, 4 after one is taken); an empty queue answers nil within 100 ms; a real-time `SimulatedClockDriver` run of 1.5 s shows at least 50 frames, zero late/dropped and repeats at most half.
- Statistics and health: unchanged (`FrameStatistics`, `SDIOutputReport`, `renderTiming`, `lastRenderError` read the same sources).
- **Four-output benchmark** (`HW002_SDIBenchmarkTests`, Debug, 4 outputs, 1080p59.94, 600 frames, per frame across all four outputs on the advancing thread; this machine was shared with other agents' builds, so runs vary):

  | | mean | p99 | worst | per output render+readback mean / worst | late / dropped |
  |---|---|---|---|---|---|
  | Before (baseline run in the real tree) | 8.793 ms | 18.853 ms | 28.161 ms | 2.169 / 11.408 ms | 0 / 0 |
  | Before (2 more runs, HEAD copy) | 9.285; 6.336 ms | 22.789; 8.032 ms | 36.366; 9.688 ms | 2.289 / 23.070; 1.572 / 2.545 ms | 0 / 0 |
  | After (lockstep, scratch, 3 runs) | 6.269; 5.559; 5.532 ms | 12.784; 7.230; 6.573 ms | 20.937; 8.635; 8.074 ms | 1.524 / 7.937; 1.371 / 2.425; 1.364 / 2.191 ms | 0 / 0 |
  | After (real tree, loaded machine) | 7.938 ms | 18.712 ms | 42.509 ms | 1.910 / 11.480 ms | 0 / 0 |

  Lockstep still waits for the render, so this number moves little by design; it shows no regression and zero late/dropped. The meaningful new figure is the free-pacing run (`FIXC_S9_FreePacingBenchmarkTests`, new): time the SDK callback thread spends per frame across all four outputs **0.024 ms mean, 0.041 ms p99, 0.083 ms worst** (scratch; 0.056 / 0.814 / 2.382 ms on the loaded real tree), against about 8.8 ms mean when rendering on that thread. Render threads: about 2.1 ms mean per frame. Late 0, dropped 0. The simulated clock there runs flat out, so thousands of repeats are expected and not a defect.
- **Not done / remaining for S9:** the callback path still copies the 8 MB frame into the SDK's frame buffer inside `DLBOutput scheduleBGRA` (and, for straight alpha, does the unpremultiply there). Moving that off the callback thread needs a bridge API that lets the render thread fill the SDK frame directly (or pre-pack); that is a separate change with the same Not Verified risk and was not attempted. Also unchanged: `SDIFrameRenderer.frame()` holds its lock across the GPU wait, so main-thread readouts (`renderTiming`, `lastError`) can wait up to one frame's render (as before this change, but now on a thread that is not the card's).

## S10: format-change restart checks every HRESULT. FIXED

- Fix (`RunFormatChange`, `ChooseCaptureFormat`, `TearDownInput`): the pixel format is chosen with `DoesSupportVideoMode` (BGRA directly for an RGB 4:4:4 signal when supported, else 8-bit YCbCr converted by the SDK's converter, else a clear failure; YCbCr with no converter is a clear failure). Then `PauseStreams`, `EnableVideoInput`, `FlushStreams`, `StartStreams` are each checked; the first failure tears the input down (running false, `StopStreams`, `DisableVideoInput`, `SetCallback(nullptr)`, converter released), reports through `failureHandler` with a message naming the step and the `0x…` result and the HRESULT in the NSError, and does not call the format handler. If the owner stopped the input meanwhile nothing is reported.
- Before (13 seam tests against the HEAD bridge): the four failing-step cases each had `reports.failureList → []` (no failure reported; the new mode was reported anyway); RGB with BGRA unsupported did not fall back; nothing-supported and no-converter produced no failure.
- After: all pass (success order `PauseStreams, EnableVideoInput(YUV), FlushStreams, StartStreams`; four failing steps; BGRA direct; BGRA→YUV fallback; nothing supported; no converter).
- Unverified: that a real card accepts BGRA input for an RGB signal and behaves as the manual's pause/enable/flush/start sequence describes.

## S11: SetLevel checked; preroll max(3, device minimum). FIXED

- Bridge: `keyer->SetLevel` result checked; on failure the keyer is disabled, the output disabled, `enableDisplayMode` returns NO with "The card would not set the keyer level (SDK result 0x…)" (keying not enabled). The device's `BMDDeckLinkMinimumPrerollFrames` (already read into `DLBDeviceInfo`) is now carried onto `DLBOutput.minimumPrerollFrames`, then `DeckLinkOutputPort.minimumPrerollFrames`, through `DeckLinkMapping.prerollFrames(deviceMinimum:)` (at least 3, at most 10), a new defaulted requirement `SDIOutputPort.minimumPrerollFrames` (default 0), and `SDIOutput`: preroll = `max(prerollFrames, port.minimumPrerollFrames)`, buffer cap raised to preroll + 2.
- Before: `aRefusedKeyerLevelFailsTheEnableAndLeavesNothingOn`: `thrown → nil` (enable succeeded although SetLevel failed); `theDevicesMinimumPrerollIsAvailableFromTheOutput`: `-1 == 5`; `aDeviceMinimumAboveThreeRaisesThePreroll`: preroll stayed 3 for minimum 5 and 7.
- After: pass. Also `anAbsurdMinimumIsCappedSoTheBufferStaysBounded`, and a small or unknown minimum keeps preroll 3.
- Unverified: the meaning of `BMDDeckLinkMinimumPrerollFrames` is taken from its name; the header carries only the identifier (line 636), no comment.

## S12: close() always removes the callback and breaks the cycle. FIXED

- Fix: `stop()` and `close()` both use `TearDownInput`, which always calls `SetCallback(nullptr)` when a callback is installed (not only when the input was running) and always resets the callback and converter references (the input state -> callback -> input state cycle). After a removal `running` is already false, which was the bug.
- Before: `closeAfterARemovalStillRemovesTheCallbackAndBreaksTheCycle`: `callbackInstalled → true`, `liveInputCallbackCount → 1` (baseline 0).
- After: pass, plus close of a running input, close twice, and close after a failed restart.

## S13: nothing enumerated inside the profile callback. FIXED

- Fix: `ProfileActivated` records the activation, wakes `activateProfile` waiters, and `dispatch_async`es the refresh (which enumerates profiles via `BuildInfo`) and then the owner's handler onto a new serial queue `com.worshipflow.decklink.profile`. The one attribute read on the passed profile (its id, needed by the waiter) stays.
- Before: `getProfilesCallsInsideCallback → 1`.
- After: 0 inside the callback, and the refresh still happens (the handler sees a larger `getProfilesCalls` count).

## S16: running output never stopped silently; fill/key not flipped by a momentary empty device. FIXED

- Coordinator: when a running output's planned destination differs and the plan offers a different destination (not a fault), the output is stopped and **faulted** with an operator-readable message (what it was, what the settings now say, "Restart this screen to use the new destination"); no automatic resume, because a restart could feed the wrong connector. Chosen over restarting by itself: the CLAUDE.md rule against silently redirecting a feed.
- Device: `DeckLinkDevice` holds the last known model name, per-pair profiles, sub-device count and `SDIDeviceInfo` while it has no members (or a pair has none), and `DeckLinkDeviceProvider` keeps a departed card object and reuses it when the same card returns, so the layout is not rebuilt as "unknown model, one connector, fill on the lower connector" in between. Members that are present always override what is held (a real profile change still shows).
- Before: `aChangedKeyRouteFaultsTheRunningOutputWithAReadableReason`: Issue "expected a fault" (the output was stopped with no fault); `FIXC_LayoutHoldTests`: layout `keyRoute(firstConnector: 1)?.fillConnector → nil` (was 2), `held.connectorCount` not 4, `keyRoutes → []`, returning card not the same object (7 issues).
- After: all pass; an unchanged plan touches nothing.
- Unverified: whether a real profile change really empties a card's member list or delivers sub-devices one at a time in the order assumed; the hold covers both shapes the code can see.

## Files

Created: `Sources/DeckLinkC/DeckLinkBridgeFakes.h`, `Sources/DeckLinkC/DeckLinkBridgeFakes.mm`, `Sources/DeckLinkC/include/DeckLinkBridgeTesting.h`, `Sources/OutputEngine/SDIRenderAhead.swift`, `Tests/SDIEngineTests/FIXC_S8_CallbackThreadTests.swift`, `Tests/OutputEngineTests/FIXC_S9_RenderAheadTests.swift`, `Tests/OutputEngineTests/FIXC_S11_PrerollTests.swift`, `Tests/OutputEngineTests/FIXC_S16_AssignmentChangeTests.swift`, `Tests/DeckLinkSDITests/FIXC_BridgeSeamTests.swift`, `Tests/DeckLinkSDITests/FIXC_PrerollTests.swift`, `Tests/DeckLinkSDITests/FIXC_LayoutHoldTests.swift`, this report.

Changed: `Sources/DeckLinkC/DeckLinkBridge.mm`, `Sources/DeckLinkC/include/DeckLinkBridge.h`, `Sources/DeckLinkSDI/{DeckLinkDevice,DeckLinkDeviceProvider,DeckLinkMapping,DeckLinkOutputPort}.swift`, `Sources/SDIEngine/{SDIDevice,SDIOutputSession}.swift`, `Sources/OutputEngine/{SDIOutput,OutputCoordinator}.swift`, `Package.swift` (test target dependency only). All API changes are additive (defaulted parameter `renderPacing`, protocol requirement with default `minimumPrerollFrames`, new types); `DeckLinkDeviceProvider.reconcile/arrived/removed` went from private to internal for tests.

## SDK calls added or changed, checked against `Sources/DeckLinkC/sdk/DeckLinkAPI.h`

These cannot be run here; each was matched to its declaration.

| Call | Where | Header |
|---|---|---|
| `IDeckLinkKeyer::SetLevel(uint8_t)` result now checked (was ignored) | `enableDisplayMode` | line 1687 |
| `IDeckLinkKeyer::Disable()` on that failure | same | line 1690 |
| `IDeckLinkOutput::DisableVideoOutput()` on that failure | same | `IDeckLinkOutput` block (existing call) |
| `IDeckLinkInput::DoesSupportVideoMode(connection, mode, pixelFormat, BMDVideoInputConversionMode, flags, &actual, &supported)` now also called per detected format | `ChooseCaptureFormat` | line 1183 |
| `IDeckLinkInput::PauseStreams / EnableVideoInput(mode, format, flags) / FlushStreams / StartStreams` results now checked | `RunFormatChange` | lines 1205, 1190, 1206, 1203 |
| `IDeckLinkInput::StopStreams / DisableVideoInput / SetCallback(nullptr)` now always run on tear-down (callback removal no longer depends on "running") | `TearDownInput` | lines 1204, 1192, 1207 |
| `IDeckLinkProfileCallback::ProfileActivated` now only records and dispatches; `IDeckLinkProfileManager::GetProfiles` runs later on a queue | `ProfileCallback`, `BuildInfo` | lines 1628, 1639 |
| `BMDDeckLinkMinimumPrerollFrames` (existing attribute read) now used | `BuildInfo` -> `DLBOutput` | line 636 |
| `bmdDetectedVideoInputRGB444` flag (existing) now decides the capture format | `VideoInputFormatChanged` | line 223 |
| `CreateVideoConversionInstance()` now called through `DLBConversionFactory` (same function) | `startWithInitialDisplayMode` | line 1743 |

## Not verified

- Every bridge behaviour above on real hardware, driver or SDK. The seam proves call order and HRESULT handling against my own stand-ins, which are only as right as my reading of the header.
- S8: that the SDK really blocks stop/disable inside its own callback (the fix removes the exposure regardless).
- S9 on a real card: DeckLink completion timing, the 8 MB copy still on the callback thread (see above), the two-to-three-frame latency render-ahead adds to a scene change (about 50 ms at 59.94; accepted by the coordinator decision), real GPU contention with four outputs.
- A full-length soak of render-ahead and unplug/replug cycles; only short runs (a few seconds) were done.
- `./scripts/check.sh` end to end: package tests pass in the real tree (1788); the app build step failed on the other agent's unfinished `HardwareTestView.swift` (non-exhaustive `switch` at lines 232 and 241), so exit 0 was not obtained from my last attempt. A retry is noted in the hand-off message.
- Docs (`docs/17-change-log.md`, `docs/14-current-status.md`, `docs/16-known-issues.md`, `docs/15-agent-handoff.md`) were not updated here: they are shared with the other agent and this brief asked only for this report. They need an entry for FIX-C and for the new test seam.
