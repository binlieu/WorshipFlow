# FIX-O report: the show state is observed one part at a time (KI-180)

Feature IDs UI (Show), SYS. Brief `AI/specs/FIX-O-show-state-observation.md`. Level: **Implemented, Unit Tested**, measured in the running debug build (replayed drags and model-driven gestures). Not Hardware Verified, not Live-Service Verified. No wall-clock assertions in the suite. No git state changed.

## Design chosen

Per-field observation behind the existing model's interface, not a rewrite of callers.

- `ObservedShow` (new, OperatorCore): a small class holding the `ShowState` value, with one `Observation` key per part (selected index, live index, nothing-live, live deck id, live deck, preview deck, Clear, Blackout, background cleared, "words on screen") and derived accessors (`liveSlide`, `liveSlideAtPlace`, `nextSlide`) that register only the parts they are made of. `set(_ newState)` compares old and new part by part and notifies only the parts that differ, so the value, `ShowState.apply` and what every command does are untouched. `WorkspaceModel.show` and `AppModel.show` remain (whole state, registers every part, so an unmigrated reader is coarse but never stale); `showParts` is the new door. `apply`, `onShowChange` (output publication) and undo are unchanged; `apply` now reads `showParts.current` (no registration).
- `ObservedSlideList`: `WorkspaceModel.slides` remains as the whole list; `slideList.count`, `.isEmpty`, `.order`, `.slide(at:)` notify on their own (one slide's words wake that slide's readers and the whole-list readers only; a position reader also depends on the order). `ObservedLayers`: `MediaModel.layers` remains; `layerParts.background` / `.foreground` notify separately.
- Why this and not separate `@Observable` holders: the model stays one object with one command path, callers keep compiling, and a missed migration is coarse, not wrong.
- Views changed to read parts: toolbar state tag (`ShowStateTag.text(isBlackedOut:isCleared:)`), TransportBar, MediaClearButtons, ShowInspector (Preview and Live monitors are views of their own so selection and mode draw them, not the inspector), the grid and list, Edit, Scripture, Cues, Library sidebar, media dock and bin. The grid gives `mode` to the live cell only (Blackout and Clear used to draw all 30 realised cells twice).
- Public interface of OperatorCore: **added** `ObservedShow`, `ObservedSlideList`, `ObservedLayers`, `WorkspaceModel.showParts`, `WorkspaceModel.slideList`, `MediaModel.layerParts`, `ShowStateTag.text(isBlackedOut:isCleared:)`. **Changed type of storage, same name and type**: `WorkspaceModel.show`, `.slides`, `MediaModel.layers` are now computed properties over the holders. Nothing removed; no caller outside the model had to change for correctness.

## Measurement (debug build, 200 slides, 100 bin items, this Mac)

Reused from FIX-M: the drag replay (`UISnapshotFixM.swift`, `scripts/measure-drags.sh`, `ReplayedDrag`, the stall ticker, `LibraryStore.commitCount`). New: `BodyProbe` (a counter in chosen view bodies), per-drop body counts in the replay line, a gesture block (`UI_SNAPSHOT_FIXO=1`: 5 runs each of selection, preview refresh, Next, Previous, Blackout, Clear then Go Live), `scripts/fixo-modes.sh`. "SlideGrid.content" is the grid's body closure; "SlideGridCell" the cells; a cell count is the cells drawn again.

Before = HEAD 8feab15 with only the probes and the new hook added (one run; its gestures use on-screen slides). After = final tree (two runs; the range is shown). Drop handler call = what runs before control returns.

