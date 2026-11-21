# SYS-001 report: SQLite store

## Files created
- `Packages/WorshipFlowKit/Sources/Domain/SearchFolding.swift`, `LibraryModels.swift`
- `Packages/WorshipFlowKit/Sources/Persistence/`: `LibraryStore.swift`, `LibraryStore+Content.swift`, `LibraryStore+Playlists.swift`, `SearchIndex.swift` (also holds `search`), `Records.swift`, `Schema.swift`, `StoreError.swift`
- `Packages/WorshipFlowKit/Tests/PersistenceTests/SearchBackendTests.swift` (runs search on both FTS5 and LIKE paths; prints backend and timing)
- Edited: `docs/19-data-dictionary.md`

## Decisions
- ADR-0004 followed: DatabasePool for files, DatabaseQueue in memory, `synchronous = NORMAL` in `prepareDatabase`, foreign keys on, named migration `v1`, no erase-on-change, struct records, UUIDs as upper-case text (`databaseUUIDEncodingStrategy(for:)`; raw SQL binds `uuidString`), `createdAt`/`updatedAt`.
- Folded `titleFolded` and `bodyFolded` columns on `presentation` are the source of truth, rewritten in the same transaction as each title or slide change. Speaker notes are not searched.
- FTS5 table `presentationSearch` is derived, created at open (not in the migration), rebuilt if missing, dropped if FTS5 is absent. Probe: creating a temp FTS5 table at open.
- `matchedTitle` means every query term is in the title. Ranking: title matches first, then bm25 (FTS5) or folded title (LIKE).
- Presentations are listed by folded title (no sortOrder); libraries and slides and playlist items carry dense sortOrder; playlists are listed by createdAt.
- Extra public API beyond the tests: `renamePresentation`, `renamePlaylist`, `deletePlaylist`, `removePlaylistItem` (needed for complete title reindexing and basic playlist editing). `StoreError` also has `.unknownMigration(String)`.

## Search backend
FTS5 was available in the system SQLite; the FTS5 path is used. The LIKE path is implemented and tested via an internal forcing initializer. 2,000-song search ("chorus 1234"): about 0.0009 to 0.001 s on FTS5 (limit 200 ms). The LIKE path was not timed.

## Commands run
- `swift test --package-path Packages/WorshipFlowKit`: "Test run with 81 tests in 16 suites passed after 0.935 seconds" (includes the other agent's tests, which compiled by then).
- `./scripts/check.sh`: exit 0.
- Earlier, while another slice's DomainTests did not compile, I ran my tests in a scratch copy of the package (Domain + Persistence + my two test dirs): 31 tests passed.

## Not verified / deviations
- Observation streams (feature spec behaviour 3) are not implemented; the brief asked for exactly the tested API.
- Slide groups, arrangements, themes, media assets from the feature spec are not in v1 (brief lists six tables).
- The 2-second debounced commit and resign-active commit (ADR decision 4) are app-layer, not implemented here.
- Crash survival is tested only by dropping the store without `close()`, not by killing a process or cutting power.
- Search on very large libraries, non-Latin scripts (combining marks are stripped for all scripts), and a file created with FTS5 then opened without it were not tested.
- Persistence tests are run in debug builds only.
