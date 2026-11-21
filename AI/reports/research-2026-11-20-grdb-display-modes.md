# Research: GRDB, Vietnamese search, durability, display modes (2026-11-20)

Done by a Sonnet research subagent. Items marked unconfirmed were not verified against a primary source.

## GRDB
- Latest stable 7.12.0 (1 Nov 2026). `.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0")`, product `GRDB`. Source: github.com/groue/GRDB.swift releases and README.
- Needs Swift 6.1+, Xcode 16.3+. Package builds in Swift 6 language mode.
- `DatabasePool` opens in WAL and allows reads during a write. Async `read`/`write` honour cancellation. Observe with `ValueObservation.tracking{}.values(in:)`.
- Pitfalls: struct records only; a stored `static let databaseSelection` fails strict checking (use a computed `static var`); sync calls are not re-entrant; never two connections to one file.

## Migrations
- `DatabaseMigrator` with named migrations, each in its own transaction; `migrate(_:upTo:)` stops at a named migration.
- `eraseDatabaseOnSchemaChange` wipes the database when migrations change. Do not ship.

## Vietnamese full-text search
- FTS5 `unicode61 remove_diacritics 2` folds letters with stacked marks. Coverage of every Vietnamese letter: unconfirmed.
- đ/Đ are not folded to d (no entry in `fts5_unicode2.c`). Confidence high; reading done through a fetch tool.
- Workaround: a normalised search column, same folding applied to the query.
- FTS5 in the macOS system SQLite: unconfirmed. Check at run time.

## Durability
- WAL with `synchronous=NORMAL`: a power cut may roll back recent commits. Survival across an app crash is an inference, not sourced.
- Local USB APFS should support WAL. Effect of case-sensitivity and ignored ownership: unconfirmed.

## Display modes (all from memory, unconfirmed against Apple docs)
- List: `CGDisplayCopyAllDisplayModes`, `CGDisplayModeGetRefreshRate` (may return 0).
- Switch: `CGBeginDisplayConfiguration`, `CGConfigureDisplayWithDisplayMode`, `CGCompleteDisplayConfiguration`; `kCGConfigureForAppOnly` or `ForSession` reverts automatically.
- Pacing at 59.94 on a display at another rate cannot lock to vsync; schedule from the app's own clock.
