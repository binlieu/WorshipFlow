# Brief: SYS-001 SQLite store

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/features/SYS-001-sqlite-store.md`, `AI/reports/research-2026-11-20-grdb-display-modes.md`, and the tests in `Packages/WorshipFlowKit/Tests/PersistenceTests/LibraryStoreTests.swift` and `Tests/DomainTests/SearchFoldingTests.swift`.

## Goal

Make those tests pass by adding domain record types, the `SearchFolding` rule and a GRDB-backed `LibraryStore`.

## Do not modify

- Test files marked "Owned by the coordinator". You may add new test files.
- `Package.swift` and `project.yml` (already updated with the `Persistence` target and GRDB 7.12).
- Anything under `Sources/RenderEngine`, `Sources/MediaEngine`, `Sources/OutputEngine`, `App/`. Another agent may be working there.
- In `Sources/Domain`, only add new files. Do not edit `Scene.swift` or `SlideContent.swift`.

## What to build

**`Domain`** (Foundation only, new files):
- `SearchFolding.fold(_:)`: decompose, strip combining marks, map đ and Đ to d, lowercase, turn every run of non-alphanumeric characters into one space, trim.
- `Library`, `Presentation` (with `PresentationKind`: `song`, `sermon`, `scripture`, `other`), `Slide` (holds a `SlideContent` and `notes`), `Playlist`, `PlaylistItem`, `SearchHit` (`presentationID`, `title`, `matchedTitle`). UUID ids, `sortOrder` where ordered, all `Sendable`, `Equatable`, `Codable`, `Identifiable`.

**`Persistence`**:
- `LibraryStore` (final, `Sendable`) with exactly the API the tests call: `inMemory()`, `open(at:)`, `open(at:migratingUpTo:)`, `close()`, `tableNames()`, `appliedMigrations()`, library, presentation, slide, playlist, search and app-state methods, and `importForTesting(libraryID:count:_:)` (bulk insert in one transaction; mark it clearly as a test and benchmark helper).
- `StoreError`: at least `.notFound` and `.invalidName`, `Equatable`.
- Follow ADR-0004 in full: `DatabasePool` for files (`DatabaseQueue` is acceptable for in-memory), `synchronous = NORMAL` set explicitly, foreign keys on, named migration `v1`, no `eraseDatabaseOnSchemaChange`, struct records, UUIDs stored as text, `createdAt` and `updatedAt` columns.
- Deletes cascade as the tests require, and reordering keeps `sortOrder` dense, all inside one transaction per operation.
- Search: keep folded title and folded slide text per presentation, updated in the same transaction as every change to titles and slides. Check at open whether FTS5 is available; use it if so (prefix matching on the last term, all terms required), otherwise `LIKE` on the folded columns. Title matches rank before lyric-only matches. Queries are folded with the same function and never interpolated into SQL.
- Record GRDB's record types as internal; the public API speaks `Domain` types only.

**Docs**: fill in `docs/19-data-dictionary.md` with every table and column of schema v1.

## Constraints

- Swift 6 language mode, strict concurrency, no `@unchecked Sendable` without a justification comment, no force unwraps.
- Do not commit.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit` passes, including the earlier 21 tests. Paste the summary line.
2. `./scripts/check.sh` exits 0.
3. `AI/reports/SYS-001-report.md` records files created, decisions, whether FTS5 was found in the system SQLite, the measured time of the 2,000-song search, commands run with exit status, and anything not verified.
