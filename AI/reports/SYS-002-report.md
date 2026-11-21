# SYS-002 report: settings and media references in SQLite (schema v3)

## Files
Created: `Packages/WorshipFlowKit/Sources/Domain/MediaAsset.swift`, `Sources/Persistence/LibraryStore+Settings.swift`, `Tests/SettingsStoreTests/SettingsStoreExtraTests.swift`.
Changed: `Sources/Domain/LibraryModels.swift` (`Presentation.themeID`, defaulted init parameter before `createdAt`), `Sources/Persistence/Schema.swift` (migration `v3`), `Sources/Persistence/Records.swift` (`PresentationRecord.themeID`), `docs/19-data-dictionary.md`.

## Decisions
- JSON columns via `SettingsJSON` (sorted keys, no escaped slashes, nil optionals omitted). Look screens are `{"<UUID>": {"themeID": ..., "visibleLayers": [sorted]}}` (a `Set` would encode in random order).
- Upserts use `ON CONFLICT DO UPDATE`, so editing keeps rowid and createdAt (creation order is stable).
- `PresentationRecord` reads `themeID` but its custom `encode(to:)` never writes it, so `createPresentation` still works on a store opened with `migratingUpTo: "v1"/"v2"`. `setTheme` is the only writer.
- `presentation.themeID` has no foreign key (built-in ids have no row); `deleteTheme` clears it in the same transaction.
- Built-in theme ids passed to `saveTheme`/`deleteTheme` throw `StoreError.invalidReference` (no new `StoreError` case, to avoid breaking exhaustive switches elsewhere). `setTheme` with an unknown id throws `invalidReference`.
- `addMediaAsset` re-reads the inserted row so the returned `addedAt` equals the stored (millisecond) value; `path` is UNIQUE.
- `saveScreenProfiles` rejects duplicate ids with `invalidReference`. Destination stored as `destination` text plus nullable `displayID`.
- Corrupt stored JSON makes the read throw rather than dropping rows.

## Commands
- `swift build --package-path Packages/WorshipFlowKit`: ok.
- Scratch copy outside the repo (other agent's test target removed): `swift test` 204 tests, 1 failure (see below).
- After the other agent's `OperatorCore` compiled, real tree `swift test`: `Test run with 234 tests in 34 suites failed ... with 1 issue`. The only failure is `SongStructureStoreTests.schemaV2AddsStructureTables`. `SettingsStoreTests` and my `SettingsStoreExtraTests` pass.
- `./scripts/check.sh`: exit 1, at the first step, for that one failure.
- The remaining check.sh steps run by hand: domain-boundary grep clean; `xcodegen generate` exit 0; `xcodebuild ... build` exit 0.

## Test I believe is wrong (coordinator-owned, not modified)
`Tests/PersistenceTests/SongStructureStoreTests.swift:23` asserts `appliedMigrations() == ["v1", "v2"]` on the latest schema. `SettingsStoreTests.schemaV3AddsSettingsTables` requires `["v1", "v2", "v3"]`. They contradict; the v2 test should be changed to `.prefix(2)` or `contains`. check.sh cannot exit 0 until the coordinator fixes it.

## Not verified
- App behaviour (the app does not yet call the new API). Concurrent-write behaviour of the new methods beyond what the tests cover. FTS-less (`LIKE`) backend with v3 was not specifically run. No Release build.
