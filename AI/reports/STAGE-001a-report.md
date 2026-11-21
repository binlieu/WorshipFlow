# STAGE-001a report: stage layouts, timers, time formatting

## Files
Created (Domain): `Packages/WorshipFlowKit/Sources/Domain/ShowTimer.swift`, `TimeFormat.swift`, `StageLayout.swift` (StageElement, StageLayout, StageContext, StageComposer).
Created (Persistence): `Sources/Persistence/LibraryStore+Stage.swift`.
Changed: `Sources/Persistence/Schema.swift` (added `v4` only), `docs/19-data-dictionary.md` (v4 section).
New tests: `Tests/StageTests/StageParityTests.swift`, `Tests/StageStoreTests/StageStoreExtraTests.swift`.

## Decisions
- Timer stores `runningSince` + `accumulated`; `value(at:)` clamps a backwards clock to zero run time. `countdownTo` is always running; start/pause/reset do not move it (reset only clears stored run time).
- `TimeFormat.clock` rounds up (ceil) before formatting, so -0.2 shows `0:00` and 0.2 shows `0:01`; NaN is 0; values clamp to +-99:59:59.
- `StageElement` gained `verticalAlignment` (default `.top`) after `alignment`, so the standard layout reproduces the built-in scene; test initialisers still compile.
- `StageLayout.standard` uses `SceneStyles.standard` values; its next-slide element has `showsSecondLanguage = false` (built-in scene shows the next slide's primary line only). `StageParityTests` asserts the composed scene equals `SceneComposer.scene(for: .stage ...)` for live, cleared, stopped and several clock texts.
- Store: names trimmed via the existing `validName` (blank throws `invalidName`) for layouts and timers; built-in layout id throws `invalidReference` on save and delete; unknown ids throw `notFound`.
- `SceneComposer` and all existing public APIs untouched.

## Commands
- `swift build` (package): exit 0.
- `swift test --package-path Packages/WorshipFlowKit --filter 'StageTests|StageStoreTests'`: 28 tests, 6 suites, passed.
- Filtered run from the brief (`StageTests|StageStoreTests|PersistenceTests|SettingsStoreTests|DomainTests|CompositionTests`): 179 tests, 1 failure (below).
- Full `swift test --package-path Packages/WorshipFlowKit`: 267 tests in 41 suites, 1 failure (below).
- `./scripts/check.sh`: exit 1 at the package-test step because of that failure; later steps did not run.
- Domain boundary grep (the check.sh step, run by hand): no hits.

## Test believed stale (coordinator-owned, not modified)
`Tests/SettingsStoreTests/SettingsStoreTests.swift:24` (`schemaV3AddsSettingsTables`) asserts `appliedMigrations() == ["v1", "v2", "v3"]` exactly. Adding `v4`, which the STAGE test requires, necessarily breaks it. The StageStore test correctly uses `prefix(4)`. It should become `.prefix(3)` or be updated. Until it is, `./scripts/check.sh` cannot exit 0.

## Not verified
- `xcodegen generate` and the app `xcodebuild` steps of check.sh (not run; check.sh stopped earlier and I did not regenerate the project while another agent works in the tree).
- No interface or app integration; nothing exercised on hardware.
