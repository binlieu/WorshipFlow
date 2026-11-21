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
| bodyFolded | TEXT NOT NULL DEFAULT '' | Folded primary and secondary text of all slides, in slide order, plus the words of text boxes (v5). Speaker notes are not searched |
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

Keys added by UI-003 (no schema change; all JSON text in `appState`):

| Key | Value | Notes |
|---|---|---|
| `settings.mediaDock` | `{"height": 176, "isCollapsed": false}` | Height and collapsed state of the media dock in Show. A damaged value falls back to the defaults |
| `stage.recentMessages` | JSON array of up to 5 strings, newest first | The last stage messages sent, for reuse. The message that is on stage now is never stored (a relaunch starts without one) |
| `stage.toolbarTimers` | JSON array of timer ids (UUID strings) | The timers the operator marked for the toolbar. Absent: the defaults (first elapsed timer, first countdown). An empty array means none |

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

## Schema v4 (migration `v4`, STAGE-001a)

Both tables keep the whole definition as JSON text (sorted keys, no escaped slashes, UUIDs upper-case, as in v3). Rows are upserted, so editing keeps a row's place in the creation-order listing. No foreign keys.

### stageLayout
Custom stage layouts. The built-in `StageLayout.standard` (fixed id `5A6E0001-0000-4000-8000-000000000001`) lives in code: it is never stored, and saving or deleting it throws `invalidReference`.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty |
| definition | TEXT NOT NULL | `StageLayout` as JSON: `id`, `name`, `background`, `warningColor` and `elements` (each with `id`, `kind`, `frame`, `style`, `alignment`, `verticalAlignment`, `showsSecondLanguage`). A `timer` element holds the timer's id, which may be gone: such an element draws nothing |
| createdAt | DATETIME NOT NULL | Listed by this, then insertion order |
| updatedAt | DATETIME NOT NULL | |

### showTimer
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Trimmed, non-empty |
| definition | TEXT NOT NULL | `ShowTimer` as JSON: `id`, `name`, `kind` (countdown seconds, elapsed, or countdown-to date), `runningSince` (seconds since the reference date, omitted while stopped) and `accumulated`. A running timer is stored as its start anchor, so a relaunch shows the right time |
| createdAt | DATETIME NOT NULL | Listed by this, then insertion order |
| updatedAt | DATETIME NOT NULL | |

## Schema v5 (migration `v5`, SLIDE-001a)

Adds slide objects: text boxes, shapes and images laid over a slide. No new table.

