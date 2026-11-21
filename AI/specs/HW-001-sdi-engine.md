# Brief: HW-001 and KEY-001 — SDI engine: abstraction, scheduler, connector planning, fill and key, simulator

Read first: `CLAUDE.md` (hardware and video-output rules, verification levels), `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md`, `AI/reports/research-2026-11-20-phase2-integrations.md`, `docs/MASTER-SPEC.md` section 4, and the coordinator test `Tests/SDIEngineTests/SDIEngineTests.swift`.

Catalogue: SCRN-11 (DeckLink SDI output), SCRN-10 (alpha-key output). **The highest level this slice can reach is "Simulated".** No vendor SDK is used or downloaded here.

## Goal

Make the coordinator test pass, in the new target `Sources/SDIEngine` (delete `Placeholder.swift`). Everything is plain Swift with Foundation and `Domain` only: no Metal, AppKit or AVFoundation in this target.

## What to build (API fixed by the tests)

- `SDIVideoMode` (`width`, `height`, `frameDurationValue`, `timeScale`, `framesPerSecond`, `name`; `hd1080p5994`, `hd1080p60`, `hd1080p50`, `hd1080p2997`, `hd1080p30`, `hd1080p25`, `hd1080i5994`, `hd720p5994`, `hd720p60`, `hd720p50`; `allKnown`). Nothing above HD.
- `SDIScheduler` (value type): `start()`, `frameCompleted(_:bufferedFrames:)`, `stop()`, `isRunning`, `statistics`, `health` (`.ok`, `.degraded`, `.failing` over a sliding window of the last 120 completions: three or more bad frames is degraded, thirty or more is failing), `Action` (`.schedule(frameIndex:)`, `.startPlayback(atFrame:)`), `SDICompletionResult` (`.completed`, `.displayedLate`, `.dropped`, `.flushed`).
- `SDIOutputRequest`, `SDIAssignment`, `SDIConnectorRole` (`.unused`, `.output(UUID)`, `.fill(UUID)`, `.key(UUID)`), `SDIPlanFault` with `operatorMessage`, `SDIConnectorPlan`, `SDIConnectorPlanner.plan(requests:connectorCount:supportsExternalKeying:)`. Connectors are numbered from 1; pairs are (1, 2) and (3, 4); fill on the first of a pair, key on the second; earlier requests win; nothing is ever moved to another connector on its own.
- `AlphaMode`, `FillKeySplitter.split(bgra:fillAlphaMode:)`.
- `SDIFrame`, `SDIKeying` (`.none`, `.external(fillAlphaMode:)`), `SDIFrameCompletion` (`frameIndex`, `result`), `SDIError` (at least `.deviceDisconnected`, plus cases for not enabled, unsupported mode, connector unavailable; `Equatable`, with operator-readable descriptions), `SDIDeviceInfo` (with `.simulatedDuo2`, `isSimulated`), protocols `SDIDevice` and `SDIOutputPort` that a real DeckLink bridge will implement later, and `SimulatedSDIDevice` with a manual clock (`advance(frames:)`), `lastDisplayed(onConnector:)`, `simulateUnplug()`, `simulateReplug()`, `isConnected`.
- An `SDIOutputSession` that ties a port, a scheduler and a frame source together: it asks a `@Sendable` frame provider for the frame at each index, schedules it, reacts to completions, exposes statistics and health, and stops cleanly on `deviceDisconnected` with a reported reason. If the provider has no new frame in time it repeats the last one and counts a repeat. Test it against the simulator: a 600-frame run with a steady clock ends with zero late and zero dropped; a run where the provider stalls for 10 frames repeats frames and recovers; an unplug mid-run stops the session with the reason and no crash.
- Thread safety: the simulator and session will be driven from an SDK-style callback thread in the real bridge; make them safe for that (document the locking; justified `@unchecked Sendable` only).

## Do not modify

Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`. Anything outside `Sources/SDIEngine` and new files in `Tests/SDIEngineTests`: another agent is working in the media engine, operator core and app.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps. Do not commit or change git state. Do not consult any advisor tool. Do not download anything.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter SDIEngineTests` passes; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step failed solely because of the other agent's unfinished work.
2. `AI/reports/HW-001-report.md` records files, decisions, commands run with exit status, any coordinator test you believe is wrong, and — explicitly — that nothing here is Hardware Verified and what a real bridge will need to implement.
