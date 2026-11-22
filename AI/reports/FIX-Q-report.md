# FIX-Q report: Next, Previous and drops on the main thread (KI-186, KI-187, KI-189)

Feature IDs OUT, UI (Show), CUE, SYS. Brief `AI/specs/FIX-Q-next-and-drop-cost.md`. Level: **Implemented, Unit Tested**, and measured in the running app (Release measuring build and Debug build, replayed gestures and drops, this Mac, **the screen was locked for every run**). Not Hardware Verified, not Live-Service Verified. SDI paths are simulated only. No change to the output scheduler or the publication path. One public addition: `ObservedShow.isSelected(at:)` and `isLive(at:)`. No git state changed.

**Summary.** The targets for Next, Previous, drops and the 7 ms MIDI burst are **not met**. The model call and the publication were never the cost (0.2 to 0.5 ms; command to publication 0.3 to 0.9 ms, unchanged): a Next costs the main thread about 25 to 40 ms of SwiftUI updating and layout. FIX-Q found and removed one large systemic cost that every earlier measurement sat on top of (the Media controller row ticking ten times a second with nothing loaded: 15 to 19% of the main thread idle in Show, now 1%), narrowed the grid so it no longer runs its body on Next, fixed Next in Cues mode (45 to 15 ms), put the Release build into the gate, and made the timing hooks usable in a Release measuring build. Per-gesture cost in Show did not measurably fall.

## Per item

