# FIX-M report: drag and drop that feels immediate

Feature IDs UI (Show, Edit, Media), LIB. Brief `AI/specs/FIX-M-drag-and-drop.md`. Level: **Implemented, Unit Tested**, and measured in the running debug build by replaying drag sessions. Not Hardware Verified, not Live-Service Verified. No wall-clock assertions in the suite.

## How the real drag session was measured

Synthetic mouse events cannot start AppKit's drag loop (FIX-K), so the debug hook `UI_SNAPSHOT_FIXM=1` (`App/Sources/UISnapshotFixM.swift`, run by `scripts/measure-drags.sh` against a temporary `--library` with `--silent-audio` and a copy of the app under a throw-away bundle id) feeds a replayed drag to the window's real drag destinations: it finds the `_PlatformDraggingDestinationView` SwiftUI registered under the pointer and calls `draggingEntered`, 24 x `draggingUpdated` (16 ms apart, moving across neighbouring cells), `prepareForDragOperation`, `performDragOperation`, `concludeDragOperation` with a pasteboard (a slide index, a bin tile's `wfmedia:` text, a Finder file URL). SwiftUI's own `dropDestination`, `isTargeted` and drop-handler code runs for each call. Counters: hover cost per update = time in the call plus how late the main thread woke; drop = the call's own time, the longest main-thread stall (2 ms heartbeat) around it, database commits (`LibraryStore.commitCount`) and output publications (`debugPublishCount`). 200 slides, 100 bin items, debug build, this Mac, a run takes about two minutes.

**Not measurable without a person** (KI-181): building the drag image when a drag starts, the system's cursor and auto-scroll loop, the playlist `List` drag loop (AppKit's table draws the insertion line; only the model call was timed), Finder as drag source. Owner's two-minute procedure (Terminal `sample`, or Instruments Animation Hitches) is in `docs/hands-on-checklist.md`, section FIX-M.

**Drag kinds that do not exist in the code** (read from the source, not measured): a song or a bin tile dragged into the playlist, a bin tile onto the dock's layer, files dropped on the playlist, slide reorder in the list or the Edit filmstrip (both have no drag source; the filmstrip only takes drops of a bin tile or a file; the filmstrip refuses a slide index), hot-folder items (not a drag: the folder is watched off the main thread, FIX-G, unchanged). Putting a song or tile in the playlist is the context menu's job.

## Before and after, per drag kind

Median / 95th / max (ms) per hover update over 25 updates; drop = longest main-thread stall around it. Before = commit 0c42374; after = the final tree (three runs, range given; run to run noise is a few ms). Output publications 0 and commits during hover 0 in every row, before and after.

| Drag kind | Hover before | Hover after | Drop stall before (ms) | Drop stall after (ms) | Commits at the drop before / after |
|---|---|---|---|---|---|
| Slide reorder in the grid | 3.1 / 4.0 / 7.7 | 2.9 to 3.2 / 4.3 to 7.0 / 6.6 to 8.6 | 35.7 | 38 to 42 | 2 (last at 560 ms) / 1 (at 55 ms) |
| Bin tile onto a slide in the grid | 3.3 / 3.8 / 5.0 | 3.4 to 3.5 / 5.6 to 6.3 / 6.3 to 8.6 | 34.9 | 26 to 29 | 0 within 1.5 s (editor debounce) / same |
| Finder file onto a slide in the grid | 3.2 / 6.1 / 7.6 | 3.2 / 5.2 to 6.9 / 6.1 to 8.2 | 26.5 | 24 to 29 | 1 / 1 |
| Finder files onto the dock | 2.2 / 6.3 / 8.1 | 2.2 / 4.9 / 5.6 to 6.5 | 24.2 | 19 to 21 | 1 / 1 |
| Playlist reorder (model call; list drag loop not replayable) | not replayable | not replayable | 22.2 (call 25 ms) | 4 to 6 (call 25 to 28 ms, awaited off the screen) | 1 / 1 |
| Bin tile onto a filmstrip cell (Edit) | 2.4 / 3.0 / 3.0 | 2.4 to 2.7 / 2.9 / 2.9 | 15.5 | 12.6 to 13.5 | 0 / 0 |
| Slide index onto a filmstrip cell (refused) | 2.9 / 3.3 / 3.4 | 2.5 to 2.9 / 3.0 / 3.2 | 1.6 | 1.8 to 1.9 | 0 / 0 |
| Finder file onto the bin (Media) | 2.1 / 4.2 / 7.1 | 2.2 / 3.4 to 3.6 / 3.6 to 4.8 | 5.5 | 5.8 to 6.1 | 1 / 1 |

The drop handler call itself (what runs before control returns) is 0.5 to 2.5 ms everywhere, before and after.

**Target (8 ms per hover update; 8 ms at the drop).** Hover: met at the 95th percentile everywhere; a single update in 25 reached 8.0 to 8.6 ms in three runs of the grid and the dock (the first update after the pointer enters a view). The drop's stall: met for the playlist reorder (5 ms), the Finder file onto the bin (6 ms) and the refused drop; **not met** for the grid drops (slide reorder about 40 ms, tile or file onto a slide 24 to 29 ms), the dock (20 ms) and the filmstrip (13 ms) in a debug build. A release build is not measurable with this hook (it is `#if DEBUG`).

## What was found and changed