### Columns added to v1 tables
| Table.column | Type | Notes |
|---|---|---|
| slide.objects | TEXT, nullable | JSON array of `SlideObject`, back to front (first is drawn first). NULL when the slide has no objects, which is every lyric slide and every slide written before v5, so plain slides stay small. Each element has `id` (upper-case UUID), `frame` (`x`, `y`, `width`, `height` as fractions of the slide, top-left origin), `opacity` (0...1) and `content`, one of `{"text": {"_0": TextObject}}`, `{"shape": {"_0": ShapeObject}}`, `{"image": {"_0": ImageObject}}` (Swift's synthesized enum encoding). Keys are sorted. Sizes, outline, shadow and stroke widths are in points at a 1080-line reference. An unreadable value reads as no objects; it is never an error. The store writes the column only when a slide has objects or the column exists, and an update that would store objects on a store older than v5 fails instead of dropping them |

The words of text objects are folded into `presentation.bodyFolded` and the search index with the lyrics (`TextObject.text` only; shapes and images add no words). `replaceContent` produces slides without objects.

## Derived search index (not a migration)

`presentationSearch` is an FTS5 virtual table `(title, body, presentationID UNINDEXED)`, tokenizer `unicode61 remove_diacritics 0` because the text is already folded. It is created at open when the system SQLite has FTS5, filled from `titleFolded` and `bodyFolded` if missing, and updated in the same transaction as every change. When FTS5 is absent it is dropped and search uses `LIKE` on the folded columns. It holds no data that cannot be rebuilt.

## Not yet persisted

Media playback state and per-presentation media are not persisted yet; they arrive with the features that use them (no placeholder tables).

## Schema v6 (HW-002)

| Table | Column | Type | Notes |
|---|---|---|---|
| screenProfile | extra | TEXT, nullable | JSON for settings added after v3: mirrors, SDI destination details, video mode. NULL for a plain profile. |

## Schema v7 (migration `v7`, LIB-004b)

Bible translations imported into the church's library (ADR-0008 decision 4). Written only by `ScriptureStore`, through the library's one connection pool. Nothing here is created by an older file until it is opened with this version; rows in v1 to v6 tables are not touched.

### scriptureTranslation
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID. Kept when a translation is replaced |
| code | TEXT NOT NULL UNIQUE (NOCASE) | The translation file's `id` ("kjv", "VI1925"). Unique ignoring case. This is what the app and the importer call the translation |
| name | TEXT NOT NULL | |
| language | TEXT NOT NULL | BCP 47 tag ("en", "vi") |
| abbreviation | TEXT NOT NULL | Shown on slides |
| copyright | TEXT, nullable | As stated in the file; the exporter writes "not stated" when it was not given |
| licence | TEXT, nullable | The file's `license` |
| sourceDescription | TEXT, nullable | The file's `sourceURL`: where the church got the text |
| isPublicDomain | BOOLEAN NOT NULL | False unless the file says so |
| ownerApprovalJSON | TEXT, nullable | `OwnerApproval` as JSON: `approved`, `date` (ISO 8601), `note` |
| versificationID | TEXT NOT NULL | "KJV", "VI1925", or the label of the translation's own table |
| versificationJSON | TEXT, nullable | NULL when the translation follows the built-in table named by `versificationID` exactly. Otherwise the table: `{"id": "...", "books": {"GEN": [[count, highest], ...]}}`, one `[count, highest]` pair per chapter (`[0, 0]` for a chapter the table does not have) |
| versificationNote | TEXT, nullable | The file's `versificationNote` |
| verseCount | INTEGER NOT NULL | Verses stored |
| importedAt | DATETIME NOT NULL | |

### scriptureVerse (WITHOUT ROWID)
| Column | Type | Notes |
|---|---|---|
| translationID | TEXT NOT NULL | References `scriptureTranslation(id)`, ON DELETE CASCADE |
| bookOrder | INTEGER NOT NULL | 1 to 66, canon order (`Canon.books`) |
| chapter | INTEGER NOT NULL | |
| verse | INTEGER NOT NULL | |
| text | TEXT NOT NULL | The verse exactly as imported (no normalisation of diacritics) |
| textFolded | TEXT NOT NULL | `SearchFolding.fold(text)`: source of truth for search, like `presentation.bodyFolded` |

Primary key `(translationID, bookOrder, chapter, verse)`. A full Bible is about 31,000 rows.

### Derived scripture search index (not a migration)

`scriptureSearch` is an FTS5 virtual table `(textFolded, translationID UNINDEXED, bookOrder UNINDEXED, chapter UNINDEXED, verse UNINDEXED)`, tokenizer `unicode61 remove_diacritics 0`. Created at open when the system SQLite has FTS5 and rebuilt from `scriptureVerse` if missing; dropped when FTS5 is absent, in which case search uses `LIKE` on `textFolded`. It is only read through a join to `scriptureVerse`, so a stale row cannot produce a result. `ScriptureStore` writes it in the same transaction as the verses.

## Schema v9 (migration `v9`, CUE-002a)

Show control: macros, slide actions, scheduled events, the schedule engine's state and MIDI bindings. Every `definition` and `state` column is JSON text written by `CueStore` with sorted keys and a top-level `version` (currently 1 for each shape). A missing version reads as 1; a newer version is read as far as it is understood and is never overwritten by an older build. UUIDs inside the JSON are the engine's own `Codable` form (upper-case text); dates inside the JSON are seconds since 2001-01-01 (`Date`'s default), so a fractional second survives. Rows of earlier tables are not touched.

### cueMacro
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Copy of the name inside `definition`, for listing; `definition` is the source of truth |
| definition | TEXT NOT NULL | `Macro` JSON: `{"version", "id", "name", "steps": [action, ...]}`. Actions are `CueAction` objects (`kind` plus fields); an unknown kind is kept as it is |
| sortOrder | INTEGER NOT NULL | Dense 0...n-1; the operator's order. Index `cueMacro_on_sortOrder` |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

A macro may name a macro that is not stored (macros are saved in any order); cycles and nesting deeper than 8 are refused at save.

### cueSlideActions
| Column | Type | Notes |
|---|---|---|
| slideID | TEXT PK | FK `slide.id`, ON DELETE CASCADE. At most one row per slide |
| definition | TEXT NOT NULL | `CueActionList` JSON: `{"version", "actions": [...]}`. Transport actions are refused at save, also through macros |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

`LibraryStore.replaceContent` (a reflow) deletes and re-creates a presentation's slides, which would cascade these rows away; it takes them out first and writes them back, in the same transaction, against the new ids of the slides whose words did not change (the same matching as speaker notes: same section, same first-language words, first unused match). Rows of slides that nothing matches are dropped.

### cueScheduledEvent
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT NOT NULL | Copy of the name inside `definition` |
| enabled | BOOLEAN NOT NULL | Copy of `isEnabled` inside `definition` |
| definition | TEXT NOT NULL | `ScheduledEvent` JSON: `{"version", "id", "name", "isEnabled", "timing", "payload", "activeFrom"}`. `payload` is a list of actions or a macro id |
| createdAt | DATETIME NOT NULL | |
| updatedAt | DATETIME NOT NULL | |

No sort column: events list in insertion order (`rowid`), which the engine uses to order events that fall at the same time. A replaced row keeps its place.

### cueScheduleState
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | CHECK `id = 1`: one row |
| state | TEXT NOT NULL | `ScheduleEngineState` JSON: `{"version", "gracePeriod", "lastHandled": [{"event", "at"}, ...], "lastCheckedAt"}` |
| lastCheckedAt | DATETIME | Copy of `lastCheckedAt` inside `state`, written in the same statement |
| updatedAt | DATETIME NOT NULL | |

`lastHandled` entries for events that no longer exist are dropped when the event is deleted and ignored when the library is loaded.

### cueMIDIBinding
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| definition | TEXT NOT NULL | `MIDIBinding` JSON: `{"version", "id", "name", "pattern", "command"}` |
| sortOrder | INTEGER NOT NULL | Dense 0...n-1; the engine uses the first binding in this order that matches. Index `cueMIDIBinding_on_sortOrder` |

## Schema v10 (migration `v10`, CUE-002b)

### remoteToken
One row per phone paired with the remote control server. A salted hash of the token; the token itself is never stored.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID, the first half of the token the phone holds |
| label | TEXT NOT NULL | The name the phone gave when pairing |
| salt | BLOB NOT NULL | 16 random bytes |
| hash | BLOB NOT NULL | SHA-256 over salt then the token's secret |
| createdAt | DATETIME NOT NULL | |
| lastUsed | DATETIME | Written at most once every 30 seconds per token |

Other app state keys added: `cue.midi.settings` (MIDI on or off, chosen input and output by stable id and name, virtual ports) and `cue.remote.settings` (remote control on or off, port), both JSON in `appState`.

### LIB-004c: scripture playlist items (no schema change)

`playlistItem.kind = 'scripture'` with `payload` JSON `{"label", "ranges":[{"book","startChapter","startVerse","endChapter","endVerse"}], "primaryCode", "secondaryCode"}`; `presentationID` is NULL. No verse text is stored. State key `scripture.choices` (settings state table): `{"primary","secondary","versesPerSlide"}`.

### LIB-005: media paths relative to the library's folder (no schema change)

A path stored in `slide.objects` (image objects), `theme.definition` (an image background), `prop.imagePath` and `mediaAsset.path` that lies inside `<library folder>/Media/Imported/` is stored as `Media/Imported/<program id>/<file>`, relative to the folder that holds `Library.sqlite`. `LibraryStore` converts it to an absolute path when it reads and back when it writes, so callers only see absolute paths; every other path is stored as it was given, and an in-memory store converts nothing. A relative path with a `..` part is never turned into a file path. Files below `Media/Imported/<program id>/` are named `<sha256>.<ext>`; `missing/<name>` is a path that never had a file. The program package format (not stored in the library) is described in `docs/features/LIB-005-program-export-import.md`.

### Backups folder (FIX-G, no schema change)

`<library folder>/Backups/Library before import <yyyy-MM-dd HHmmss UTC>.sqlite` (a counter is added for a second backup in the same second): a complete copy of the library file made with SQLite's backup API before a program import replaces anything. The newest five of that name are kept; other files in the folder are never touched. Opens like the library itself.

### Schema v11 (migration `v11`, FIX-G): a slide's own background, and MEDIA-010's hot folders

Migration `v11` is additive: `ALTER TABLE slide ADD COLUMN background TEXT` (nullable). It then moves the old `appState` entries `slideBackgrounds.<presentation id>` (a JSON object from slide id to selection, written by the first MEDIA-010 build) into the slide rows and deletes those entries; an entry for a slide or presentation that no longer exists, or one that cannot be read, is dropped. Every other row is untouched. A column rather than a child table: a slide has at most one background, so its own row carries it and it goes with the row (delete slide, delete presentation, re-flow) with no foreign key to keep.

| Column | Type | Meaning |
|---|---|---|
| `slide.background` | TEXT, NULL | JSON `{"assetID": "<UUID>", "duration": <seconds or absent>, "kind": "image" or "video"}` (a `MediaSelection`, keys sorted) naming a media bin item; NULL when the slide uses the presentation's own background. The item is not checked: if it was removed the slide keeps the choice and shows the missing-media mark. Written by `appendSlide`, `updateSlide`, a re-flow (carried by the same match as notes and objects) and a program import |

The hot folders are still one JSON value in `appState`:

| Key | Value |
|---|---|
| `media.hotFolders` | JSON array, in the order added: `[{"id": "<UUID>", "name": "...", "path": "/absolute/path", "bookmark": "<base64 security-scoped bookmark, optional>"}]`. Absent when there are none. Only the reference is stored; the folder and its files are never changed. The items of a folder are not stored: they are listed from the folder, with ids derived from the folder id and the file name |

### Schema v12 (migration `v12`, UI-005b): library kind, service date, prop targets and kinds

Migration `v12` is additive and rewrites nothing: `library.kind TEXT NOT NULL DEFAULT 'songs'` (`songs`, `scripture`, `sermons`, `announcements`); `playlist.serviceAt DATETIME` (nullable; a UTC instant; the toolbar title shows it in the user's locale); `prop.targets TEXT NOT NULL DEFAULT '["audience","broadcast"]'` (JSON array of roles; a prop is drawn only on these; the default is where props were drawn before v12, the stage never drew them), `prop.kind TEXT NOT NULL DEFAULT 'image'` (`image`, `text`) and `prop.text TEXT` (JSON `{text, fontSize, colorHex, anchor}` for a text prop; `fontSize` in points on a 1080-line picture; `anchor` one of nine positions). `playlistItem.kind` gains the values `sermon`, `media` and `announcements`; `payload` for the last two is JSON (`{assetID, name, kind}` and `{label, items, secondsPerPicture}`). An older build reads these kinds as "Unknown item". A program package carries `playlist.serviceAt` (ISO 8601), and item entries `media` and `announcements`; the bin items they name travel in `mediaAssets` with their files.
