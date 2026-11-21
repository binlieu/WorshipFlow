# CUE-001 report: show-control rules

Levels: Implemented; Unit Tested. Not Simulated in the app, not Hardware Verified. See `docs/features/CUE-001-cue-engine.md` for behaviour and decisions.

## Files
Sources (`Packages/WorshipFlowKit/Sources/CueEngine`, `Placeholder.swift` deleted): `CueJSON.swift`, `CueAction.swift`, `Macro.swift`, `SlideActions.swift`, `CueExecutor.swift`, `Schedule.swift`, `PlaybackMarker.swift`, `MIDIMessage.swift`, `MIDIBinding.swift`.
Tests (`Tests/CueEngineTests`, `Placeholder.swift` deleted): `MIDIMessageTests.swift`, `MIDIBindingTests.swift`, `CueActionTests.swift`, `MacroTests.swift`, `SlideActionTests.swift`, `CueExecutorTests.swift`, `ScheduleTests.swift`, `PlaybackMarkerTests.swift`.
Docs: `docs/features/CUE-001-cue-engine.md`, this report. `Package.swift` untouched (it already had the CueEngine target and test target). Nothing else changed; no git commands that change state were run.

## Test-first (red recorded before each implementation)
Scratch package (Domain + CueEngine + CueEngineTests, no GRDB) at `scratchpad/wf-cue001-459627004`, synced from the repository by a script. Red output files in `scratchpad/`: `cue001-red1.txt` (MIDI: `cannot find type 'MIDIMessage' in scope`), `cue001-red2.txt` (`cannot find 'MacroLibrary'`, `MIDIPattern`, `MIDIBinding`, `CueAction` members), `cue001-red3.txt` (executor: `CueExecutor`/`CueClock`/`CueReport` missing), `cue001-red4.txt` (`cannot find type 'ScheduledEvent'`), `cue001-red5.txt` (`cannot find type 'PlaybackMarker'`). Each group went green after its implementation. Red was a compile failure in every case, because the API did not exist; a runtime-red for each rule was not recorded separately.
Failures found while going green were test mistakes, fixed against independently computed values: `#expect` cannot call a mutating method on a local (hoisted); a depth test read the wrong chain index; a week of daily events has 8 occurrences in my window, not 7; three simulation windows included one more local day than I had listed (Lord Howe 1 October 15:45 UTC, New York 10 March 06:30 UTC, 3 November 06:30 UTC).
Mutation check (scratch copy only, restored afterwards): grace `<` to `<=`, fall-back `min` to `max`, sysex not cancelling running status, note-off not releasing a pad, stop not cancelling pending stages. Each made the suite fail (2, 5, 4, 3, 2 issues).
Calendar expectations: every DST instant in `ScheduleTests` was computed with Python `zoneinfo` (not with the code under test); the Lord Howe and New York gap instants were also cross-checked with the system `date` tool.

## Commands and results
- Scratch: `swift build --build-tests` (red, five times, exit 1 as expected); `swift test`: `Test run with 191 tests in 25 suites passed after 6.397 seconds` (exit 0).
- Real package: `swift test --package-path Packages/WorshipFlowKit --filter CueEngineTests`: exit 0, `Test run with 191 tests in 25 suites passed after 7.003 seconds`. No warnings from CueEngine or its tests in the log (`scratchpad/cue001-real2.log`). The real package built with the other agent's files as they were at that moment.
- Not run: the full `swift test` of every target, `./scripts/check.sh`, the app build.

## Decisions
See the feature doc, "Decisions where the brief left room" (14 items).

## Brief problems
See the hand-off message (items 4).

## Not verified
- No real MIDI device, CoreMIDI or UMP stream; no real clock; no Mac sleep and wake; `CLOCK_MONOTONIC` behaviour during sleep.
- Time zone data on other macOS versions; zones other than New York, London, Lord Howe, Kolkata, Auckland, Pago Pago and UTC.
- Concurrency behaviour in the real app (the executor is `@MainActor` and was tested only from the main actor).
- The stored forms of `ScheduleEngine`, `ScheduledEvent`, `MIDIBindingSet` (default `Codable` shapes, no version).
- Slide-live detection against the app's real `WorkspaceModel`; the app does not call any of this yet.
- Performance with many events or markers (the minute-by-minute simulation tests take about 5 s each).
