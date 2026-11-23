# SYS-015 report: migration v15 for the mode features

Feature IDs: SYS, SLIDE, MEDIA, STAGE, OUT, CUE. Brief: `AI/specs/SYS-015-migration-for-mode-features.md`. Model: Sonnet. Main folder, HEAD d7628c1, nothing committed.

## What v15 adds

- `mediaAsset.markIn`, `mediaAsset.markOut` (DOUBLE, NULL) and the table `mediaMarker` (id, assetID with ON DELETE CASCADE, time, name, actions, sortOrder, createdAt, updatedAt; index `mediaMarker_on_assetID`). One table for Media's markers and Cues' playback markers. Written against literal names only.
- Optional keys in stored JSON, written only when not at the default: slide object `name`, `isHidden`, `isLocked`, content case `video`; text object `fit`, `backgroundFill`; screen profile `connectedToKey`, `signalChains`, `screenLookID` (in `screenProfile.extra`). Collections stay in app state.
- One rendering rule: the compositor skips a hidden object. `video` draws nothing yet (feature work, UI-007). Fit, fill, locked, marks, markers, key note, chain and screen Look are stored only.
- A copy before a migration (the app only backed up before an import): a library that holds data is copied aside once before a migration runs, `Backups/Library before migration to v15 (was v14) <UTC date>.sqlite`, with SQLite's backup API on its own short-lived read-only connection. No copy, no migration: if the copy fails the open throws `MigrationBackupFailed`. Not taken for a new library, an in-memory store, a library refused as newer, or a fixture built with `migratingUpTo`.

## Decisions

- **Item 1 (downgrade):** older builds cannot open a v15 library. The existing newer-library guard (FIX-H item 14) refuses any library whose history holds a step the build does not know, so v15 is refused by every earlier build with nothing changed. No second guard. Rule recorded for later slices: a new `SlideObject.Content` case ships with a migration (an unreadable `objects` column reads as no objects, so an unguarded older build would lose them on save, KI-238). Tests: `aLibraryAtAStepThisBuildDoesNotKnowIsRefusedAndLeftAsItWas`, `aStoredObjectOfAKindThisBuildDoesNotKnowReadsAsNoObjects...`.
- **Item 3 (section name):** no stored field. A slide already points at its section (`slide.groupID`, `slideGroup.name`), so a copy could only disagree. `ShowDeck.sectionNames` (one entry per slide, default empty) is composed by `ArrangementResolver.sectionNames(for:groups:)` when the preview deck is built (`WorkspaceModel.previewDeck()`), and `ShowState.liveSectionName` / `nextSectionName` give the stage composer the live and next section. Known cost: the name is as old as the deck (KI-237).
- ADR-0009 records both, plus the backup rule and "defaults write no key".

## Test evidence: failing, then passing

New tests (all `SYS015_*`): `SYS015_MigrationTests` (10), `SYS015_StoreTests` (17), `SYS015_FieldsTests` (15), `SYS015_ProgramTests` (15), `SYS015_EditorTests` (3), `SYS015_ScenesDigestTests` (2): 62 tests.

- Migration tests were run before the migration existed and failed at runtime for the right reason (7 of 8 then: `no such table: mediaMarker`, applied list ended at `v14`, no `markIn` column, no backup file; the two "no copy" tests passed as they should). After `v15` and the backup they passed.
- The rendering digest was recorded on unchanged code (publications 18, digest `ab7dcfe9...9412`, with text, shape and image objects) and passes after every change. The existing `FIXQ_PublishedScenesDigestTests` digest also passes unchanged.
- Domain, store, package and editor tests were written before the types and methods existed and failed to compile for the missing API (`no member 'markOut'`, `cannot find 'MediaMarker'`, `no member 'setMediaMarks'`, `no member 'markers'` and so on); they passed once implemented.
- Two real findings from the full runs, both fixed: opening a pool reader in the backup step left a non-empty `-wal` after close (`ToolLibraryGuardTests`; the backup now uses its own connection before the pool exists); one existing test asserted v14 was the newest step.
- Existing test edit (the only one): `FIXK_TextFramesStoreTests.swift` line 39 asserted `applied.last == "v14"`, which cannot hold after any later migration; now `applied.prefix(14) == v1...v14` (same fix earlier slices made for v2 and v3).

## Public API for the feature agents

