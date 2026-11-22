# FIX-S report: KI-193 root cause, intermittent tests, build copies

Verification levels: Implemented, Unit Tested (new tests below), Simulated: not applicable. The crash was reproduced and the fix exercised in a Debug build driven through the app's own model calls (a debug hook in a scratch copy of the tree, never committed); the screen may have been locked, so nothing was clicked with a mouse. Hands-on: Not Verified (see `docs/hands-on-checklist.md`, section FIX-S).

## Item 1: KI-193

**Reproduced.** Scratch copy of the tree with the three guards of commit a0fa76c taken out. Library: `scripts/make-test-data.sh` data imported with `wf-test-data-import --create-library` into a scratch library (100 songs, 932 slides, 200 bin images). A scratch-only debug hook (not in the repository) opened presentations of different lengths through `WorkspaceModel.openPresentation`, and, following the owner's report, through `WorkspaceModel.openPlaylistItem` (what a click on a playlist row calls).

- Random opens (a 60-slide song and the 5 to 12 slide songs, random 0 to 300 ms between): trap in the first round.
- Playlist path: library song open, 3 s wait, playlist row clicked at 7.2 s after launch; the row's song had 5 slides, the open one 8: trap 11 ms after the click. Crash report: `Array.subscript.getter` <- `SlideGrid.cell(_:color:available:)` (`CentrePane.swift` 231) <- closure at 214 <- `ForEachChild.updateValue()`: the owner's stack.

**Cause (shown, not assumed).** A trace in the scratch build logged every body of the grid and every cell closure with what it had captured:

```
BODY grid: keys.count 12 first 6703D9      (the 12-slide song)
...        live slides become 8
BODY grid: keys.count 8 first 180832       (the new body, with the new 8 slides)
STALE closure: slot.index 8 captured keys.count 12 ... live slides.count 8 capturedFirstKey 6703D9
```

- The grid's body does run when the slide list is replaced (`ObservedSlideList.set` notifies `all`, which the body reads). It is not a missed invalidation, and the playlist path is the same as the library path: `install()` sets slides, groups, arrangements and group counts in one synchronous turn, so there is no two-step state (`FIXS_CellSlotTests.replacingTheListWithAShorterOneNotifiesTheReaderOfTheWholeList` shows the notification).
- After the new body has run, SwiftUI still runs the lazy `ForEach` closure of cells that are on their way out, built by the older body, with their old captured position. Each of those closures called `workspace.slides[i]` on the live list, which now has fewer slides. Only a longer-to-shorter replacement can trap (shorter-to-longer asks for positions that exist and is harmless). The grid, the list and the Edit film strip had the same shape.

**Fix.** `CellSlot` (`Packages/WorshipFlowKit/Sources/OperatorCore/CellSlot.swift`, moved there from the app) carries the cell's slide, key, position and `isLast`; `CellSlot(at:slides:keys:)` is nil beyond the list. `SlideGrid`, `SlideList` and the Edit film strip take one snapshot of `workspace.slides` in their body and build their cells from slots; no lazy closure reads the model's list by a position. The a0fa76c guards are gone because nothing is left to guard (the slot cannot be out of range). Cells in the list and film strip are now keyed by slide like the grid's (before: by position).

**After the fix**, the same driver, same build otherwise: 150 randomised rounds (including grid/list toggles and Edit mode) and 150 playlist clicks (14 playlist items: a long song, 10 library songs, 2 songs of the other library; presentations opened between): no crash, against a trap in round 1 before.

**Tests** (`FIXS_CellSlotTests`, 5): slot keeps its slide when the list is replaced; no slot beyond the list or for missing keys; repeated slide keeps two keys; the observation test above; a source test that no lazy closure of the grid, list or film strip indexes `workspace.slides` or checks `workspace.slides.indices` (run against the pre-fix source: fails with 10 issues; against the fix: passes). A lazy SwiftUI closure cannot be run by a unit test, so the crash itself is covered by the hook run, not by an automated test.

