# Brief: SYS-002 — settings and media references in SQLite (schema v3)

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/19-data-dictionary.md`, `AI/reports/SYS-001-report.md`, `AI/reports/SLIDE-003-report.md`, the existing `Sources/Persistence`, `Sources/Domain/Theme.swift`, `Look.swift`, `OutputRouting.swift`, `LibraryModels.swift`, and the coordinator test `Tests/SettingsStoreTests/SettingsStoreTests.swift`.

Catalogue: PRES-06, SCRN-08, MEDIA-08, MEDIA-01 (storage half). Closes KI-016 for storage.

## Goal

Make `SettingsStoreTests` pass by adding migration `v3` and the store operations for themes, Looks, props, screen profiles and media assets.

## Do not modify

- Coordinator-owned tests. Migrations `v1` and `v2`. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/OperatorCore`, `Tests/OperatorCoreTests`, `App/`, `Sources/RenderEngine`, `Sources/OutputEngine`, `Sources/MediaEngine`: another agent is working there. It calls the existing store API, so keep every existing public method's signature and behaviour unchanged.

## What to build

**`Domain`**: `Presentation.themeID: UUID?` (default nil); `MediaAsset` (`id`, `name`, `kind`, `path`, `bookmark: Data?`, `duration: Double?`, `pixelWidth: Int?`, `pixelHeight: Int?`, `addedAt`) and `MediaKind` (`image`, `video`, `audio`), in a new file.

**`Persistence`** (new file `LibraryStore+Settings.swift` plus migration `v3`):
- Tables `theme`, `look`, `prop`, `screenProfile`, `mediaAsset`; `presentation.themeID` nullable.
- Themes: `themes()` (custom only, by folded name), `saveTheme` (upsert by id; rejects built-in ids and blank names), `deleteTheme` (clears `presentation.themeID` that pointed at it, in the same transaction), `setTheme(_:forPresentation:)` (accepts nil, a built-in id, or a stored theme id).
- Looks: `looks()` in creation order, `saveLook` (upsert), `deleteLook`.
- Props: `props()`, `saveProp(_:bookmark:)` (a nil bookmark keeps the stored one), `bookmark(forProp:)`, `deleteProp`.
- Screen profiles: `screenProfiles()`, `saveScreenProfiles(_:)` replacing the whole ordered set in one transaction.
- Media assets: `addMediaAsset(...)` (same path returns the existing asset), `mediaAssets(kind:)` in order added, `renameMediaAsset`, `removeMediaAsset` (removes the reference only; never touches the file).
- Store structured values (theme definition, Look screens, frames) as JSON text columns with a stable, documented encoding. For the Look's per-screen dictionary, encode with string UUID keys so the JSON is readable and stable.
- `playlistItems(of:)` and the other v2 queries must keep working on a store opened with `migratingUpTo: "v2"`.

**Docs**: add every v3 table and column to `docs/19-data-dictionary.md`.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'SettingsStoreTests|PersistenceTests'` passes; the full suite too once the other agent's `OperatorCoreTests` compile (say which you ran).
2. `./scripts/check.sh` exits 0, or you state exactly which step could not run because of the other agent's unfinished work.
3. `AI/reports/SYS-002-report.md` records files, decisions, commands run with exit status, and everything not verified.
