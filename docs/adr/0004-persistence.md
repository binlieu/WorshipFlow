# ADR-0004: Local persistence

Status: Accepted, 2026-11-20. Based on research recorded in `AI/reports/research-2026-11-20-grdb-display-modes.md`.

## Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | GRDB.swift 7.12 or later, product `GRDB`, using the system SQLite. | Builds in Swift 6 mode; no custom SQLite build to maintain. |
| 2 | One `DatabasePool` per library file, opened once for the life of the app. | WAL lets previews and search read while an edit is being written. Two connections to one file are unsafe. |
| 3 | `synchronous = NORMAL`, set explicitly. | A forced quit leaves the OS running, so committed edits survive. A power cut can lose the last commits but does not corrupt the file. |
| 4 | Every edit is committed within two seconds (debounced), and immediately when the app resigns active or quits. | Meets NFR-07 (lose at most five seconds). |
| 5 | Records are `Sendable` structs. View state lives in separate observable classes. | Strict-concurrency safety. |
| 6 | Named migrations on a `DatabaseMigrator`, never edited after release. `eraseDatabaseOnSchemaChange` is not used anywhere, including debug builds. | It destroys user data when a migration changes. |
| 7 | Migration tests build a database at version N with `migrate(upTo:)`, insert rows, migrate to the latest, and assert rows and schema. | Test-first rule for migrations. |
| 8 | Search uses a folded text column: Unicode-normalise, lowercase, strip combining marks, and map đ and Đ to d. The same function folds the query. | SQLite's own diacritic removal leaves đ unchanged, so "dien" would not find "điển". |
| 9 | The folded text is indexed with FTS5 when the system SQLite provides it, checked once at start-up; otherwise search falls back to `LIKE` on the folded column. | FTS5 presence in the system library was not confirmed by research. |
| 10 | Primary keys are UUID strings. Rows carry `createdAt` and `updatedAt`. | Stable identity for later export, sync and linking. |
| 11 | The library lives in `~/Library/Application Support/WORSHIPFLOW/` by default. Media stays where the user keeps it and is referenced by security-scoped bookmark. | A removable drive unplugged mid-write is the main corruption risk; keep the database off it unless the user chooses otherwise. |
| 12 | The folding function lives in `Domain`. | It is a pure rule with no SQLite dependency, and search results must match across modules. |

## Not decided here

Project export and backup format (`LIB`), and screen and Look configuration tables (`OUT-002`).
