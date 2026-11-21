# Brief: LIB-004b — translations in the church library, and the command-line importer

Read first: `CLAUDE.md` (licensing rule; data safety rules), `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/adr/0008-bible-translations.md`, `docs/16-known-issues.md` (KI-062 to KI-064), `AI/reports/LIB-004-report.md`, `docs/features/LIB-004-scripture-engine.md`, all of `Sources/ScriptureEngine`, `Sources/Persistence` (how `LibraryStore` and migrations work), `AI/reports/bible-db-books.tsv`.

Catalogue: PRES-09, PRES-10. Phase 4. No interface in this slice.

## Rules

- Test first for every decision: failing test, recorded output, then implement.
- **No Bible text enters the repository** beyond the tiny KJV fixtures already allowed. Anything the importer produces from a real source goes to a path the caller names; the `Bibles/` folder at the repository root is git-ignored for local runs. Do not run the importer against the owner's database in this slice except for the one read-only smoke test described below, whose output goes to your scratch directory and is deleted afterwards.
- The app must never contain a database client or a database password (ADR-0008 decision 7): all MySQL access is in the separate tool.

## What to build

1. **`ScriptureStore`** (new target; replace the placeholder): storage of translations in the church's library file.
   - It needs new tables. `LibraryStore` owns the migrator, and another agent is editing `Sources/Domain`, `Sources/OperatorCore` and `App/` right now but **not** `Sources/Persistence`: add migration `v7` in `Sources/Persistence/Schema.swift` (never edit earlier migrations) creating `scriptureTranslation` (id, code unique, name, language, abbreviation, copyright, licence, sourceDescription, isPublicDomain, ownerApprovalJSON, versificationID, versificationJSON for a non-built-in table, verseCount, importedAt) and `scriptureVerse` (translationID, bookOrder, chapter, verse, text; primary key on the four position columns; cascade on translation delete), plus an FTS5 index over folded verse text when FTS5 is available (same availability check and fallback pattern as the existing search index). Expose the minimum from `Persistence` that `ScriptureStore` needs to read and write those tables through the same `DatabasePool` (for example an internal-but-SPI accessor or a small public "run in a transaction" method) without opening a second connection to the file (ADR-0004 decision 2). Add a migration test that rows written at `v6` survive `v7`, using `prefix(n)` for the migration list.
   - API (async, `Sendable`): `translations()`, `importTranslation(_ file: TranslationFile, replaceExisting: Bool)` in one transaction with batched inserts (a full Bible is about 31,000 rows: it must import in a few seconds and report progress through a callback), `deleteTranslation(code:)`, `verses(in: [VerseRange], translationCode:)`, `search(_:translationCode:limit:)` using the same folding as `SearchFolding` so "duc chua troi" finds "Đức Chúa Trời", and `versification(for:)`. Re-importing the same code without `replaceExisting` fails with a clear error and changes nothing. A failed import leaves no partial translation.
   - A `ScriptureLibrary` façade that the app will use: parse a typed reference in a language context, fetch verses from a primary and optional second translation, and return slides through `ScriptureEngine`'s slide rules, reporting unpaired verses.
   - Performance tests on a synthetic full-size translation: import time, a reference fetch, a keyword search; record the numbers.
2. **`wf-bible-import`** (executable target `BibleImportTool`; replace the placeholder): a command-line tool.
   - `wf-bible-import inspect --mysql <options>` lists the versions in a database with the owner's schema (`versions`, `books`, `verses`: see `AI/reports/bible-db-books.tsv` and the LIB-004 report for the shape) with verse and book counts.
   - `wf-bible-import export --mysql <options> --version <code> --out <file.json> [metadata flags]` writes one translation in the LIB-004 file format, mapping the database's books by `book_order` to the canon, deriving the versification table from the data when it is not a built-in one, and validating (empty verses, duplicates, gaps reported). Metadata flags for name, language, abbreviation, copyright, licence, source, public-domain flag and owner approval; nothing is assumed: missing copyright and licence are written as "not stated".
   - `wf-bible-import import --library <Library.sqlite> --file <file.json|file.usfm|folder of .usfm>` loads a translation file into a church library through `ScriptureStore`; `--replace` to overwrite; refuses if the library is open by a running app unless `--force` (detect with a simple lock or by checking for the app's process; explain the risk).
   - MySQL access shells out to the `mysql` client binary (path from `--mysql-bin`, default found on `PATH`); the password is read from the environment variable `MYSQL_PWD` or prompted without echo, **never** accepted as a command-line argument and never written to any file or log; host, user and database are options. Always `--default-character-set=utf8mb4`. Read-only queries only. Put the query building and output parsing behind a protocol so tests use a fake runner with canned output (including Vietnamese text and tab or newline characters inside verse text — choose an output mode that survives them, such as `--batch --raw` with care, or hex or JSON output, and test it).
   - Exit codes: 0 success, non-zero with a one-line reason; `--help` for every subcommand.
3. **One read-only smoke test against the owner's database**, run by you once: `inspect` only (it prints version codes and counts; no verse text is written anywhere). The connection is host `localhost`, user `root`, database `bible`; ask the coordinator for nothing: the password is in the environment variable `WF_BIBLE_DB_PWD` if the coordinator has set it for your process, otherwise skip this step and say so. Paste the `inspect` table into the report.
4. **Docs**: `docs/features/LIB-004b-scripture-store-and-importer.md` (what it does, the commands with examples that never show a password, the licensing position from ADR-0008), and add the `v7` tables to `docs/19-data-dictionary.md`.

## Do not modify

Coordinator-owned tests. `Package.swift` (the targets are already declared; say what is needed if anything is missing), `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, earlier migrations. `Sources/Domain`, `Sources/OperatorCore`, `App/` and their tests: another agent is restructuring the interface there. `swift test` compiles every target; if a run fails solely because of that agent's unfinished files, build your own targets, run your tests in a uniquely named scratch copy of the package outside the repository (`wf-lib004b-<random>`), and retry the real run before finishing.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not download anything. Do not write Bible text anywhere inside the repository.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'ScriptureStoreTests|ScriptureEngineTests|PersistenceTests|SettingsStoreTests'` passes in the real package (or you state exactly why it could not and give the scratch result); `swift build --product wf-bible-import` succeeds. Paste the summary line.
2. `AI/reports/LIB-004b-report.md` records files, decisions, performance numbers, the `inspect` output or why it was skipped, commands run with exit status, and everything not verified.
