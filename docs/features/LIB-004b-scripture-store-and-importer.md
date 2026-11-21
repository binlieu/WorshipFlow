# LIB-004b: translations in the church library, and the importer

Catalogue: PRES-09, PRES-10. Phase 4. Builds on LIB-004 (rules). Decisions: ADR-0008. No interface in this slice.

Verification level: Implemented; Unit Tested. Not Simulated in the app (nothing calls the store yet). The MySQL path is tested only against canned client output and a stand-in `mysql` script; it has not been run against a real server (see the report).

## What it does

1. **`ScriptureStore`** (`Sources/ScriptureStore`) keeps translations in the church's library file, through the `LibraryStore` it is given (one connection pool per file, never a second connection). It needs schema `v7` (`docs/19-data-dictionary.md`).
   - `translations()`, `translation(code:)`, `deleteTranslation(code:)`.
   - `importTranslation(_ file: TranslationFile, replaceExisting:, progress:)`: validates with `TranslationLoader` (so the report is the same as everywhere), prepares every row first, then writes in **one transaction** with multi-row inserts. Re-importing a code without `replaceExisting` fails with `alreadyExists` and changes nothing; a failure at any point rolls back to exactly the previous state (a failed replace keeps the old translation whole). Codes are unique ignoring case. Replacing keeps the translation's id.
   - `verses(in: [VerseRange], translationCode:)`: by position, so it needs no verse-count table; only existing verses come back.
   - `search(_:translationCode:limit:)`: the rules of `ScriptureSearchIndex` (all words required, each a word prefix, quoted phrases, case, diacritics, đ and punctuation ignored) on FTS5, or on `LIKE` where FTS5 is missing. "duc chua troi" finds "Đức Chúa Trời". Results in canon order; `truncated` says there were more.
   - `versification(for:)`: the built-in table the translation names, or the table stored with it.
2. **`ScriptureLibrary`** is the façade the app will use: `lookup("John 3:16-18; Ps 23", primary:, secondary:, uiLanguage:, context:, options:)` parses the reference in a language context, reads only the needed verses from the primary and optional second translation, builds slides with `VerseSlides`, and returns the parse problems, the slides with their report (verses missing in either translation), and `notes` where the two translations number a chapter differently (ADR-0008 decision 5).
3. **`wf-bible-import`** (`Sources/BibleImportTool`) is the command-line tool.

### Changes to LIB-004 (all source compatible)

A translation file may carry its own verse-count table (`metadata.versificationTable`: book code to one `[count, highest]` per chapter), used instead of the built-in table the name points to; `TranslationLoader.decode(from:)`; `Translation(metadata:versification:verses:)` from rows; public `ScriptureSearchHit.init`, `ScriptureSearchResult.init`, `ScriptureSearchIndex.queryTerms`; `Versification.init(id:table:)`, `.tableRepresentation`, `.derived(id:from:)`. A chapter with `[0, 0]` is not reported missing.

## The tool

```
wf-bible-import inspect --mysql --host localhost --user root --database bible
wf-bible-import export  --mysql --host localhost --user root --database bible \
    --version VI1934 --id VI1925 --language vi --public-domain --out ~/Bibles/VI1925.json
wf-bible-import import  --library ~/Library/Application\ Support/WorshipFlow/Library.sqlite --file ~/Bibles/VI1925.json
wf-bible-import import  --library ./Library.sqlite --file ./web-usfm --id web --language en --name "World English Bible"
```

Each command has `--help`. Exit status: 0 done; 1 the work failed (one line on standard error says why); 2 the command line is wrong; 3 refused to touch the library or the output file.

### MySQL

- It shells out to the `mysql` client (`--mysql-bin`, default `mysql` on `PATH`) with `--default-character-set=utf8mb4`, `--batch`, `--skip-column-names` and `--init-command=SET SESSION TRANSACTION READ ONLY`. Only `SELECT` and `SHOW` statements are ever sent; anything else is refused before the client starts. The app contains no database client and no password (ADR-0008 decision 7): this code is in the tool's target, not in `ScriptureStore`.
- **Password.** Never an argument: `--password`, `-p` and similar are refused. It is read from `MYSQL_PWD` or typed at a prompt (no echo; only when a person is at the terminal; `--no-password` skips it), and passed to the client only through the client's environment. Error messages show the client's first error line with the password removed, never the command line.
- **Output mode.** Every text value is fetched as `HEX(CONVERT(col USING utf8mb4))`, so tabs, newlines, backslashes, quotes and NUL inside verse text, and the connection's character handling, cannot change a byte. Text is written exactly as the database holds it (no Unicode normalisation).
- **Schema.** The owner's column names are not recorded anywhere in the repository, so the tool finds them in `information_schema` from lists of likely names (`inspect --schema` shows what it chose) and every role can be set with `--map verses.text=<column>`. A numeric version column in `verses` is read as `versions.id`, a text one as `versions.code`.
- **`inspect`** lists each version with books, chapters and verses. **`export`** maps `book_order` 1 to 66 to the canon, skips and counts empty, NULL and out-of-range rows, keeps the first of a duplicated verse (and says loudly when the second text differs), reports gaps without filling them, warns about text that looks stored in the wrong character set, cross-checks the `books` table's English names against the canon, and chooses the verse-count table: the built-in KJV or VI1925 when every chapter ends where it does, otherwise a table derived from the data and stored in the file. Metadata is never assumed: copyright and licence are "not stated" unless given; the version is public domain only with `--public-domain`; owner approval only with `--owner-approved`. The output file is written atomically and an existing file is not replaced without `--overwrite`.

### Import

- `--file` is a `.json` translation file, one `.usfm` file or a folder of `.usfm` files (then `--id` and `--language` are required; files whose `\id` is not one of the 66 books are skipped and listed).
- The library must already exist (`--create` makes it), must be a WorshipFlow library (a SQLite file with other tables, or not SQLite, is refused without being opened for writing), and must not be open in another program: the tool asks `lsof` who has the file or its `-wal` / `-shm` files open, and where `lsof` is unavailable treats leftover `-wal` / `-shm` files as "in use". `--force` overrides this; the message explains the risk (two programs writing one file can lose changes; the app does not see the new translation until it restarts). Quit the app first instead.
- `--replace` overwrites a translation with the same code; `--dry-run` checks the file and prints the report without opening the library.
- Back up `Library.sqlite` before importing into a library used in services; opening it with this version also applies migration `v7`.

## Licensing

ADR-0008 applies unchanged. Only VI1925 is meant to be bundled (as one translation file, with the owner's approval recorded in its metadata); every other translation is imported at each church from a file or database that church provides and stays on that church's Mac. The import tool writes Bible text only where the caller names, never into the repository (`Bibles/` at the repository root is git-ignored for local runs). The tests use eleven King James Version verses and synthetic filler text, and synthetic full-size translations are built in memory or in a temporary folder that is deleted. The church is responsible for having the right to use what it imports (ADR-0008 decision 4); the tool says so in its help.
