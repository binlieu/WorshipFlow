# UI-006d report: Media mode features the design draws and the app lacked

Feature ID UI-006d. Brief `AI/specs/UI-006-mode-features.md` (Media row). Design `docs/UI/screens/05-media-audio.png`, `docs/UI/mockups/05-media-audio.html`. Levels reached: **Implemented, Unit Tested** (24 new tests), and run in a Debug build through the snapshot hook (a generated library, `--silent-audio`). Nothing here is Simulated, Hardware Verified or Live-Service Verified: no feature touches a device or an output.

## Ranked list (operator value over size)

| # | Candidate (UI-005d "left out") | Gain | Needs | Size | Decision |
|---|---|---|---|---|---|
| 1 | Offline files: callout and Locate... (M5) | A drive that is not mounted, or a moved folder, is seen before the service, not when a slide shows nothing; one pick brings the item back with its place in every slide | A file check (pure + injected), one new store method on existing columns | M | **Built** |
| 2 | Named collections (the design's "Announcement loop", "Motion backgrounds" rows) | Group the loop, the welcome pictures, the baptism set; find them in one click | One JSON text in the existing app-state table (key `media.collections`) | M | **Built** |
| 3 | Preview picture in the strip (the owner's open question) | See the clip being previewed | A picture area the 77 pt strip has no room for; a second decoder running | M | Not built (below) |
| 4 | Mark in / Mark out | Play a clip from and to chosen points | New stored fields per item, and the registry's player and `MediaTransport` honouring them | L | Not built: migration, engine |
| 5 | Add marker | Cue actions at a point of a clip | New stored table; `MarkerTracker` exists in CueEngine but nothing in the app feeds it a player position | L | Not built: migration, cue wiring |
| 6 | Routing matrix (M24) and Cue L / Cue R meters (M26) | Choose where audio goes | A second audio bus and device routing in the audio engine | L | Not built: hardware / audio engine, belongs with Screens and a bus slice |
| 7 | Live inputs row | Capture sources in the bin | DeckLink input discovery and a capture path; would be at most Simulated | L | Not built: hardware |

## Built features

### 1. Offline files and Locate... (UI-006d-1)

What it does:
- `MediaModel` knows which bin files cannot be read (`offlineIDs`, `offlineSummary`). The check runs off the main thread, only when something asks: the bin loads or changes, a disk is mounted or unmounted, the app comes forward, Media mode opens, after Locate. No timer, no `TimelineView`, so it adds nothing that ticks while idle (KI-190).
- The left list shows the design's callout at its foot: a warning, "1 file is offline" (or "N files are offline"), the file and the reason (the disk "X" is not connected, taken from the `/Volumes` path, or the file is not there any more), and **Locate...**. Nothing is drawn when nothing is offline.
- A tile (and a list row) of an offline item carries a warning mark and says "offline" to VoiceOver; the tile's menu has Locate... for that item.
- Locate... opens an open panel at the old folder (or its nearest existing parent, or /Volumes). The chosen file is read first and must be the same kind (video, picture, sound) as the item. The item keeps its id, name and date: only path, bookmark, duration and size change, so slides that use it as their own background recover without being touched. Other offline items from the same old folder move too when the chosen file's folder holds files of their names (a disk that came back under another name). A path that another bin item already uses is refused with a message and changes nothing. Problems are listed in the existing error banner, one sentence per file.
- Thumbnails of the moved items are made again.

Files: `OperatorCore/MediaOffline.swift`, `MediaModel+Offline.swift`; `Persistence/LibraryStore+MediaRelocate.swift` (`relocateMediaAsset`); `App/Sources/MediaLocate.swift` (callout, panel); edits in `MediaMode.swift`, `MediaBinPanel.swift`.
Tests (`UI006d_MediaOfflineTests.swift`, test first): the words for an unmounted disk, a moved file, several files and none; the relocation plan (neighbours that exist in the new folder move, others do not); the model finds and clears the set, rechecks on add and remove, locating keeps the id and persists, refuses another kind, an unreadable file and a path already in the bin. Level: Implemented, Unit Tested; the panel and the callout were run in the Debug build with a file taken away from under the bin (screenshot `UI-006d-media-offline-dark.png`). The open panel itself was not driven (see Not verified).

### 2. Named collections (UI-006d-2)

What it does: a "+" at the Media bin heading, or "New collection..." in a tile's menu, makes a collection (a name, empty or with that tile). Its row sits under the kinds with a count; clicking shows its items in bin order with its name as the title. A tile is added by its menu (Add to collection, with a check mark where it already is) or by dragging it onto the row; Remove from "name" is in the menu while the collection is open. Rows rename and delete from their menu (delete asks and says only the list goes). Names are trimmed, never empty, unique ignoring case. A collection never moves, copies or deletes a file; removing an item from the bin takes it out of every collection; collections persist across relaunch (JSON in the app-state table, key `media.collections`; unreadable text gives none and leaves the bin alone). The group grows with its rows below the design's 172 pt.
Keyboard and accessibility: rows are buttons with names and counts, "Delete collection" is a VoiceOver action; the Up/Down selection follows the shown items because the filter lives in `MediaModel.visibleAssets`. Undo: not offered (the bin's own remove and rename are not undoable either); delete confirms.
Files: `OperatorCore/MediaCollections.swift`, `MediaModel+Collections.swift`; edits in `MediaMode.swift`, `MediaBinPanel.swift`.
Tests (`UI006d_MediaCollectionsTests.swift`): names, adding keeps order and ignores repeats, pruning, bin order, stored-text round trip and torn text, delete; the model creates, filters, survives a relaunch, forgets removed items and stores that, refuses a bad name with a message, deleting the open collection returns to the whole bin. Level: Implemented, Unit Tested; seen in the Debug build (`UI-006d-media-offline-dark.png`: "Announcement loop", 2 items).

## Features not built

- **Preview picture (the owner's question).** Not built. The strip is 77 pt high in the design and has no room; a picture needs a 16:9 area (about 160 x 90) taken from the grid or the right column. The decode cost: the preview is a separate `AVPlayer` (`BinPlayerSupport.swift`), not the registry's, so a layer on it would not add decode work to the live path; it adds a second video decode on the same Mac (a ProRes or 4K clip decoded again while the show is live, plus a layer composited in the operator window). I cannot measure that here (no hardware, no live load) and the brief forbids claiming it, so it needs the owner's call on where the picture goes and one measured run with a live output playing. Smallest version if wanted: the selected tile shows the player's picture only while the preview plays.
- Mark in / Mark out / Add marker, routing matrix, Cue meters, Live inputs: see the ranked list.

## Needs a migration (for the coordinator's one migration brief)

- `mediaAsset`: `markIn REAL NULL`, `markOut REAL NULL` (seconds; null = whole clip). Used by the registry's player and `MediaTransport` for foreground and background clips (engine work as well).
- New table `mediaMarker(id TEXT PK, assetID TEXT NOT NULL REFERENCES mediaAsset(id) ON DELETE CASCADE, time REAL NOT NULL, name TEXT, actions TEXT NOT NULL)` (the `PlaybackMarker` shape; `actions` is the `CueAction` JSON) and the app side that feeds `MarkerTracker`.
- Collections are in app state today (key `media.collections`, one JSON); if the library should carry them in a program package export (LIB-005) they need `mediaCollection(id, name, sortOrder)` and `mediaCollectionItem(collectionID, assetID, sortOrder)`. Not needed for them to work.

## Rectangle table (`scripts/compare-rects.py`, `scripts/design-map-media.json`, dark, 1440 x 900)

Three entries added (callout row, its icon, Locate button), the capture hook gained a second pair of captures (`media-offline-dark/light`) with an item whose file is gone and a collection open. Offline capture:

| Region | Mapped | Within 1 pt |
|---|---|---|
| sidebar | 14 | 14 |
| centre | 19 | 16 |
| inspector | 31 | 29 |

Callout: the button is at the design's place (R +0.8: the "Locate..." text measure); the row and icon tops are skipped in the map because the callout is bottom-anchored and its text is a different sentence (3 lines against the design's 2; the design's reason is "external disk not mounted"). The standard captures (`media-dark/light`, no offline item) are unchanged: same remaining list as UI-005d (toolbar, import, layer switch, Audio cue label, level label R, Stop and health in the Show transport).

## Shared-file lines

- `Packages/WorshipFlowKit/Sources/OperatorCore/MediaModel.swift` (additive, marked `UI-006d`): `store`, `prober`, `isAvailable`, `reload()`, `persist(key:)`, `attempt` went from `private` to internal (so the new extension files can use them); five stored properties (`collections`, `collectionFilter`, `offlineIDs`, `offlineSummary`, `offlineTask`); one line in `visibleAssets` (the open collection's items); `load()` and `reload()` call `loadCollections()` / `scheduleOfflineCheck()` / `binChanged()`. No existing signature or behaviour changed.
- `WORSHIPFLOW.xcodeproj/project.pbxproj`: regenerated by xcodegen for the new app file; regenerate after merging, do not hand-merge.
- `App/Sources/UISnapshotMediaDesign.swift` (debug only, Media's own hook): the offline and collection captures.
- No other shared app file, `Package.swift` or `project.yml` touched.

## Docs entries for the coordinator

**Change log** (UI-006d): Media bin: offline files are found (callout at the foot of the list, a mark on the tile, no timer) and Locate... points an item at its file again keeping its id, so slides recover; neighbours from the same folder move with it. Named collections in the bin's list (new, rename, delete, add by menu or drag, remove), kept in the library's app state. `LibraryStore.relocateMediaAsset` added.

**Known issues** (unnumbered): (1) Media: no in and out points, markers, routing matrix, cue meters or live inputs (migration / engine / hardware, see the list). (2) Media: the preview video's picture is still not drawn (UI-005d item); costs above. (3) Collections hold bin items only, not hot-folder items. (4) Collections are not in the program package export. (5) The offline check does not notice a file that disappears while Media mode is closed until the app comes forward, a disk is mounted or unmounted, or the bin changes. (6) A file that exists but is unreadable counts as offline with the "not there any more" wording.

**Hands-on checklist**: unplug a disk with a bin item on it (or rename the file) and bring the app forward: callout and warning mark appear; Locate... and pick the file in its new place: the item returns, a slide that used it as background shows it again; choose a file of another kind: refused with a message; put the disk back: the callout goes. Make a collection from the "+", from a tile menu and by dragging a tile onto it; rename, delete (items stay); remove an item from the bin and see the count drop; relaunch and see it again; Up/Down in an open collection; light and dark; VoiceOver on the callout and rows.

**Feature spec updates**: MEDIA-010 (or a new MEDIA-011): offline detection, Locate, collections, `media.collections` key.

## Check and tests

Package tests alone (`swift test --filter UI006d`): 24 tests in 5 suites pass. `./scripts/check.sh` (own build folder) exits **1** both times (run twice, as the brief says): 3064 tests in 486 suites, the only failures are `MIDIRouterTests` `aHeldPadFiresOnceUntilReleased` and `aMissedNotificationIsCoveredByPolling` (30 s waits; the same two UI-005d recorded under parallel builds; MIDIIO is not touched by this slice). Because check.sh stops at the first failure, the app builds were run by hand with the same commands: Debug and Release (`xcodebuild`, arm64) both exit 0 with no errors. The Release hook-string check at the end of check.sh was not reached and not run.
Pictures: `AI/reports/UI-006d-media-offline-dark.png` and `-light.png` (the offline callout and the open collection "Announcement loop"; the sandbox had no test clip, so the grid shows pictures only).

## Not verified

The NSOpenPanel path of Locate... (no clicks possible on a locked screen; the model path is unit tested, the callout is seen in a capture); the drag of a tile onto a collection row (SwiftUI `dropDestination`, not driven); VoiceOver; a real unmounted external disk and the mount / unmount notifications; the sidebar with many collections or at other window sizes; a relocated item that is the live background (the layer keeps the asset id and the registry gets the new path through `onAssetsChange`; not run live); Hardware Verified and Live-Service Verified: Not Verified.
