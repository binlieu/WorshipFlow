# HW-001 / KEY-001 report: SDI engine

Verification level: **Simulated at most.** Nothing here is Hardware Verified. No vendor SDK was used or downloaded.

## Files
Sources (`Packages/WorshipFlowKit/Sources/SDIEngine`, `Placeholder.swift` deleted):
`SDIVideoMode.swift`, `SDIScheduler.swift`, `SDIConnectorPlanner.swift`, `FillKeySplitter.swift`, `SDIDevice.swift`, `SimulatedSDIDevice.swift`, `SDIOutputSession.swift`.
Tests (new): `Tests/SDIEngineTests/SDIOutputSessionTests.swift` (steady 600-frame run, provider stall, unplug, start failure, keyed session, black first frame).

## Decisions
- Scheduler buffer target is `min(prerollFrames, maxBufferedFrames)`; each completion schedules `target - buffered` frames. This is what the coordinator tests require (a refill to the cap of 5 would contradict `eachCompletionTopsTheBufferBackUp`). Settings are clamped to at least 1.
- Health window counts only late and dropped frames as bad; `.flushed` is not counted in the window and triggers no refill.
- Planner check order: duplicate screen, range, keying supported, first-of-pair, connector in use, paired connector in use. Two extra faults beyond the tests: `.noPairedConnector` and `.screenAlreadyAssigned`.
- `SDIOutputPort` is class-bound with `onFrameCompleted` and an extra `onFailure` callback (device removal), so a session learns of an unplug without needing a later completion. `SDIDevice` uses an associated `Port` type.
- Simulator: one lock in `SimulatedBackend` (`@unchecked Sendable`, the only unchecked type); callbacks are always invoked after the lock is released. A late frame is the newest stale scheduled frame, older stale frames report `.dropped`. Unplug invalidates all ports; ports from before stay dead (`.portClosed`) after replug.
- Session never holds its lock while calling the provider or port. If the provider returns nil it repeats the last frame (counted); before any frame exists it sends a zeroed frame of the mode size. The provider must not call back into the session.
- `SDIVideoMode.isInterlaced` added (1080i59.94 uses 1001/30000, frame rate 29.97).

## Commands
- Scratch package outside the repo (Domain + SDIEngine + SDIEngineTests): `swift test` -> exit 0, "Test run with 32 tests in 6 suites passed", no warnings in SDIEngine sources or tests.
- `swift build --package-path Packages/WorshipFlowKit --target SDIEngine` -> exit 0.
- `swift test --package-path Packages/WorshipFlowKit --filter SDIEngineTests` in the real package: failed to compile solely because of the other agent's unfinished audio files (`AudioOutputDevice` not found in MediaEngineTests/OperatorCoreTests). See the final status in the hand-off message for the retry result.

## Coordinator tests
None believed wrong; no inconsistencies found.

## What a real DeckLink bridge must implement
Conform to `SDIDevice` and `SDIOutputPort`: open/enable the connector with the mode's exact frame duration and timescale (59.94 vs 60), BGRA to the card's format with scheduled display times, completion callbacks mapped to `SDICompletionResult` (completed, displayed late, dropped, flushed), buffered-frame count from the SDK, external keying via a fill/key pair (including the alpha-mode choice and the real switcher's expectations), device arrival/removal notifications mapped to `onFailure`, genlock/reference handling, and real-time behaviour of the SDK callback thread. None of this is verified; all timing here comes from a manual clock.
