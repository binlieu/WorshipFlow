# Data dictionary

Library file: `~/Library/Application Support/WORSHIPFLOW/Library.sqlite` by default (ADR-0004). One `DatabasePool`, WAL, `synchronous = NORMAL`, foreign keys on. Primary keys are UUIDs stored as upper-case text. Dates are stored as GRDB's UTC text (`yyyy-MM-dd HH:mm:ss.SSS`). Migrations are named and never edited after release; the applied names are in `grdb_migrations`.

## Schema v1 (migration `v1`, SYS-001)

### library
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty |
| sortOrder | INTEGER NOT NULL | Dense 0...n-1 among libraries |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

### presentation
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| libraryID | TEXT NOT NULL | FK `library.id`, ON DELETE CASCADE. Index `presentation_on_libraryID` |
| title | TEXT NOT NULL | Trimmed, non-empty |
| kind | TEXT NOT NULL | `song`, `sermon`, `scripture`, `other` |
| titleFolded | TEXT NOT NULL DEFAULT '' | `SearchFolding.fold(title)`, maintained in the same transaction as every title or slide change |
| bodyFolded | TEXT NOT NULL DEFAULT '' | Folded primary and secondary text of all slides, in slide order. Speaker notes are not searched |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | Bumped on slide changes |

### slide
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| presentationID | TEXT NOT NULL | FK `presentation.id`, ON DELETE CASCADE |
| sortOrder | INTEGER NOT NULL | Dense 0...n-1 within the presentation. Index `slide_on_presentationID_sortOrder` |
| primaryText | TEXT NOT NULL | `SlideContent.primary` |
| secondaryText | TEXT | `SlideContent.secondary` |
| notes | TEXT NOT NULL DEFAULT '' | Speaker notes |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

### playlist
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty |
| createdAt | DATETIME NOT NULL | Playlists are listed by this |
| updatedAt | DATETIME NOT NULL | |

### playlistItem
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID. The same presentation may appear several times |
| playlistID | TEXT NOT NULL | FK `playlist.id`, ON DELETE CASCADE |
| presentationID | TEXT NOT NULL | FK `presentation.id`, ON DELETE CASCADE. Index `playlistItem_on_presentationID` |
| sortOrder | INTEGER NOT NULL | Dense within the playlist, re-closed after a presentation is deleted. Index `playlistItem_on_playlistID_sortOrder` |
| createdAt | DATETIME NOT NULL | |

### appState
| Column | Type | Notes |
|---|---|---|
| key | TEXT PK | For example `openPlaylist` (NFR-06) |
| value | TEXT NOT NULL | Setting a key to nil deletes the row |
| updatedAt | DATETIME NOT NULL | |

## Derived search index (not a migration)

`presentationSearch` is an FTS5 virtual table `(title, body, presentationID UNINDEXED)`, tokenizer `unicode61 remove_diacritics 0` because the text is already folded. It is created at open when the system SQLite has FTS5, filled from `titleFolded` and `bodyFolded` if missing, and updated in the same transaction as every change. When FTS5 is absent it is dropped and search uses `LIKE` on the folded columns. It holds no data that cannot be rebuilt.

## Not yet persisted

Slide groups, arrangements, themes and media assets named in `docs/features/SYS-001-sqlite-store.md` are not in v1; they arrive with the features that use them (no placeholder tables). Screen and Look configuration is `OUT-002`.