| Item | Done |
|---|---|
| 1 Release build in the gate | `scripts/check.sh` builds Release (compile only, `arch=arm64`, in its own derived-data folder, `<Debug folder>-release` or `WF_DERIVED_DATA_RELEASE`: in one shared folder each configuration rebuilt the packages for the other and the step took 150 s every run) after Debug, prints its duration, and fails if the Release binary contains `UI_SNAPSHOT_DIR` or `UI_SNAPSHOT_FIXQ`. `scripts/package-test-build.sh` makes the same check on the packaged app. The Release step took 179 s on a cold folder and 6 s on the next run (the whole check 281 s and 78 s); one shared folder had made it 150 s every run, so it has its own. |
| 2 Measure in Release first | Every hook `#if DEBUG` is now `#if DEBUG \|\| WF_MEASURE`. `WF_CONFIG=Release` in `scripts/fixq-run.sh`, `measure-drags.sh`, `fixp-run.sh` builds with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=WF_MEASURE` (`scripts/lib-measure-build.sh`). The design tags (`wfRect`) stay Debug-only, because a tag puts a GeometryReader and an NSView behind several views per slide cell, which slowed a first Release measuring build below the shipped app (found by comparing the sample). Proof the flag is off in the packaged app: the check's `strings` test, run on the Release binary built without the flag (below), and 32 `UI_SNAPSHOT` strings in the measuring binary against none in the packaged one. |
| 3 Next and Previous | Profiled (below). The causes were not in the model call, scene composition, text layout, preview or thumbnail renders, database reads or publication: none of those costs more than 0.1 ms per scene, and nothing there changed. What changed: the grid no longer runs its own body on Next, Previous or a selection (`ObservedShow.isSelected(at:)` / `isLive(at:)`, keyed observation; the cell reads its own marks; the scroll to the selection is a view of its own); the Cues slide-action list works out the chosen slide once and is lazy. Output content and order are unchanged, proved by digest. |
| 4 Drops | The dropped cell's thumbnail already renders off the main thread (`PreviewRenderer`'s queue) with the old picture shown until the new one lands; that was left. The grid's body already did not run for a change to one slide; it still runs when the bin changes (it reads the set of bin ids to mark missing media): a file onto the dock redraws the grid body once. The large finding for drops is KI-190 (below). Per-drop cost is still above the target. |
| 5 MIDI | Repeated in Release and Debug after the work (below). Coalescing was not added (not allowed for Next and Previous). KI-189 updated. |

## Where Next's time went (Release measuring build, 200 slides, 100 bin items)

- **Model and publication**: `PhaseProbe` around each step of `showChanged` and `publish`: show state 0.01 to 0.06 ms, media and audio 0.00 to 0.01, image warm (only schedules a task that waits 300 ms) 0.01, media sync 0.03, publication gate 0.02, scene composition for the screens 0.07 to 0.14, hand-over to the outputs 0.00, remote and stage 0.00. The awaited call that FIX-O measured at 20 to 35 ms in Debug is mostly the next display pass: the hook's `call` figure includes it; the work inside `apply` is under 0.5 ms. **Command to the new scene reaching the outputs: 0.3 to 0.9 ms, before and after.**
- **The window**: after the command, the main thread spends about 25 to 40 ms of CPU, in two or three run-loop passes (13 to 19 ms for the longest), in SwiftUI's attribute-graph update, layout and display. Seven view bodies run per Next (the clear icons, the preview monitor, two grid cells, one thumbnail, the transport bar). `sample` of 300 alternating Next and Previous: busy time is the display cycle (`NSHostingView.layout`, `ViewGraphRootValueUpdater.render`, `AG::Subgraph::update`), view bodies are a few percent.
- **Bisect by hiding parts of the Show window in the measuring build** (Next, CPU above idle per 0.7 s, medians of 12 runs): everything shown 37.8 ms; without the slide grid 27.2 (so the grid costs about 10.6 although its own body no longer runs); without the inspector 27.3 (its live monitor about 4, preview monitor and stage card each under 1); without the transport bar 34.8; scroll helper 1.6; grid, inspector, transport bar, sidebar and dock all hidden 7.4 (4.7 above idle).
- **By mode** (Next, CPU above idle, before): Stage 1, Media 6, Screens 10, Edit 15, Show 23 to 31, Cues 45. After: Cues 12.
- **The systemic cost**: idle in Show the main thread used 105 to 130 ms of CPU per 0.7 s (15 to 19%) and 84 to 90 ms in Media, with the heartbeat seeing a 16 to 18 ms stall ten times a second; Edit, Stage and Screens used 3 to 4 ms. Hiding the dock took Show to 7 ms. Cause: `MediaControllerRow` wrapped its content in `TimelineView(.periodic(by: 0.1))` even when no clip, sound or background video was loaded, and each tick made SwiftUI update the whole window. Fixed (`TickingWhile`, which ticks only while something is loaded; the row's source depends only on observed state, so it appears and the clock starts when one is chosen); the same in the Media mode's audio cue card and sound rows. Idle is now 3 to 7 ms in every mode.

## Before and after, Release measuring build (200 slides, 100 bin items; two runs each, an hour apart)

`burst` = the longest uninterrupted run of main-thread CPU in one run-loop pass, median of 20 runs (worst of the 20 in brackets for Next). `CPU+` = main-thread CPU above the idle run in the call and the 0.7 s after. `stall` = the 2 ms heartbeat's longest gap, median, **includes waits** (a locked screen makes a display commit wait for a frame: idle rows show 16 ms with no command; read only as "no worse than 16"). Target for Next and Previous: 8 ms median, 16 worst, on the main thread. All rows miss it.

| Gesture | burst before | burst after | CPU+ before | CPU+ after | stall before | stall after | command to publication before / after |
|---|---|---|---|---|---|---|---|
| Next | 12.9, 13.6 (worst 22.3, 23.4) | 17.5, 19.3 (worst 24.1, 30.1) | 31, 23 | 33, 38 | 16.6, 17.5 | 16.3, 17.5 | 0.6, 0.6 / 0.7, 0.8 ms |
| Previous | 12.3, 13.9 | 15.1, 20.3 | 29, 27 | 24, 37 | 17.8, 18.8 | 16.1, 20.0 | 0.7, 0.7 / 0.7, 0.7 |
| Next by key or MIDI (command path) | 12.8, 13.5 | 17.4, 19.3 | 30, 31 | 27, 33 | 18.1, 18.8 | 16.1, 19.6 | 0.7, 0.9 / 0.8, 0.8 |
| Go Live (a slide of the grid) | 9.3, 9.9 | 12.6, 17.3 | 30, 23 | 27, 43 | 9.6, 12.6 | 10.3, 14.9 | 0.4, 0.5 / 0.6, 0.7 |
| Blackout on | 18.7, 21.3 | 23.0, 23.6 | 30, 19 | 38, 38 | 19.3, 21.0 | 21.0, 21.0 | 0.3, 0.4 / 0.6, 0.6 |
| Blackout off | 17.7, 18.0 | 22.0, 24.4 | 26, 18 | 32, 40 | 18.8, 19.2 | 19.7, 22.5 | 0.4, 0.4 / 0.6, 0.6 |
| Clear | 20.1, 20.8 | 31.9, 34.6 | 30, 24 | 42, 47 | 29.3, 30.6 | 30.8, 34.0 | 0.3, 0.4 / 0.5, 0.5 |
| Go Live after Clear | 23.9, 22.7 | 33.0, 34.9 | 34, 23 | 45, 50 | 31.9, 31.9 | 32.7, 35.5 | 0.3, 0.4 / 0.4, 0.6 |
| Next in Cues | 45.1, 44.8 | 37.4 (lazy list not yet), 14.8 | 45, 44 | 36, 12 | 43.3, 43.0 | 35.6, 16.1 | |
| Next in Edit / Media / Stage / Screens | 12.3 / 5.8 / 0.5 / 4.1 | 15.5 / 10.3 / 0.5 / 4.7 | 15 / 6 / 1 / 11 | 19 / 12 / 0 / 19 | | | |
| Idle in Show, CPU per 0.7 s | 105, 130 | 6, 6 | | | | | |
| Idle in Media, CPU per 0.7 s | 90, 90 | 7, 7 | | | | | |

**Read these honestly.** After FIX-Q the Show-mode bursts are 1.3 to 2 times longer for the same CPU work, and so are the bursts of paths FIX-Q did not touch (Edit 12.3 to 15.5, Media, Screens), whose idle CPU also rose from 3 to 6 ms. The runs differ by the state of the machine (an idle process starts each burst on a cold core; not verified, KI-191). So **no claim is made that any gesture got faster or slower**; the claim is that the per-gesture cost did not fall measurably and that the steady cost did. Misses and causes: all rows above the 8 ms target; the cause is SwiftUI's update and layout of the 200-slide grid (about 10 ms), the inspector (about 10), the transport bar (about 3) and the remaining chrome (about 5) per command (KI-187). Blackout, Clear and Go Live after Clear are larger because they also change the live monitor, the toolbar tag, the clear icons and the live cell's ring and tag.

Debug build, 12 runs, one run each (the Debug build also draws the design tags): burst before / after in ms: Go Live 12.2 / 13.4, Next 15.3 / 17.9 (worst 21.9 / 28.3), Previous 14.6 / 15.8, Next by key 15.8 / 17.7, Blackout on 22.5 / 25.1, off 22.0 / 24.7, Clear 24.3 / 35.4, Go Live after Clear 27.0 / 38.4. Command to publication 0.7 to 1.2 ms before and after (FIX-O reported 20 to 35 ms in Debug for the whole call including the display pass). Same targets, same misses.

## Drops, Release measuring build (replayed through the window's real drag destinations; two runs each)

Per drop kind: handler call (what runs before control returns), `burst`, main-thread CPU in the 1.5 s from the drop (before includes the 220 ms of idle ticking in that window, after 4 ms), heartbeat stall (includes waits). Target: stall under 8 ms.

| Drop | call ms | burst before | burst after | CPU 1.5 s before | CPU 1.5 s after | stall before | stall after |
|---|---|---|---|---|---|---|---|
| Slide reorder in the grid | 0.9 to 1.5 | 21.6, 24.3 | 33.5, 43.8 | 294, 272 | 58, 70 | 28.8, 32.3 | 26.1, 35.3 |
| Bin tile onto a slide | 0.6 | 10.0, 11.8 | 15.8, 25.1 | 269, 292 | 44, 51 | 17.5, 19.9 | 14.5, 22.9 |
| Finder file onto a slide | 1.8 to 2.2 | 10.6, 8.9 | 16.6, 16.5 | 275, 273 | 56, 48 | 10.0, 10.4 | 15.1, 14.8 |
| Finder files onto the dock | 1.5 to 1.8 | 8.3, 8.1 | 20.1, 19.9 | 280, 291 | 52, 57 | 13.1, 6.9 | 20.3, 19.7 |
| Bin tile onto a filmstrip cell (Edit) | 0.5 to 0.6 | 14.0, 11.5 | 14.9, 15.8 | 40, 38 | 41, 44 | 11.4, 9.5 | 12.3, 13.2 |
| Finder files onto the bin (Media) | 1.7 to 1.9 | 3.8, 4.2 | 1.0, 2.2 | 198, 196 | 22, 20 | 4.4, 4.6 | 1.5, 1.1 |
| Slide index onto a filmstrip cell (refused) | 0.5 to 0.6 | 0.6 | 0.6 | 22 | 22 | 1.4 | 1.2 |
| Playlist reorder (model call; table drag not replayable) | 8 to 23 | | | | | 4 to 7 | 4 |

Debug, one run each, burst before / after: reorder 30.9 / 56.4, bin tile 11.5 / 29.0, Finder file 11.5 / 17.7, dock 10.6 / 17.9, filmstrip 18.1 / 16.6, bin 6.2 / 4.8. **Misses**: every drop that changes the grid or the dock is above the 8 ms target in both builds, and the bursts after FIX-Q are longer, not shorter (same caveat as above: the unchanged filmstrip row is within 1.3 times; the Show rows are 1.6 to 2.4 times, which is more than the machine noise seen elsewhere, so it may be real; not explained: KI-186, KI-191). What does not miss: hover (medians 2.2 to 3.4 ms; 95th 2.4 to 4.7 ms in the runs shown, 8.1 once before), the refused drop, the Media bin, the playlist reorder; and the main thread is busy 4 to 5% of the 1.5 s after a drop instead of 18 to 19%.

## MIDI

`FIXP=midi scripts/fixp-run.sh`, Release measuring build, 200-slide grid scrolled at 60 Hz, the 1080p59.94 clip playing, a Next per message: before: idle median 0.1 ms; a note every 32 ms median 2.8, 95th 13.9, worst 40.4 ms; a note every 7 ms (the hook's 5 ms gap plus 2 ms for the note-off) median 353.9, 95th 926.6, worst 935.3 ms, 138 of 200 over 200 ms. After, two runs: idle median 0.1; 32 ms: median 4.1 and 2.9, 95th 14.6 and 15.0, worst 36.5 and 38.5 (**target met**: median under 50, worst under 200); 7 ms: median 370.0 and 355.9, 95th 870.5 and 689.3, worst 882.4 and 701.2, 156 and 131 of 200 over 200 ms (**target missed**). Debug after: 32 ms median 6.6, 95th 25.6, worst 55.3; 7 ms median 998.8 ms, 159 of 200 had run when the run ended. Debug before is FIX-P's (32 ms median 2.5 to 9.8, worst 50 to 183; 7 ms median 1.1 to 1.2 s, about 105 of 200 run after 3 s). Cause of the remaining queue: a Next is about 30 ms of main-thread work (KI-187) and the stream asks for one per 7 ms; each press is a step, so there is no coalescing. Nothing is lost or reordered.

## Tests (new files `FIXQ_*.swift`; existing tests not edited)

- `FIXQ_MarksTests` (9): a Next, Previous, selection, Go Live or Stop wakes the readers of exactly the positions that gain or lose the mark and no other; Blackout, Clear, a background choice, a preview refresh and a quick edit wake none; the marks equal the whole state after every command of a 400-command recorded sequence. Written before the code (the first run compiled both); **not seen failing**: a mutation check was not run.
- `FIXQ_PublishedScenesDigestTests` (2): a fixed 42-command sequence replayed through the app's publication gate and `PublishedScenes` for an audience window, a stage window and a keyed broadcast screen (Fill and Key): the SHA-256 of every published scene in order, and the number of publications (29), recorded before the changes and unchanged after. Seen failing first against placeholder constants. It covers scenes, not pixels; the composition, publication and scheduler code is untouched (`git diff` is empty for `Domain`, `PublishedScenes.swift`, `LivePublication.swift`).
- `FIXQ_ViewSourceTests` (5): the grid's own body reads no selection, live place, mode or live deck; each cell asks for its own marks; the Cues list works out the chosen slide once; the media controller row, the cue card and the sound rows tick only while something plays; the publication contains no preview work and the preview warm-up waits first. Cache tests from the brief do not apply: no cache was added.
- The existing `FIXO_ViewSourceTests.theGridGivesTheModeToTheLiveCellOnly` asserts the text `mode: live == i ? liveMode : .live` in `CentrePane.swift`. The grid no longer says it (the cell decides the mode from its own live mark, same behaviour). That test could not be edited, so the sentence stays in the grid's comment. Say if you want the test updated instead.

## Driving the running app in every mode (Debug, `scripts/fixo-modes.sh`)

78 steps in Show, Edit, Media, Stage, Cues and Screens (Go Live, Next, Previous, Blackout twice, Clear, Go Live lifting Clear, Clear background, Next, Blackout, Next lifting it, Stop), each compared with a fresh build of the same mode: the toolbar state tag followed the model in **78 of 78** (checked against the log); the grid live marker, preview, live monitor, Stage and Screens panels showed no difference in 74 of 78 steps; 4 differed by 13, 272, 344 and 526 pixels (Show inspector live monitor, Stage preview and readout, a 6 pixel strip in Screens), the size and rate of the live-preview noise measured in KI-188 (3 of 78 before, 2 of 54 with nothing done). The screen was locked, so no click was real; the hands-on check is in the checklist.

## Gate

`./scripts/check.sh`, run 3 (cold Release folder): exit 0, 3,033 package tests in 480 suites passed (3,017 before, 16 new), domain boundary, project generation, Debug build, Release build (179 s) and the measuring-hook strings check passed; 281 s in all. Run 4 (final, warm): exit 0, 3,033 tests passed, Release step 6 s, 78 s in all. Two earlier runs during the work (runs 1 and 2, with one shared derived-data folder) also exited 0 with 3,033 tests. No timing-sensitive test failed in any run.

`scripts/package-test-build.sh` with `WF_PACKAGE_OUT` and `WF_PACKAGE_DERIVED_DATA` pointing at a scratch place: exit 0 (Release build, `codesign --verify`, the new measuring-hook strings check, zip). The packaged binary has 0 `UI_SNAPSHOT` strings; the measuring binary has 32. Nothing was written to `dist/`.

## Not verified, stopped short of

- Any hand-felt improvement: the screen was locked, so no real click, drag or scroll was made; every gesture and drop was driven through the model or the window's drag entry points (KI-181, KI-182).
- A Release measuring build is not the packaged app (it has the measuring hooks); the strings check proves the packaged one has none, not that the two run at the same speed.
- Why the Show bursts are longer after FIX-Q (core and clock state is a guess); an interleaved A, B, A, B run on an unlocked screen was not made.
- Next, Previous, Go Live, Blackout, Clear, every grid and dock drop and the 7 ms MIDI burst miss their targets (KI-186, KI-187, KI-189). The next step is in KI-187: make the cell, the preview and the live monitor cheaper to update.
- Edit mode (15 ms per Next): the filmstrip's cell is still a function in the parent's body; not narrowed.
- Real MIDI hardware, hardware, VoiceOver, light mode. Nothing in this task is Hardware Verified or Live-Service Verified.

## Files

New: `App/Sources/PhaseProbe.swift`, `App/Sources/UISnapshotFixQ.swift`, `scripts/fixq-run.sh`, `scripts/lib-measure-build.sh`, `FIXQ_MarksTests.swift`, `FIXQ_PublishedScenesDigestTests.swift`, `FIXQ_ViewSourceTests.swift`. Changed: `ObservedShow.swift`; `SlideGridCell.swift`, `CentrePane.swift`, `CuesEditors.swift`, `MediaDockView.swift`, `MediaAudioColumn.swift`, `AudioPanel.swift`, `WFControls.swift` (`TickingWhile`), `AppModel.swift` (`PhaseProbe` around the steps of `showChanged` and `publish`, empty in the packaged app); every `#if DEBUG` of the hooks (24 app files, `MIDIRouter`, `LibraryStore`, `SlideEditorModel`), `DesignProbe.swift`, `UISnapshotFixK.swift` (drop-target finder), `UISnapshotFixM.swift` (CPU and burst), `UISnapshotRun.swift` (one block), `scripts/check.sh`, `package-test-build.sh`, `measure-drags.sh`, `fixp-run.sh`, `WORSHIPFLOW.xcodeproj` (xcodegen). Docs: change log, known issues (KI-186, 187, 189 updated, 190 and 191 added), hands-on checklist. Not touched: `docs/UI`, `docs/adr`, `AI/specs`, `Vendor`, `sdk`, `dist`, `.claude`, git state.
