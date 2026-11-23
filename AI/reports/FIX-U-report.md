# FIX-U report: the Show window's update after a command (KI-186, KI-187, KI-189, KI-192)

Feature IDs UI (Show), SYS. Brief `AI/specs/FIX-U-show-window-update-cost.md`. Model: Sonnet. Level: **Implemented, Unit Tested** (three source-rule tests), measured in the running app (Release measuring build, 200 slides, 100 bin items, replayed commands, this Mac, **the screen was locked and the operator window not visible for every run**). Not Hardware Verified, not Live-Service Verified. No migration, no behaviour change, no change to `Domain`, `Persistence`, the scheduler or the publication (`FIXQ_PublishedScenesDigestTests` passes without edits).

**Summary.** Three changes are kept: the toolbar's Blackout / Cleared word, the Show inspector's pinned row and the transport bar's text block are each a view of their own, so Blackout, Clear and a Go Live that lifts one no longer run the body of the whole window (`WorkspaceView`) or of the whole inspector, and Next no longer runs the transport bar's buttons. Interleaved A/B, 9 rounds (6 quiet, 3 loaded): the longest main-thread burst falls from 25.0 to 19.4 ms for Clear, 26.6 to 21.5 for Go Live after Clear, 13.7 to 11.0 for Blackout, 8.4 to 6.9 for Next by key or MIDI; nothing is measurably worse. Two further candidates were measured and **rolled back** (the inspector's monitors as stacks instead of a `Grid`; skipping the scroll to a selection that is already on screen). **Targets are not all met**: Clear (19 ms) and Go Live after Clear (21 ms) still miss 16 ms worst; Next sits at the 8 ms median on a quiet machine and 15 on a loaded one; the 7 ms MIDI burst still queues. See "Targets" and "Not verified".

## Profile: where the update after a command goes

Method: `sample` of the app running 1000 alternating Next/Previous (60 ms apart) and Clear/Go Live commands, plus subtraction by hiding parts of the Show window (a measuring-only `FIXU_HIDE` switch, not committed: `grid, inspector, transport, dock`, then the inspector's `monitors, preview, live, cards, tabs`), each variant launched 3 times, interleaved. `xctrace` could not attach to the ad-hoc signed measuring app (also not with `get-task-allow`), so the SwiftUI and Time Profiler templates were not usable; the call tree of `sample` has no view-body symbols (they are inlined into SwiftUI's generics), so which bodies run comes from `BodyProbe` and the cost of a part from hiding it.

- **Not the model and not the publication**, as FIX-Q found: command to publication 0.2 to 0.7 ms in every run (`PhaseProbe`).
- **Steady state vs after a pause.** Back to back (60 ms apart, `sample`, warm) a Next costs the main thread **3.5 ms** (471 busy samples of 1 ms for 133 commands); the 500 ms pause the gesture runner leaves before each command makes the same Next burst 8 ms (quiet machine) to 15 ms (loaded one). So the "update cost" in the burst metric is largely the cost of a cold core, as FIX-R found for the idle tick (KI-191); only the work itself can be reduced here.
- **Inside the update** (Next loop, 471 busy samples): 51% the attribute graph's update (`GraphHost.flushTransactions`, `AG::Subgraph::update`), about 21% `NSHostingView.layout` / `render` (inside the Core Animation commit), 14% of the total in `_LazyLayoutViewCache.withPlacementData` (the lazy grid placing its cells), view bodies a few percent. Clear/Go Live loop (1883 busy samples): 49% graph update, 20% layout. The graph's own bookkeeping (`UpdateStack::update`, `propagate_dirty`) is the largest self time.
- **Which bodies run** (`BodyProbe`, per command). Before: Next: `MediaClearButtons`, `PreviewMonitor`, 2 or 3 `SlideGridCell`, `SlideThumbnail`, `TransportBar`; Blackout: `LiveMonitor`, `MediaClearButtons`, `TransportBar`, **`WorkspaceView`**; Clear and Go Live after Clear: those plus **`ShowInspector`** and one cell. After: no `WorkspaceView` and no `ShowInspector` body on any of them; `ToolbarStateTag`, `ShowSlimRow` (Clear only) and `TransportText` take their place and are small.
- **By part** (hide one part, CPU of the call and the 0.7 s after / longest burst, ms, loaded machine, medians of 3 launches; full = everything shown, all = all five regions hidden):

| | full | no grid | no inspector | no transport | no dock | all hidden |
|---|---|---|---|---|---|---|
| Next, CPU / burst | 34.4 / 14.8 | 25.9 / 9.6 | 22.3 / 11.9 | 32.5 / 12.7 | 37.3 / 16.9 | 10.8 / 0.5 |
| Clear, CPU / burst | 44.5 / 24.9 | 34.7 / 17.2 | 25.2 / 15.6 | 44.0 / 25.0 | 42.7 / 26.3 | 13.3 / 5.5 |
| Go Live after Clear | 48.6 / 29.3 | 31.0 / 19.8 | 27.8 / 17.8 | 44.1 / 24.4 | 45.7 / 28.3 | 7.6 / 4.0 |

  The inspector and the grid are the two big parts (about 12 and 8 of Next's 34 CPU ms, 19 and 10 of Clear's 44); the transport bar 2 for Next and nothing for Clear; the dock nothing measurable. (This table was taken on the tree with U1 to U3 applied, the `hide` builds were made from it.) Inside the inspector (Next / Clear CPU; full 35.6 / 45.0): all monitors hidden 23.6 / 33.7; Preview monitor alone 32.8 / 44.0; Live monitor alone 35.5 / 41.5; the other screens' cards 33.6 / 40.8; the tab area 36.1 / 44.9. The monitors as a block cost 12 and the parts add up to 5: most of it is the monitors' container and layout, not a picture.
- **A scroll helper costs 4 ms of a Next.** `ScrollToSelection` calls `proxy.scrollTo` on every selection change, animated. Without the call: Next burst −4.1 ms (4 of 4 rounds), CPU −5.7; Previous −1.2. Without the animation but with the call (`proxy.scrollTo` alone): **+5 to +6 ms on every gesture**, so the animated call must stay. Not fixed: see "Rolled back".

## The changes and their A/B

Method: Release measuring build (`WF_CONFIG=Release`, `WF_MEASURE`, `scripts/fixq-run.sh`'s gestures through `UISnapshotFixQ`), 200 slides, 100 bin items, a temporary library, `--silent-audio`. Each round launches every variant once (4 runs per gesture per launch) in a rotated order; the numbers are the median over rounds of each launch's median, and "paired" is the difference inside one round (same minutes), with how many rounds the variant was better. Between hours the machine drifted by up to 2 times (Next 8.7 ms in the first batches, 15 ms in the last: another agent builds in the main checkout), so only numbers from one table are comparable. The noise floor of a launch's median is 0.5 to 2 ms (burst), CPU 1 to 3 ms; a variant's min..max over rounds is in `AI/reports` scratch only (deleted), the gap in the table is read against that.

| Change | Files | Paired burst, B − A (rounds better) | Decision |
|---|---|---|---|
| **U1** toolbar state word `ToolbarStateTag` (was read by `WorkspaceView`, so Blackout, Clear and Go Live after Clear rebuilt the toolbar, the mode, the transport bar and the sheets) | `ContentView.swift` | base → U1, 6 rounds: Blackout on −1.4 (5), off −1.7 (6), Clear −1.5 (5), Go Live after Clear −1.0 (5); Next +0.2 (2), Previous +0.4 (1), Go Live +0.2 (1): inside the noise floor, not worse | **Kept** |
| **U2** pinned row `ShowSlimRow` (`hasLiveWords` made `ShowInspector` rebuild the monitors, Looks, tabs and stage message on every Clear) | `ShowSlimRow.swift` (new), `ShowInspector.swift` | U1 → U1+U2: Clear −2.2 (5), Go Live after Clear −2.6 (5), Previous −0.5 (5), Next by key −0.7 (6), Previous by key −0.8 (5), Blackout −0.8/−0.4; others ±0.5 | **Kept** |
| **U3** `TransportText` (badge, headline, detail: the words change on every Next, the buttons do not) | `TransportBar.swift` | U1+U2 → +U3: Clear −3.1 (5), Next −1.2 (4), Next by key −0.5 (5), Previous by key −0.7 (6), Previous −0.5 (5), Go Live −0.3 (4), Blackout on −0.4; Blackout off −0.1, Go Live after Clear −0.8 | **Kept**, with a layout fix (below) |
| U3 fix `fixedSize` on `TransportText` | `TransportBar.swift` | found by the rectangle comparison, not by timing: as one child of the bar the badge was squeezed from 45.7 to 18 pt and the text moved 27 pt left. With `.fixedSize(horizontal: true, vertical: false)` the rectangles are identical to the base. A/B of the fixed build against U1+U2+U3, 4 rounds: Go Live −0.8 (4), Next −1.0 (3), Previous −0.2 (3), Next by key −0.8 (3), Previous by key −1.1 (2), Blackout on −0.3 (2), off −1.0 (3), Clear −2.0 (2), Go Live after Clear 0.0 (2): not worse | **Kept** |
| M1 the inspector's monitors as `VStack`/`HStack` instead of a `Grid` (the "monitors" block costs 12 ms CPU, the parts 5) | `ShowInspector.swift` | vs U1+U2+U3, 6 rounds: burst Go Live +0.2 (2), Next +0.2 (1), Previous −0.4 (4), Next by key 0.0, Previous by key −0.1, Blackout on −1.2 (4), off +0.1, Clear +0.5 (3), Go Live after Clear +0.8 (3); CPU +0.1 to +1.3 on most | **Rolled back**: no measurable difference, so the `Grid` is not the cost. Never committed |
| S1 skip the scroll when the selected cell is fully on screen (cells report `onScrollVisibilityChange(threshold: 0.99)` into an unobserved set; the helper reads it) | `CentrePane.swift` | vs U1+U2+U3, 6 rounds: Next burst +0.2 (3 of 6 better), Previous −0.9 (4), Next by key 0.0 (3), Clear +1.3 (1), Go Live after Clear −1.1 (5); CPU Previous by key +1.8 (0 of 6), Blackout off +2.2 (0 of 6) | **Rolled back**: no gain where the diagnostic says 4 ms (the visible set is probably not filled in the lazy grid inside a lazy stack, not investigated) and slightly worse CPU. Never committed |

The rolled-back diagnostics (`FIXU_HIDE`, `ShowMeasureHide.swift`) were builds in a scratch folder only.

Cumulative, base against U1+U2+U3 (6 quiet rounds, medians of launch medians; the machine in its quiet state), burst ms:

| Gesture | base | final | paired (9 rounds incl. 3 loaded) |
|---|---|---|---|
| Go Live (a slide of the grid) | 5.7 | 5.6 | −0.2 (5 of 9) |
| Next | 8.7 | 8.2 | −0.5 (7 of 9) |
| Previous | 7.8 | 7.5 | −0.9 (7 of 9) |
| Next by key or MIDI | 8.4 | 6.9 | −1.5 (9 of 9) |
| Previous by key | 8.4 | 6.5 | −1.4 (8 of 9) |
| Blackout on | 13.7 | 11.0 | −2.3 (9 of 9) |
| Blackout off | 13.3 | 10.9 | −2.1 (8 of 9) |
| Clear | 25.0 | 19.4 | −4.0 (8 of 9) |
| Go Live after Clear | 26.6 | 21.5 | −3.8 (7 of 9) |

Main-thread CPU in the call and the 0.7 s after, base → final (quiet rounds): Go Live 19.4 → 18.6, Next 24.1 → 26.0 (ranges overlap, paired over 9 rounds −2.1), Previous 23.5 → 23.1, Next by key 24.4 → 18.6, Previous by key 24.5 → 17.8, Blackout on 27.6 → 21.5, off 27.4 → 21.8, Clear 39.8 → 30.8, Go Live after Clear 41.3 → 33.8. Worst single run of the 24 per gesture (burst): Next 15.7 → 14.3, Previous 9.9 → 9.8, Blackout 16.3 → 13.4 / 14.9 → 15.2, Clear 28.2 → 22.0, Go Live after Clear 27.4 → **30.2** (one run; its median fell and 7 of 9 rounds improved).

## Targets (8 ms median and 16 ms worst of the main-thread burst, Next and Previous; the same bar is applied to the others)

| Gesture | base quiet (median / worst) | final quiet | final loaded machine (3 rounds) | Met? |
|---|---|---|---|---|
| Next | 8.7 / 15.7 | 8.2 / 14.3 | 15.0 / 20.4 | median **just missed** (8.2 against 8) when quiet, missed when loaded; worst met when quiet |
| Previous | 7.8 / 9.9 | 7.5 / 9.8 | 12.9 / 16.1 | met when quiet |
| Go Live | 5.7 / 10.2 | 5.6 / 10.0 | 11.4 / 18.2 | met when quiet |
| Next / Previous by key or MIDI | 8.4 / 11.8, 8.4 / 9.3 | 6.9 / 9.3, 6.5 / 10.3 | 13.6 / 15.7, 13.4 / 16.0 | met when quiet |
| Blackout on / off | 13.7 / 16.3, 13.3 / 14.9 | 11.0 / 13.4, 10.9 / 15.2 | 16.9 / 22.6, 16.5 / 19.8 | missed (median), worst met when quiet |
| Clear | 25.0 / 28.2 | 19.4 / 22.0 | 25.5 / 30.6 | **missed** |
| Go Live after Clear | 26.6 / 27.4 | 21.5 / 30.2 | 28.6 / 33.2 | **missed** |
| Idle in Show, CPU per 0.7 s (loaded machine) | 9.9 (8.6 to 10.0) | 10.0 (9.9 to 10.0) | | same; 3.5 in Media against 3.3 to 3.9 (a first base launch read 10.7); nothing ticks while idle |
| Drop kinds, burst / CPU in 1.5 s, 3 launches each (base / final): slide reorder 39.7 / 67 and 40.0 / 66; bin tile onto a slide 16.9 / 56 and 16.4 / 50; Finder file onto a slide 17.1 / 52 and 14.7 / 46; files onto the dock 15.8 / 46 and 15.7 / 47; bin tile onto a filmstrip cell 16.5 / 50 and 15.8 / 47; refused drop 6.2 / 32 and 6.0 / 31; files onto the bin 1.9 / 22 and 1.8 / 24 | | | | unchanged (not touched), still above 8 ms except the Media bin and the refused drop (KI-186 open) |

Why Clear and Go Live after Clear still miss: they change the toolbar word, the pinned row's existence (the inspector's scroll area changes height), the transport badge and text width, the Live monitor's badge and ring, and the live cell: more layout than Next. The inspector's monitors still account for most of the remaining inspector cost (12 ms CPU of Next for a container whose children add up to 5) and the grid for about 8 to 10; neither was reduced here (the `Grid` swap and the scroll skip did not help). The 8 ms median on Next also depends on the machine: the same Release build read 8.7 ms in the quiet first batches and 15 ms in the last, and a Next 60 ms after another costs 3.5 ms.

**MIDI, one message every 7 ms under load** (the hook sends 5 ms apart plus 2 ms for the note-off; `fixp-run` equivalent: `UI_SNAPSHOT_FIXP=midi`, 200-slide grid scrolling at 60 Hz, a 1080p59.94 clip playing, a Next per message; 2 launches each, interleaved): base median 80.9 and 179.2 ms, 95th 350.4 and 434.8, worst 375.1 and 444.7, over 200 ms 62 and 90 of 200; final median 82.9 and 65.5, 95th 284.1 and 289.2, worst 302.8 and 309.5, over 200 ms 59 and 63. **Target (median under 50, worst under 200) not met**; the worst and the 95th fell about 20%. Nothing was lost (200 of 200 ran, live slide 200 of 200). One message every 32 ms: median 2.6 to 3.1 (base) and 2.6 to 3.2 (final), worst 29.8 and 33.9 against 27.8 and 19.8: met. No coalescing of Next or Previous. Real MIDI hardware was not measured.

**Rectangle comparison for Show** (`UI_PREFIX=FIXU scripts/design-capture.sh`, `scripts/compare-rects.py` with `scripts/design-map-show.json`, Debug build, run at the base commit and at the final tree): **identical** per element (`--all --bad --rects` output diffed: no line differs). In this environment both give 32 of 220 mapped elements within 1 pt (toolbar 16, transport 16; sidebar, centre, dock and inspector 0), not the 205 of 242 that UI-005j recorded: the capture window is not the size the mapping was made at on this Mac and the screen is locked; this was not investigated, and it is the same before and after. Before the `fixedSize` fix the transport region read 15 and the badge was 18 pt wide.

## Tests

`FIXU_ViewSourceTests` (3, new): `WorkspaceView`'s own body reads neither hold nor the show parts and `ToolbarStateTag` does (and the sentence `FIXO_ViewSourceTests` asserts is still in `ContentView.swift`); `ShowInspector`'s body does not decide whether the pinned row shows and `ShowSlimRow` does; `TransportBar`'s own body reads no words, mode, `livePositionLine` or text measurement and keeps `TransportText` at its own width (`fixedSize`). Written with the changes, not before them (they pin a structure, not logic); not mutation checked. No wall-clock assertion. **No source-rule test conflicted** with a kept change: `FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests`, `FIXK_ToolbarTests`, `FIXP_CanvasSourceTests` and `FIXQ_PublishedScenesDigestTests` passed unedited. The rolled-back S1 had also kept them passing (not run).

## Gate

`WF_DERIVED_DATA=<scratch> ./scripts/check.sh` on the final tree (with the `fixedSize` fix): exit 0; package tests 3,199 in 514 suites passed (3,196 at the base, 3 new); domain boundary, project generation, Debug build, Release build (187 s, cold folder) and the measuring-hook strings check passed. Run once. No timing-sensitive test failed. The suites that pin the grid, cell, toolbar and inspector source and the published-scenes digest were also run on their own earlier (27 tests, passed).

## Known issues (unnumbered, for the coordinator)

- KI-187 update: the model call and publication are 0.2 to 0.7 ms; a Next back to back costs 3.5 ms of main thread and 8 to 15 ms after a pause; the inspector (about 12 of 34 CPU ms) and the grid (about 8) are the two large parts and the transport bar 2; the dock none. Clear and Go Live after Clear dropped from 25 to 19 and 27 to 21 ms but still miss 16 ms. Open.
- KI-189 update: 7 ms MIDI burst worst 375 and 445 → 303 and 310 ms, median 81 and 179 → 83 and 66; target not met. Open.
- New: `ScrollToSelection` calls `proxy.scrollTo` on every selection change; it costs about 4 ms of a Next (without it: burst −4.1 ms, CPU −5.7), and removing the animation makes every gesture 5 to 6 ms slower. Skipping it for a cell already on screen through `onScrollVisibilityChange` did not help in the lazy grid (S1). A working skip would need the first row and the row height, or `ScrollPosition`. Open.
- New: the inspector's monitors block costs 12 ms CPU on Next where Preview, Live and the cards add up to 5; replacing its `Grid` by stacks changes nothing (M1). The remainder is the container's layout; not found.
- New: `xctrace` cannot attach to the ad-hoc signed measuring app on this Mac (also with the `get-task-allow` entitlement), so SwiftUI/Time Profiler templates could not be used; `sample` plus `BodyProbe` plus hiding parts replaced them.
- The layout trap found: moving a part of an `HStack`'s children into a view of their own can make the stack treat it as one flexible child and squeeze its first member; `compare-rects.py` caught it (U3). Any later split of the transport bar, the toolbar or the dock header should be checked the same way.
- FIX-R/FIX-Q measuring caveats (KI-191) stand: locked screen, window not visible, drift between hours.

## Hands-on checklist entries (for `docs/hands-on-checklist.md`, FIX-U)

- [ ] Show, with a song live: press Escape (Clear), then Return on a slide, then B twice (Blackout on and off): the amber word in the toolbar appears with Cleared and Blackout and goes away when lifted; the pinned "Edit live slide" row at the bottom of the right column is there while words are live and goes away on Clear; the transport bar's badge and text change with each; nothing is cut or moved (the LIVE badge keeps its width and the headline starts 10 pt after it).
- [ ] Next, Previous and a click on a far slide still scroll the grid to the selection when it is off screen.
- [ ] Feel: Clear, Blackout and Go Live after Clear on a 200-slide song with the real screen unlocked; the report's numbers come from a locked screen.

## Change log entry (for `docs/17-change-log.md`)

- FIX-U: the toolbar's Blackout/Cleared word (`ToolbarStateTag`), the Show inspector's pinned row (`ShowSlimRow`) and the transport bar's badge and text (`TransportText`, at its own width) are views of their own, so Blackout, Clear and a Go Live that lifts one no longer run the window's or the inspector's body and Next no longer runs the transport bar's buttons. Interleaved A/B (Release measuring build, 200 slides): burst Clear 25.0 → 19.4 ms, Go Live after Clear 26.6 → 21.5, Blackout 13.7 → 11.0, Next by key 8.4 → 6.9, nothing worse; drops unchanged; MIDI burst worst 375/445 → 303/310 ms (target not met). Rolled back after measuring: inspector monitors as stacks, skipping the scroll for a visible cell. New `FIXU_ViewSourceTests` (3). No migration, no behaviour change, rectangles identical to before.

## Files

Changed: `App/Sources/ContentView.swift`, `ShowInspector.swift`, `TransportBar.swift`, `UISnapshotFixQ.swift` (profiling aid: loop kinds `clear` and `blackout`); new `App/Sources/ShowSlimRow.swift` (needs `xcodegen generate`; `WORSHIPFLOW.xcodeproj/project.pbxproj` not committed as the brief says), `Packages/WorshipFlowKit/Tests/OperatorCoreTests/FIXU_ViewSourceTests.swift`, this report. Scratch (outside the repository; builds, logs, the hide builds, the packaged check folder) deleted at the end.