Domain (`import Domain`):
- `SlideObject`: `init(id:frame:opacity:name:isHidden:isLocked:content:)` (new params defaulted); `name: String?` (trimmed, at most `SlideObject.maxNameLength` = 120, blank is nil; `SlideObject.cleanName`), `isHidden`, `isLocked`; `drawableLayer: SceneObjectLayer?` (nil for hidden and for video; `sceneLayer` stays total and draws nothing for video).
- `Content.video(VideoObject)`; `VideoObject(mediaID:loops: true, muted: true)`.
- `TextObject`: `fit: TextFit` (`.none`, `.shrinkToFit`), `backgroundFill: ColorRGBA?`.
- `MediaAsset.markIn`, `markOut` (init parameters defaulted nil). `MediaMarks.isValidTime(_:length:)`, `MediaMarks.isValid(markIn:markOut:length:)`.
- `MediaMarker` (`id, assetID, time, name, actions, sortOrder, createdAt, updatedAt`), `MediaMarker.emptyActions`, `validatedActions(_:)`, `cleanName(_:)`, `maxNameLength` 120, `maxActionsBytes` 64 KiB, `maxPerAsset` 1,000.
- `ScreenProfile`: `connectedToKey: [String]`, `signalChains: [[ChainNode]]`, `screenLookID: UUID?` (init parameters defaulted); `connectedKeyNote(mirror:)`, `setConnectedKeyNote(_:mirror:)`, `signalChain(mirror:)`, `setSignalChain(_:mirror:)` (max `ScreenProfile.maxChainLength` 12). `ChainNode(kind: .enclosure/.converter/.other, label:)` (label bounded to 120).
- `ShowDeck(presentationID:slides:sectionNames:)`, `ShowDeck.sectionName(at:)`, `ShowState.liveSectionName`, `ShowState.nextSectionName`, `ArrangementResolver.sectionNames(for:groups:)`.

Persistence (`LibraryStore`, all `async throws`; unknown ids throw `StoreError.notFound`, values that are not real or a full clip throw the new `StoreError.invalidValue`, a Look that does not exist throws `.invalidReference`):
- `setSlideObjectName(_:objectID:inSlide:)`, `setSlideObjectHidden(_:objectID:inSlide:)`, `setSlideObjectLocked(_:objectID:inSlide:)` -> the updated `Slide`.
- `setMediaMarks(markIn:markOut:forAsset:)` (nil clears that mark; 0 to the clip's length, in not after out, video and audio only) and `clearMediaMarks(forAsset:)` -> the updated `MediaAsset`. `mediaAssets(kind:)` returns the marks.
- `mediaMarkers(forAsset:)` (time order, then the order added), `addMediaMarker(forAsset:time:name:actions:)`, `moveMediaMarker(id:to:)`, `renameMediaMarker(id:to:)`, `setMediaMarkerActions(id:actions:)`, `deleteMediaMarker(id:)`.
- `setScreenKeyNote(_:mirror:forScreen:)`, `setScreenSignalChain(_:mirror:forScreen:)`, `setScreenLook(_:forScreen:)`; `saveScreenProfiles` and `screenProfiles()` carry the new fields; `deleteLook` clears `screenLookID` from every screen that had it.
- Package: a video object's clip, a clip's marks and markers travel (`ProgramDocument.AssetEntry.markIn/markOut/markers`); the reader refuses marks or markers that are not real times, bad or oversized actions, over 1,000 markers, and a video with no clip in the package, and bounds names to 120 characters; import renames a video object's clip and a marker action's clips like a slide background. A video whose clip is gone is left out of the export with a warning.

## Docs

Updated: `docs/19-data-dictionary.md` (v15 section, mediaAsset and extra rows), `docs/17-change-log.md`, `docs/16-known-issues.md` (KI-231 to KI-238), new `docs/adr/0009-v15-fields-and-downgrade.md`. Not touched (coordinator's): `docs/14-current-status.md`, `docs/15-agent-handoff.md`, feature specs. App files touched: only two one-line `.video` cases in `EditInspector.swift` and `SlideObjectsEditor.swift` so the switches stay exhaustive.

## Not verified

- Nothing was run against the owner's real library or the app UI; scratch libraries only. Hands-on: Not Verified.
- No hardware, no playback: marks and markers are stored only, `video` draws nothing.
- The backup was tested with SQLite files in temp folders; a read-only or full disk was tested by a plain file where `Backups/` belongs, not a real full disk.
- Restoring a pre-migration copy is a manual step (KI-235), not tested as a flow.
- The run summary lines (test counts, exit statuses) of the two final `./scripts/check.sh` runs are in the final message.