| Gesture | Handler call before / after (ms) | Longest main-thread stall before / after (ms) | Bodies before | Bodies after |
|---|---|---|---|---|
| Slide reorder in the grid | 1.3 / 0.7 to 1.8 | 42 / 34 to 38 | ClearButtons, Inspector, Grid, 29 cells, 2 thumbnails, TransportBar, WorkspaceView (toolbar) | PreviewMonitor, Grid, 29 cells, 2 thumbnails |
| Bin tile onto a slide | 0.7 / 0.3 to 0.4 | 28 / 14 to 20 | the same set with 1 cell | Grid, 1 cell, 2 thumbnails |
| Finder file onto a slide | 2.5 / 1.8 to 1.9 | 23 / 14 to 20 | the same set with 1 cell | Grid, 1 cell, 2 thumbnails |
| Finder files onto the dock | 0.9 / 1.5 to 1.8 | 26 / 8 to 15 | the same set with 1 cell | Grid, 1 cell, 2 thumbnails |
| Bin tile onto a filmstrip cell (Edit) | 0.6 / 0.4 to 0.6 | 16 / 14 to 15 | thumbnails 2, WorkspaceView | thumbnails 2 |
| Playlist reorder (model call, list drag loop not replayable) | total 26 / 13 to 22 | 5.2 / 7.5 to 7.8 (noise) | not probed | not probed |
| Selection change (cell on screen) | 0.4 / 0.3 | 5.3 / 5.5 to 9.5 | ClearButtons, Inspector, Grid, 2 cells, TransportBar, WorkspaceView | PreviewMonitor, 2 cells, 1 thumbnail |
| Preview refresh, edit of an off-screen slide | 0.5 / 1.0 to 2.3 | 5.8 / 5.4 to 23 (first and 3rd of 5 runs) | ClearButtons, Inspector, Grid, TransportBar, WorkspaceView | Grid only |
| Preview refresh, edit of an on-screen slide | 0.7 / 1.0 to 1.6 | 741 on the first run (the new thumbnail is drawn for the first time, before and after), 13 to 19 / 12 to 19 | the same set with 1 cell | Grid, 1 cell, 1 thumbnail |
| Next | 33 / 23 to 34 (call) | 31 / 21 to 32 | ClearButtons, Inspector, Grid, 2 cells, TransportBar, WorkspaceView | ClearButtons, PreviewMonitor, Grid, 2 cells, TransportBar |
| Previous | 38 / 22 to 31 | 36 / 20 to 29 | as Next | as Next |
| Blackout on and off | (300 ms sleep inside) | 39 / 27 to 31 | ClearButtons x2, Inspector x2, Grid x2, **60 cells**, TransportBar x2, WorkspaceView x2 | LiveMonitor x2, ClearButtons x2, Grid x2, **2 cells**, TransportBar x2, WorkspaceView x2 |
| Clear then Go Live | (300 ms) | 48 / 40 | as Blackout | as Blackout plus ShowInspector x2 (the slim row appears and goes, a real change) |

The hover cost per update (median 2 to 3.5 ms, 95th under 8.5) and the commit and publication counts are as in FIX-M, before and after.

