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

## Schema v2 (migration `v2`, SLIDE-003 and SLIDE-004)

Adds song sections and arrangements. Rows written under v1 are untouched: their slides have `groupID` NULL.

### slideGroup
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| presentationID | TEXT NOT NULL | FK `presentation.id`, ON DELETE CASCADE |
| name | TEXT NOT NULL | Section label as the user wrote it, such as `Verse 1` or `Điệp khúc` (colon dropped). Section names are not searched |
| sortOrder | INTEGER NOT NULL | Order of first appearance in the text. Index `slideGroup_on_presentationID_sortOrder` |

`replaceContent` keeps a group when its exact name still appears, so its id (and any arrangement using it) survives an edit. One group per distinct name.

### arrangement
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| presentationID | TEXT NOT NULL | FK `presentation.id`, ON DELETE CASCADE. Index `arrangement_on_presentationID` |
| name | TEXT NOT NULL | Trimmed, non-empty |
| createdAt | DATETIME NOT NULL | Arrangements are listed by this |
| updatedAt | DATETIME NOT NULL | |

### arrangementItem
| Column | Type | Notes |
|---|---|---|
| arrangementID | TEXT NOT NULL | FK `arrangement.id`, ON DELETE CASCADE. Part of the primary key |
| position | INTEGER NOT NULL | Dense 0...n-1; part of the primary key. A group may appear at several positions |
| groupID | TEXT NOT NULL | FK `slideGroup.id`, ON DELETE CASCADE; must belong to the arrangement's presentation (checked by the store). Index `arrangementItem_on_groupID` |

### Columns added to v1 tables
| Table.column | Type | Notes |
|---|---|---|
| slide.groupID | TEXT, nullable | FK `slideGroup.id`, ON DELETE SET NULL. NULL means the slide is in no section and is left out of every arrangement. Index `slide_on_groupID` |
| playlistItem.arrangementID | TEXT, nullable | FK `arrangement.id`, ON DELETE SET NULL. NULL means natural slide order. Must be an arrangement of the item's presentation (checked by the store). Index `playlistItem_on_arrangementID` |

## Schema v3 (migration `v3`, SYS-002)

Adds themes, Looks, props, screen profiles and media assets (KI-016). Rows written under v1 or v2 are untouched.

JSON columns use one fixed encoding (`SettingsJSON`): sorted keys, no escaped slashes, UUIDs as upper-case strings, `nil` optionals omitted. Built-in themes (`Theme.builtIn`) live in code and are never stored. Reads throw if a stored value no longer decodes; nothing is silently dropped.

### theme
Custom themes only.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID. A built-in theme id is rejected by `saveTheme` |
| name | TEXT NOT NULL | Trimmed, non-empty |
| nameFolded | TEXT NOT NULL | `SearchFolding.fold(name)`; themes are listed by this, then insertion order |
| definition | TEXT NOT NULL | The `Theme` value as JSON (Codable encoding of `Theme`: `id`, `name`, `background`, `primary`, `secondary`) |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

### look
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty |
| screens | TEXT NOT NULL | JSON object keyed by screen profile id (upper-case UUID string): `{"<UUID>": {"themeID": "<UUID>", "visibleLayers": ["background", "props", "slide"]}}`. `themeID` is omitted when nil; `visibleLayers` is sorted. Not a foreign key: a Look may mention a screen or theme that is gone, and the app falls back to defaults |
| createdAt | DATETIME NOT NULL | Looks are listed by this, then insertion order. Editing a Look keeps it |
| updatedAt | DATETIME NOT NULL | |

### prop
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | |
| imagePath | TEXT NOT NULL | Path as last seen |
| bookmark | BLOB | Security-scoped bookmark. Saving a prop with a nil bookmark keeps the stored one |
| frame | TEXT NOT NULL | `NormalizedRect` as JSON: `{"height":..,"width":..,"x":..,"y":..}` |
| opacity | DOUBLE NOT NULL | 0...1 |
| isOn | BOOLEAN NOT NULL | |
| createdAt | DATETIME NOT NULL | Props are listed by this, then insertion order |
| updatedAt | DATETIME NOT NULL | |

### screenProfile
The whole table is the ordered set of screen profiles; `saveScreenProfiles` replaces it in one transaction.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| sortOrder | INTEGER NOT NULL | 0...n-1 in the order given |
| name | TEXT NOT NULL | |
| role | TEXT NOT NULL | `audience`, `stage`, `broadcast` |
| destination | TEXT NOT NULL | `display` or `window` |
| displayID | INTEGER | CGDirectDisplayID when `destination` is `display`; NULL for `window` |
| isEnabled | BOOLEAN NOT NULL | |

### mediaAsset
A reference to a file in the media bin. The file itself is never read, moved or deleted by the store.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty; renamable |
| kind | TEXT NOT NULL | `image`, `video`, `audio`. Index `mediaAsset_on_kind` |
| path | TEXT NOT NULL UNIQUE | Adding the same path again returns the existing row |
| bookmark | BLOB | Security-scoped bookmark |
| duration | DOUBLE | Seconds; NULL for images |
| pixelWidth | INTEGER | NULL for audio |
| pixelHeight | INTEGER | NULL for audio |
| addedAt | DATETIME NOT NULL | Assets are listed by this, then insertion order |

### Columns added to v1 tables
| Table.column | Type | Notes |
|---|---|---|
| presentation.themeID | TEXT, nullable | A built-in theme id or a `theme.id`. NULL means the role default. No foreign key, because built-in ids have no row; `deleteTheme` sets it to NULL in the same transaction. Index `presentation_on_themeID` |

## Derived search index (not a migration)

`presentationSearch` is an FTS5 virtual table `(title, body, presentationID UNINDEXED)`, tokenizer `unicode61 remove_diacritics 0` because the text is already folded. It is created at open when the system SQLite has FTS5, filled from `titleFolded` and `bodyFolded` if missing, and updated in the same transaction as every change. When FTS5 is absent it is dropped and search uses `LIKE` on the folded columns. It holds no data that cannot be rebuilt.

## Not yet persisted

Media playback state and per-presentation media are not persisted yet; they arrive with the features that use them (no placeholder tables).