1. **Reorders now show first and write afterwards** (`OptimisticOrder.swift`: `OrderMove`, `ReorderTracker`; `WorkspaceModel.moveSlide`, `movePlaylistItem`). The visible array is moved by stable identity and renumbered, the preview deck follows, then one write runs on a chain in arrival order through `slideMoveWriter` / `playlistMoveWriter` (a test seam, default the store's own write). A failed write puts the order the library holds back and says "Could not move the slide/item: ..."; drops queued behind a failure are rolled back and never written. If the chain ends and the screen differs from the library, the model reloads. Before, a slide reorder flushed drafts, wrote, then re-read all 200 slides and rebuilt the grid (2 commits: the move and the saved place); now 1 commit, no reload. The playlist reorder no longer reloads every item's slides: 22 to 5 ms.
2. **Slide grid** (`SlideGridCell.swift`, `CentrePane.swift`): cells keyed by `SlideCellKey` (slide id plus occurrence, so an arrangement that repeats a slide stays unique) instead of by position, `SlideGridCell` compares by value (`.equatable()`), and the per-cell `Set` of bin ids and the live index are computed once per grid body. A single changed slide now draws one cell.
3. **Drag images** are small labels (`DragChip`, `.draggable(payload) { DragChip(...) }`) for slide cells and bin and dock tiles, built when the drag starts, never the cell's view hierarchy. Not measurable without a hand (KI-181).
4. **Drop highlight** of the bin and the dock is `FileDropTarget`, a modifier with its own `@State`, so hover changes one overlay and the panels' contents (the 100-tile bin) are not re-evaluated. Grid and filmstrip cells have no hover state at all.
5. **File drops**: bookmarks are made on a background thread (`MediaAccess.bookmarks(for:)`), and drops are handled one after the other in arrival order (`AppModel.mediaAddTail`) for the bin, the dock and a slide. Probing and the library write were already off the main thread. File contents are never read on the main thread.
6. **Why the grid drops still stall** (KI-180, from `sample` profiles of 120 repeated drops): the time is SwiftUI updating the whole window, not the drop's work. `WorkspaceModel.show` is one observed value, so a refresh of the preview deck (every slide edit and every reorder) re-evaluates every view that reads any part of `show`: the grid, the transport bar, the inspector. A reorder also changes what every visible cell shows. Splitting that observation touches most views; left as KI-180.
7. Nothing in a drop publishes to an output (publications 0 in every row); a drop edits, never goes live (tested: live deck and index unchanged across reorders).

## Tests (new files `FIXM_*.swift`; 17 tests, written before the code)

`FIXM_OrderTests` (move and clamp, the dirty range equals exactly the positions that changed, restoring by identity, cell identities: the set is unchanged by a reorder, nothing outside the range changes, repeated slides stay distinct; the tracker), `FIXM_DropModelTests` (visible at once while the write is held, exactly one commit, quick successive drops write in arrival order and the library ends as the screen shows, a failed write restores the order with the message, a drop queued behind a failure is rolled back and never written, Live unchanged, playlist drop and failure, an unknown slide writes nothing), `FIXM_DropSourceTests` (every `.draggable` gives a `DragChip`; the bin and dock keep no hover state; bookmarks off the main thread and queued; the grid keyed by `CellSlot` and equatable; grid and filmstrip cells have no `isTargeted`).
Seen failing first: `swift test --filter FIXM_` did not compile against the old tree (`cannot find 'OrderMove' in scope` and the other new symbols: `ReorderTracker`, `SlideCellKey`, `slideMoveWriter`, `playlistMoveWriter`); the source guards' conditions were checked against `git show HEAD:` of the files (isTargeted 1 and 1, `.draggable(` without a label in `CentrePane.swift` and `MediaBinPanel.swift`, `MediaAccess.bookmark(for:)` 2 times in `AppModel.swift`, `ForEach(run.indices, id: \.self)` in the grid). An early run of the model tests hung because my gate released only the writes already waiting (fixed in the test: the gate stays open). Existing tests unchanged; the existing FIX-K "at most two commits" test still holds (now one).

## Files

New: `Packages/WorshipFlowKit/Sources/OperatorCore/OptimisticOrder.swift`, `App/Sources/SlideGridCell.swift`, `App/Sources/UISnapshotFixM.swift`, `scripts/measure-drags.sh`, the three `FIXM_*` test files. Changed: `WorkspaceModel.swift`, `WorkspaceModel+Editing.swift`, `WorkspaceModel+Playlists.swift`, `CentrePane.swift`, `MediaBinPanel.swift`, `MediaDockView.swift`, `MediaSupport.swift`, `AppModel.swift`, `UISnapshotRun.swift` (one hook block), `WORSHIPFLOW.xcodeproj/project.pbxproj` (xcodegen), `docs/16-known-issues.md` (KI-168 updated, KI-180, KI-181), `docs/17-change-log.md`, `docs/hands-on-checklist.md`. Not touched: `docs/UI`, `docs/adr`, `AI/specs`, `Vendor`, `sdk`, `dist`, `.claude`, git state.

## Not verified

The real system drag (image, hover loop, auto-scroll), the playlist `List` drag loop, Finder as source, VoiceOver on the new drag labels, light mode, a release build's numbers, the filmstrip cell (not made value-comparing; 13 ms), hardware (none).

## Check

`./scripts/check.sh` (2895 tests in 453 suites): run 1 exit 0; run 2 exit 1 on `MediaAvailabilityTests.aBrokenForegroundClipIsReportedPerAssetId` ("Expectation failed: told", after 64 s, a media-player wait in the family of KI-172; none of this task's files are involved; not reproduced); run 3 exit 0. An earlier run failed once on my own source test string (fixed).
