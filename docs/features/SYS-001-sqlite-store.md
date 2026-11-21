# SYS-001 — SQLite store

Satisfies: NFR-06, NFR-07, and the storage half of PRES-02, PRES-03, PRES-04, PRES-08. Phase 1. Decisions: ADR-0004.

## Behaviour

1. Opening the store creates the library file if absent and migrates it to the latest schema.
2. Schema v1 holds libraries, presentations, slide groups, slides, arrangements, themes, playlists, media assets and app state. See `docs/19-data-dictionary.md`.
3. Repositories expose async create, read, update, delete and reorder operations, and observation streams for the interface.
4. Deleting a library deletes its presentations; deleting a presentation deletes its slides, groups and arrangements, and removes it from playlists.
5. Reordering keeps `sortOrder` dense and stable.
6. Search folds text (ADR-0004, decision 8) and matches title and lyric text, ranking title matches first.
7. App state records the open playlist and selected item so a relaunch can restore them (NFR-06).

## Acceptance

| Check | Level |
|---|---|
| A new file migrates to v1 and reports the expected tables | Unit Tested |
| A v1 fixture with rows survives migration to the latest version | Unit Tested |
| Cascades behave as in point 4 | Unit Tested |
| Reorder keeps a dense order after moves and deletes | Unit Tested |
| "an dien la lung" finds a song containing "Ân điển lạ lùng"; every Vietnamese letter folds to its base letter; "dien" finds "điển" | Unit Tested |
| A write followed by closing the pool without a clean shutdown is present on reopen | Unit Tested |
| Search over 2,000 songs returns within 200 ms | Measured on this Mac |