**Against the target.**
- Under 8 ms at the drop before control returns: **met** everywhere (handler 0.3 to 1.9 ms).
- A grid drop draws only the affected cells plus the target highlight: **met** for the cells (1 cell, or the 29 between for a reorder, which no keying avoids) and for every other view (toolbar, transport bar, clear icons, inspector, preview no longer draw on a drop of a bin tile, a file or on the dock). The grid's own body still runs once (it reads the slide list); it costs about 5 ms with 200 slides (off-screen edit row).
- Next draws two cells, the transport bar, the preview and the clear icons, not 200 cells: **met** for the views. **Not met**: Next and Previous still hold the main thread for 20 to 35 ms; it is inside the model call (publishing the scenes and starting players, `onShowChange`), which this task was told not to change (KI-187).
- The stall around a drop (FIX-M's measure) is still 8 to 38 ms (KI-186): the dropped cell's thumbnail, the grid body and SwiftUI's layout, not invalidation. A debug build only; a release build was not measured.
- Run to run noise is several ms (the 23 ms and 14 ms single runs in the off-screen edit row are such); before has one run, after two.

## Tests (new files `FIXO_*.swift`, 29 tests, written after the first implementation pass because the measurement came first)

`FIXO_ShowPartsTests` (each command notifies exactly the parts it changes: select, Next and Previous, preview refresh, Clear, Blackout, Clear background, lift, quick edit, Go Live, Stop, no-op commands, re-trigger; one tracker per part counted with `withObservationTracking`), `FIXO_SettledStateTests` (600 recorded commands replayed against the plain value and the observed parts: state, every part and derived accessor equal after each; a `set` that skips commands; the workspace's `apply` for 300 commands equals the value and publishes each change), `FIXO_SlideListTests`, `FIXO_LayerPartsTests`, `FIXO_WorkspacePartsTests` (through the real model: selection, typing into an inactive slide while live (Live unchanged), a slide reorder, Go Live, Next, a playlist reorder, Blackout and Clear), `FIXO_ViewSourceTests` (no view reads the whole state or layers for one part; the inspector's own body reads none of selection, live place, mode or slides; the grid gives the mode to the live cell only).

Seen failing first: against a copy of HEAD the file does not compile (`cannot find 'ObservedShow' in scope`, `value of type 'WorkspaceModel' has no member 'showParts'`; 364 and 130 such errors). Mutation check on the new code: making the preview-deck part always notify failed 6 tests (restored). Existing tests unchanged and passing.

## Driving the running app (KI-182 applies: the screen may be locked, no real clicks)

`scripts/fixo-modes.sh`: in each of Show, Edit, Media, Stage, Cues, Screens, through the model (the same calls the buttons make): Go Live, Next, Next, Previous, Blackout, Blackout, Clear, Go Live (lifts Clear), Clear background, Next, Blackout, Next (lifts), Stop; 78 steps. After each step the toolbar state tag (present only while Blackout or Clear is on) and the Blackout button's colour were compared with the model, and the mode's pixels with the same mode built fresh. Result: tag and button followed the model in **78 of 78**; the grid live marker, pills, inspector, preview, Stage and Screens panels showed no difference in 75 of 78 steps; 3 steps differed by 6 to 188 pixels inside live previews (inspector live monitor, Stage preview, Screens panel) and not in the same step in another mode (KI-188: not shown stale, not shown noise). The accessibility tree cannot be read by this hook (SwiftUI builds none unattended), so no label text was checked; a hand check of each mode is in the checklist.

## Files

New: `Packages/WorshipFlowKit/Sources/OperatorCore/ObservedShow.swift`, `ObservedSlideList.swift`, `ObservedLayers.swift`, `App/Sources/BodyProbe.swift`, `App/Sources/UISnapshotFixOModes.swift`, `scripts/fixo-modes.sh`, `FIXO_ObservationTests.swift`, `FIXO_ViewSourceTests.swift`. Changed: `WorkspaceModel.swift` and its extensions, `MediaModel.swift`, `MediaItemPlayback.swift`, `SlideEditorModel.swift`, `ShowStateTag.swift`, `AppModel.swift`, `CentrePane.swift`, `ShowInspector.swift`, `ContentView.swift`, `MediaClearButtons.swift`, `MediaBinPanel.swift`, `MediaDockView.swift`, `MediaStrip.swift`, `EditMode.swift`, `EditInspector.swift`, `ScriptureView.swift`, `CuesEditors.swift`, `CuesTab.swift`, `LibrarySidebar.swift`, `SlideObjectsEditor.swift`, `SlideGridCell.swift`, `Thumbnails.swift`, `TransportBar.swift`, `ShowMode.swift`, `UISnapshotFixM.swift`, `UISnapshotRun.swift` (one hook block), `scripts/measure-drags.sh`, `WORSHIPFLOW.xcodeproj/project.pbxproj` (xcodegen), `docs/16-known-issues.md` (KI-180 updated, KI-186 to 188), `docs/17-change-log.md`, `docs/hands-on-checklist.md`. Not touched: `docs/UI`, `docs/adr`, `AI/specs`, `Vendor`, `sdk`, `dist`, `.claude`, git state.

## Not verified

A release build's numbers, the real system drag and real clicks (KI-181, KI-182), label text of any view (VoiceOver), light mode, a view that reads a slide or layer coarsely (Edit, Cues, Scripture, the Edit filmstrip still draw on any slide change: correct, not narrowed), hardware.

## Checks

See the final message for the two `./scripts/check.sh` runs.
