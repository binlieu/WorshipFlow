# LIB-004b report: translations in the church library, and `wf-bible-import`

Levels: Implemented; Unit Tested. Not Simulated in the app (nothing calls the store yet). The MySQL path is proven only against canned client output and a stand-in `mysql` script, never a real server. Behaviour: `docs/features/LIB-004b-scripture-store-and-importer.md`. Data dictionary: `docs/19-data-dictionary.md` ("Schema v7").

Brief changes honoured: step 3 (smoke test against the owner's database) was **skipped on instruction**; no MySQL server was contacted, the real `mysql` binary was never run, `WF_BIBLE_DB_PWD` was not used. Nothing was committed, staged or otherwise changed in git.

## Result

- Real package: `swift test --package-path Packages/WorshipFlowKit --filter 'ScriptureStoreTests|ScriptureEngineTests|PersistenceTests|SettingsStoreTests'` -> `✔ Test run with 311 tests in 36 suites passed after 4.261 seconds.` (log `scratchpad/lib004b-real-1.log`, exit 0; debug build).
- `swift build --package-path Packages/WorshipFlowKit --product wf-bible-import` -> `Build of product 'wf-bible-import' complete!` (debug, real package). A release build in the scratch copy also succeeded (60 s).
- Full `swift test` of every target in the real package: see the last section ("Full run").
- Scratch copy (outside the repository, symlinked to the real folders, GRDB by local path so nothing was downloaded): `scratchpad/wf-lib004b-2413510291`. It was used for red runs, mutation runs and the release binary.

## Files

Sources
- `Sources/Persistence/Schema.swift` (migration `v7` only; v1 to v6 untouched), `Sources/Persistence/LibraryStore.swift` (two lines: prepare the derived scripture index at open), new `Sources/Persistence/ScriptureTables.swift` (derived FTS5 index; the `@_spi(ScriptureStore)` accessors `scriptureRead`, `scriptureWrite`, `scriptureSearchUsesFTS5`).
- `Sources/ScriptureEngine`, source-compatible additions: `TranslationFile.swift` (`metadata.versificationTable`), `Translation.swift` (`TranslationLoader.decode`, a public `Translation.init` from rows, own-table support in `validate`, a `[0, 0]` chapter is not "missing"), `ScriptureSearch.swift` (public `ScriptureSearchHit.init`, `ScriptureSearchResult.init`, `ScriptureSearchIndex.queryTerms`), `Versification.swift` (`init(id:table:)`, `tableRepresentation`, `derived(id:from:)`).
- `Sources/ScriptureStore`: `ScriptureStore.swift`, `ScriptureStore+Import.swift`, `ScriptureStore+Read.swift`, `ScriptureLibrary.swift` (`Placeholder.swift` deleted).
- `Sources/BibleImportTool`: `main.swift` (3 lines) and `Core/`: `Arguments`, `MySQLRunner`, `MySQLBibleSource`, `TranslationExporter`, `TranslationFileSource`, `LibraryGuard`, `Environment`, `ImportToolCLI`, `Help`.

Tests (`Tests/ScriptureStoreTests`, `Placeholder.swift` deleted): `ScriptureStoreTests`, `ScriptureStoreSearchTests`, `ScriptureLibraryTests`, `ScriptureStorePerformanceTests`, `StoreFixtures`, and for the tool `ToolArgumentTests`, `ToolMySQLSourceTests`, `ToolProcessRunnerTests`, `ToolExporterTests`, `ToolCLITests`, `ToolLibraryGuardTests`, `ToolFakes`, plus the symlink `ToolCore -> ../../Sources/BibleImportTool/Core` (see decisions). New files only in `Tests/PersistenceTests/ScriptureSchemaTests.swift` and `Tests/ScriptureEngineTests/VersificationTableTests.swift`; no existing test file was modified.

Docs: `docs/features/LIB-004b-scripture-store-and-importer.md`, `docs/19-data-dictionary.md` (appended), this report.

Not mine: `Sources/Persistence/LibraryStore+Overview.swift` appeared untracked during the work; I did not create or touch it (another agent, presumably). `Package.swift`, `project.yml`, `Sources/Domain`, `Sources/OperatorCore`, `App/` were not touched.

## Test-first

Red outputs (every one a compile failure because the API did not exist; same kind of red as LIB-004): `scratchpad/lib004b-red-1.txt` (`value of type 'LibraryStore' has no member 'scriptureRead'`, `'TranslationMetadata' has no member 'versificationTable'`, ...), `lib004b-red-2.txt` (`cannot find type 'ScriptureStore' in scope`), `lib004b-red-3.txt` (`cannot find 'ImportToolCLI' in scope`).

Honest account: for the importer **I drafted the code before its tests** (an order slip). To keep the red real I moved `Core/` aside, wrote all tool tests, recorded the failing build, restored `Core/`, then fixed the tests' own mistakes by reasoning. Persistence, engine additions and the store were done in the proper order. No coordinator tests exist for this slice, so the API is mine.

Mutation checks (real source edited, tests run, source restored; log `scratchpad/lib004b-mutation.txt`): 16 mutants. Killed: replace keeping old verses; duplicate import allowed; truncation not detected; range end exclusive; no cascade; code unique case-sensitively; password redaction removed; password appended to the client's arguments; `--default-character-set=utf8mb4` dropped; in-use check skipped; text fetched without HEX; foreign SQLite file accepted; output overwrite unguarded; read-only keyword guard removed; FTS index not rebuilt at open. One neutral mutant survived by design. Two first showed "survived" and exposed (a) a missing assertion on the HEX statement text (added) and (b) an equivalent mutant (`return` followed by a statement on the next line returns that statement; redone with `return;`).

## Tests that prove the data-safety points

- One pool per file: `ScriptureStore` has no API that takes a path, it only receives a `LibraryStore`; a file-backed test imports a full translation while the same `LibraryStore` writes a song concurrently, closes, reopens, and finds both.
- One transaction, nothing left behind: a hook throws after N verses mid-import on both the FTS5 and `LIKE` backends: zero translation rows, zero verse rows, zero FTS rows. A failed **replace** keeps the old translation whole (text, search, count).
- Without `replaceExisting`, re-import (also with a different letter case) fails with `alreadyExists` and nothing changes (id, importedAt, text compared).
- Migrations: rows written at `v6` (open `migratingUpTo: "v6"`, with `prefix(7)` list check) survive `v7`; v1 to v6 untouched.
- Library "in use": refused with exit 3, file bytes unchanged; `--force` overrides; a real `lsof` test with a real child process holding the file open; a SQLite file with other tables, a text file and a missing file are refused or reported and never written to.
- No Bible text in the repository: the only scripture is the eleven KJV fixture verses (copied into `StoreFixtures.swift`); everything else is synthetic filler (Vietnamese-looking lines are not scripture); full-size translations are built in memory or in a temporary folder that tests delete. The e2e run used `scratchpad/wf-lib004b-e2e-*` (synthetic, deleted).

## MySQL seam: what the fake runner proves

`FakeMySQLServer` answers like the `mysql` client in `--batch --skip-column-names` mode for the exact statements the tool builds; `ProcessMySQLRunner` is tested separately against a stand-in `mysql` shell script. Covered:
- Vietnamese text with stacked diacritics (decomposed `e` + U+0302 + U+0323, `o` + U+0302 + U+0301, `a` + U+0309, `u` + U+031B + U+0301) kept scalar for scalar (no normalisation), through the fake, the file encoder/decoder and the exporter.
- Verse text with tab, newline, CRLF, backslashes, quotes, backticks, semicolon, `NULL`, `0x41` and a NUL byte survives byte for byte (hex output mode).
- Empty result (no versions; version with no rows; rows all skipped) -> exit 1 and no file written; NULL vs empty text kept distinct.
- Version code that does not exist -> `the database has no version with the code “NOPE”. Versions found: VI1934, EN, EMPTY.`; matching ignores case only when the exact code is absent.
- Client exits non-zero with `ERROR 1045 ... Access denied ... (using password: YES)` -> one line `wf-bible-import: the mysql client exited with status 1: ERROR 1045 ...`; the message contains neither the password (also when the "server" echoes it: replaced by `[hidden]`), nor the command line, the `--execute` SQL, host options or the client's path. Standard error of the client beyond its first error line is dropped.
- Missing `mysql` binary: absolute path missing, bare name not on `PATH`, file not executable -> `the mysql client was not found (...). Install it, or give its location with --mysql-bin.` exit 1.
- The password travels only as the child's `MYSQL_PWD` (the stand-in script records its argv and environment: password absent from argv, present in the environment; an inherited `MYSQL_PWD` is not passed on when no password is set); `--password`, `--pass`, `--pwd`, `-p`, `-psecret` and friends are refused with exit 2 and the value is never echoed.
- Only `SELECT`/`SHOW`, one statement (the check also refuses `DROP`, `INSERT`, `UPDATE`, `INTO OUTFILE`, a second statement) before the client starts; the session is also set read only by `--init-command`.
- Identifiers are quoted and restricted to letters, digits, `_`, `$`; a hostile column name is refused; version keys are sent as numbers or `_utf8mb4 0x..` hex, never as quoted text.
- Unreadable client output (warning line on standard output, odd-length hex, non-hex, invalid UTF-8, non-numeric number) is an error, not a guess.
- Large output on both streams (6 MB + 1 MB) does not deadlock; a hung client is stopped after the timeout.

## Performance (synthetic full-size translation: 31,102 verses, filler text)

Debug build, `swift test`, file-backed library, FTS5, Apple Silicon (several runs, `lib004b-real-1.log` and scratch):

| Operation | Time |
|---|---|
| Import 31,102 verses (validate, fold, one transaction, FTS index) | 1.57 to 1.77 s |
| Replace the same translation | 1.38 to 1.41 s |
| Fetch Psalm 119 (176 verses) | 1.9 to 2.8 ms |
| `ScriptureLibrary.lookup("Psalm 119:1-176")` to 176 slides | 2.6 to 3.2 ms |
| Keyword search `light water`, limit 50 (truncated) | 5 to 6 ms |
| Search with no match | 0.4 to 0.5 ms |
| Phrase `"fill the line"` matching every verse, limit 50 | 83 to 86 ms |
| Export of 31,102 rows through the fake server (parse, validate, write) | 2.1 s |

Release binary, end to end, synthetic Vietnamese-looking file of 4.1 MB (tabs and backslashes in the text): `import --create` 1.0 s reported (1.1 s wall including process start and migrations); `--replace` 1.2 s (1.5 s wall); `export` through the stand-in client process (7.8 MB of hex rows) 0.52 s wall; exported file equals the source file. The library file is 18.6 MB for one translation (verse text, folded text, FTS index). Release-build unit tests were not run (tests need a debug build).

## `inspect` output

Skipped (no connection made, by instruction). The stand-in-client run printed (synthetic data, not the owner's):
```
Database bible: 1 version
CODE  NAME             BOOKS  CHAPTERS  VERSES
SYN   Synthetic e2e ệ     66      1189   31102
```

## Commands run, with exit status

Scratch: `swift build` (0); `swift build --build-tests` red x3 (1 each: see red files) then green; `swift test --filter 'ScriptureStoreTests|ScriptureEngineTests|PersistenceTests|SettingsStoreTests'` (0, 310 then 311 tests); mutation script (0); `swift build -c release --product wf-bible-import` (0). Release binary: `--help` family (0), `nonsense` (2), `inspect --password x` (2), `inspect --mysql-bin /nonexistent/mysql` (1), `import ... --create` (0), repeat import (3), `--replace` (0), `inspect`/`export` through the stand-in client (0). Real package: the filtered `swift test` (0), `swift build --product wf-bible-import` (0), full `swift test` (below).

## Decisions where the brief left room

1. **Extra columns.** `scriptureVerse.textFolded` (source of truth for search, so the FTS rebuild and the `LIKE` fallback are pure SQL; costs about 3x file size) and `scriptureTranslation.versificationNote` (so a file's note is not lost). The FTS5 table `scriptureSearch` is derived data created in `prepare` at open (same availability check and fallback as `presentationSearch`), rebuilt if missing, dropped when FTS5 is absent, read only through a join to `scriptureVerse`.
2. **Accessor.** `@_spi(ScriptureStore)` `scriptureRead` / `scriptureWrite` (one GRDB transaction) / `scriptureSearchUsesFTS5` on `LibraryStore`; `ScriptureStore` imports it with `@_spi(ScriptureStore) import Persistence`. No second connection is possible from it.
3. **Importer code lives in `Sources/BibleImportTool/Core`**, not in `ScriptureStore`, so no MySQL code is linked into the app (ADR-0008 decision 7). `Package.swift` has no test target for the tool and I may not edit it, so `Tests/ScriptureStoreTests/ToolCore` is a symlink to that folder: the same files compile into the test module. **Wanted from the coordinator** if you prefer it cleaner: `.testTarget(name: "BibleImportToolTests", dependencies: ["BibleImportTool", "ScriptureStore", "ScriptureEngine", "Persistence"])` and move the `Tool*Tests` there (the tool is an `executableTarget`; `@testable import BibleImportTool` works for those since main.swift is three lines).
4. **A file can carry its own verse-count table** (`metadata.versificationTable`), because "derive the versification from the data when it is not a built-in one" needs somewhere to go. Stored in `versificationJSON` for a translation whose table is not exactly a built-in one. Malformed tables are reported and the named table is used.
5. **The exporter chooses KJV, VI1925, or a derived table**: a built-in table only if every chapter present ends at the table's highest verse; else derived (`--versification KJV|VI1925|derived` forces it). A KJV-numbered Bible missing the last verse of one chapter therefore gets a derived table (reported); use `--versification KJV` to force.
6. **Column names of the owner's database were not available**, so `MySQLBibleSource` finds them in `information_schema` from lists of likely names and `--map table.role=column` names any of them by hand; `inspect --schema` prints the choice. A numeric `verses` version column is read as `versions.id`, a text one as `versions.code`.
7. **Output mode: hex**, not `--raw`/`--batch` escaping: a hex string cannot contain the client's separators or escapes, and `CONVERT(... USING utf8mb4)` fixes the byte encoding whatever the column's character set.
8. **Text is never normalised** (stacked diacritics stay as stored), only trimmed by the loader at import (existing LIB-004 behaviour).
9. **Metadata is never assumed**: `--language` is required (the database does not say); copyright and licence default to "not stated"; public domain and owner approval only by flag; name and abbreviation default to the database's name and code; `id` (the code in the library) defaults to the version code, `--id` sets it.
10. **"Looks in use"** = another process (not this one) has the file or its `-wal`/`-shm` open per `lsof`; if `lsof` is unavailable, a non-empty `-wal`. An empty `-wal` and a `-shm` do not count: SQLite on macOS leaves them after a clean close (found in the e2e run and fixed). The tool also refuses a file that is not a WorshipFlow library, requires the library to exist unless `--create`, and offers `--dry-run`. It does not make a backup; the docs tell the church to copy the file first.
11. **Exit codes**: 0 done, 1 failed, 2 usage, 3 refused (library in use, not a library, translation exists, output file exists).
12. Code is unique ignoring case (`code TEXT UNIQUE COLLATE NOCASE`); replace keeps the translation id; progress is reported per batch of 500 verses (multi-row inserts), first 0 and last the total.
13. `ScriptureLibrary.lookup` reads only the verses of the parsed ranges and builds a sparse `Translation`, so a one-verse lookup does not load a Bible; `notes` lists chapters in the ranges whose verse counts differ between the two translations' tables.
14. `search` returns `ScriptureSearchResult` (hits plus `truncated`), the same type as the in-memory index, and is tested for equal answers (including snippets) on both backends.
15. Mojibake heuristic in the exporter: a letter U+00C2 to U+00F4 followed by U+0080 to U+00BF (UTF-8 read as Latin-1) is flagged as a warning, since the owner's database character set is unknown.

## Not verified

- **Anything against a real MySQL server or the real `mysql` client**: the owner's actual column names (detection may need `--map`), the exact `information_schema` output the real client prints, that the server accepts `--init-command=SET SESSION TRANSACTION READ ONLY` (MySQL 5.6.5+/MariaDB 10+; an older server would fail with a client error), `HEX(CONVERT(col USING utf8mb4))` on the owner's real column character sets (double-encoded text would export as mojibake; the exporter only warns), real client error wording, runtime and memory for a real 31,000-row export (the stand-in handled 7.8 MB in half a second).
- The interactive password prompt (`readpassphrase`) is not exercised by any test; only the decision to prompt is.
- `lsof` detection was tested with a stand-in process, not with the running app; I did not check whether the app keeps the library open idle (it should: one pool for the life of the store). Behaviour with the app sandboxed or under another user is unknown.
- No real USFM file was opened (none downloaded); USFM import is tested on hand-written synthetic files only.
- The Xcode project and app were not built; `ScriptureStore` is not linked by the app yet. No UI.
- Tests run in debug only; release timings are from the CLI end to end, not the test suite.
- FTS5 phrase-with-prefix syntax and `LIKE` fallback were tested on this Mac's SQLite (3.54); other SQLite versions untested.
- Behaviour with two processes writing the same library at once (`--force`) is not tested.
- Disk full or a power cut during an import: the transaction guarantees rely on SQLite; not simulated.
- A very large `--file` (hundreds of MB) is read fully into memory.

## Full run

See the closing lines appended below by the last command of this session.

Full `swift test --package-path Packages/WorshipFlowKit` (every target, real package, debug): `✔ Test run with 1552 tests in 229 suites passed after 39.671 seconds.` exit 0 (log `scratchpad/lib004b-real-full.log`; 1381 before, so 171 new). After it, one comment in `TranslationFile.swift` was edited and the filtered run above was repeated: still 311 tests passing. The e2e scratch folder (synthetic Bible-shaped data) was deleted; `wf-lib004b-2413510291` (scratch package, no Bible text) and the logs remain in the scratchpad.