**Same class elsewhere** (grep for `[i]`, `[index]`, `[slot.index]` in `App/Sources`): `SlideEditor`, `EditInspector.slideTab` and `ShowInspector` index the live list in the same synchronous evaluation as their `indices.contains` check (safe). `PassageGrid` (Scripture), `CuesActionRow`, the segmented control and the mirror rows index a value captured with the loop (`let`), not the model (safe). The playlist `onMove` handler checks its index. Debug-only `UISnapshot*` code not changed.

Not measured: whether the slot snapshot changes the Release idle/Next numbers of FIX-Q (the grid body already read `slides`; cells still compare by value). Worth one `scripts/fixq-run.sh` pass.

## Item 2: intermittent tests

- (a) `pauseHoldsAndSeekMovesTheFrame` (KI-172): 30 runs alone (0.4 to 3.1 s, no failure), 4 full-package runs with one busy process per core (2.2 to 4.9 s), and a 200-iteration loop of the same play, pause, seek, seek-back sequence under that load (worst 0.26 s). Not reproduced; `VideoPlayerSource` reviewed for a lost wake-up (seek completion always decrements, rate applied when settled): none found. The only 62 s thing is the 60 s `TestMedia.wait` guard. Under load the sibling `aBrokenForegroundClipIsReportedPerAssetId` takes 20 to 52 s inside the package (0.09 s alone, 30 of 30), so AV-based waits come close to 60 s on a busy Mac. Changed `TestMedia.wait`'s guard to 180 s. This is a test-side change; no code defect was shown.
- (b) `anUnplugEndsTheRenderThread`: 50 runs under CPU load with `swift test --sanitize=thread` (builds; done in a scratch copy of the package so the main `.build` was not rebuilt): 50 of 50 pass, no ThreadSanitizer report. The OutputEngine, SDIEngine and DeckLinkSDI suites, 531 tests, once under the sanitizer and load: no race report (one benchmark assertion `< 200 ms` failed because the sanitizer makes it 8 times slower). The crash seen once is not reproduced or explained; no fix made.
- (c) `aBrokenForegroundClipIsReportedPerAssetId`: 30 of 30 pass alone; see (a). Same change.
- New, KI-195: `ScriptureLibraryTests.onlyTheNeededVersesAreReadFromTheLibrary`, `ToolProcessRunnerTests.aClientThatHangsIsStopped` (three of three loaded runs), `MIDIRouterTests` (twice in one run) fail under saturating load. Not changed (not authorised).

## Item 3

`FIXO_ViewSourceTests.theGridGivesTheModeToTheLiveCellOnly` now asserts: the cell takes `app.mode` only under its own live mark (`mode: live ? app.mode : .live`), holds no `mode`/`liveMode` input, the grid never passes `app.mode` and its code never reads it. The comment in `CentrePane.swift` stays: `FIXQ_ViewSourceTests.theGridsOwnBodyReadsNeitherTheSelectionTheLivePlaceNorTheMode` also asserts that sentence, and I may not edit that test. Removing it needs that one line deleted too (KI-196).

## Item 4

`scripts/check.sh` creates each derived-data folder it uses with `.metadata_never_index` before the build; `scripts/package-test-build.sh` does the same and removes the unzipped staging folder once the zip exists. The marker was also added by hand to the three existing derived-data folders. Result: with the marker only, `mdfind` still listed the Release and Debug apps of the check folders after a `check.sh` run (also after the folders were deleted and recreated with the marker first), so the scripts also delete what is not needed: `check.sh` removes its Release app (compile-only), the packaging script removes the Release app of its own folder and the unzipped staging folder (only the zip stays). The Debug app of the check folder stays because `docs/hands-on-checklist.md` opens it there; it remains listed by Spotlight (KI-196). A packaging run into a scratch folder left only the zip.

## Slip to report

Cleaning up a stuck test run I used `pkill -f swift-test` and `pkill -x yes`: these match by name, not by owner session, so a `swift test` started by another agent in the same login could have been stopped by them. Nothing was observed, but another session's test run that ended oddly around then should be rerun.
