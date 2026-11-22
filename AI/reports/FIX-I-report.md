# FIX-I report: the owner's hands-on findings on build 101

## Cause of item 1 (Previous / Next keys do nothing)

SwiftUI's `@Environment(\.isFocused)` is inherited by every view under a focused `.focusable()` container. The slide grid's column (`ShowCentre`, which holds the grid and the media dock) is such a container. FIX-H item 7's `WFFocusReport` sits on controls in that column (the dock's pop-up, its buttons), so whenever the grid itself took focus they all reported "I have focus". The key monitor read the last report (`ui.focusedControl == .popUp`) and handed every key to "a control": arrows, Space and Return did nothing, until Escape.

Proof in the running app (real `NSApp.sendEvent` key and mouse events, debug hook, temporary `--library`):
- Before: at launch and after a click in the grid, sidebar and inspector the keys worked. After a click on a media bin tile (the grid regained focus) the log showed `focusedControl popUp; router focus popUp` and Left, Down, Space and Return changed nothing. It stayed that way after a sheet closed. A temporary trace showed three `button true` and one `popUp true` reports at that click, and the matching `false` reports when the sidebar was clicked.
- After the fix every region works (below).

Fix: `ControlFocusTracker` (OperatorCore) tracks reports per control identity, newest wins, and ignores them while the grid itself has focus (`ui.gridHasFocus` from the workspace view). Escape clears all.

## Items

| Item | Status |
|---|---|
| 1 keys dead | Done, cause proved, real-key run |
| 2 keyboard sections, arrows move selection, Return, Space, Shift-Space | Done |
| 3 selection crosses playlist items | Done |
| 4 Clear background / foreground / all drop bin choices | Done |
| 5 thumbnails show backgrounds | Done |
| 6 thumbnail menu: Clear this slide's background, Set background… | Done |
| 7 warning card fades after 5 s | Done |

Decisions: Shift-Space is Previous (free). Up/Down in the slide grid step a row and cross section boundaries; Up/Down never cross playlist items. In the Media mode the bin always has the arrows; a folded dock in Show hands them to the grid. The quiet section mark is a 1 pt blue edge at 45 % (the design has no focus style). A card whose hold ends after its 5 s fades at once. The menu actions select the slide first, because Undo only reaches the selected slide (found by a failing test). Clear background still hides every background until the next slide, and now also drops the bin choice. Item 6: the old "Use the presentation's background" entry became "Clear this slide's background" (one entry).

## Test-first record (failing output per item)

- Item 1: `FIXI_ControlFocusTests` failed to compile on `ControlFocusTracker` only (new symbol); the real-app run above is the runtime failure.
- Item 2: `FIXI_KeySectionTests` failed to compile on `KeySection`, `SelectionMove` (new symbols); after the routing change the old tests asserting arrow = Next/Previous failed at runtime (listed below). `FIXI_KeyTableTests`: `TransportKeyHints` missing.
- Item 3: `FIXI_SelectionMoveTests`: `WorkspaceModel.moveSelection` missing (compile).
- Item 4: `FIXI_ClearBackgroundTests` with the old wiring: 15 runtime issues, for example `hasLiveBackgroundOverride` still true after Clear background, Next brought the loop back, the dropped choice was remembered at relaunch, Clear all kept the background. Then fixed.
- Item 5: `FIXI_ThumbnailBackgroundTests` failed to compile on `StillCacheKey` (new).
- Item 6: `FIXI_SlideBackgroundMenuTests`: compile on `SlideBackgroundMenu`; then a runtime failure (Undo did not reach a slide that was not selected) which led to `setBackgroundFromMenu`.
- Item 7: `FIXI_FaultCardFadeTests` failed to compile on `FaultCardVisibility` (new).

## Existing tests changed (only where they asserted the old meaning)

Owner's sentence for items 1-3: "moving left / right button will move the selection but hit enter will bring the current live".
- `FIXH_KeyFocusTests.withNothingOrTheSlideGridFocusedTheTransportKeysDriveTheShow`: Right/Left now `.moveSelection`.
- `KeyRoutingTests.transportKeysReachTheShowWhenNothingIsBeingTyped`: arrows removed from the transport list, asserted not transport.
- `UI005a_TransportBarModesTests.everyTransportKeyDecidesTheSameWhateverTheMode`: arrows are `.moveSelection` in every mode.
- `FixB_TransportTests.shiftEscapeFollowsTheSameRulesAsEveryTransportKey`: Shift-Space is Previous (owner decision, "Shift-Space is Previous if that is free").
Item 4, owner: "when clear the background. the live in media bin should be cleared as well":
- `MEDIA010_LiveClearTests.goLiveNextAndPreviousBringTheBackgroundBack`: after Next the background is not the dropped loop and the override is gone.
Nothing else was edited. (`FIXG_BackgroundSilenceTests` still says the choice is "kept" after `show.apply(.clearBackground)`; that is the show-state command alone and is still true.)

## What the real-key run showed in each region

Debug hook `UI_SNAPSHOT_FIXI=1` (`App/Sources/UISnapshotFixI.swift`): real mouse clicks at probe rectangles, real key events through the app's own key monitor, scratch library, `--silent-audio`, window outputs, process stopped by the script. With a song live at slide 2:
- Launch, after a click in the grid, in the sidebar, in the inspector (grid last): Right/Left/Down moved only the selected slide (live unchanged), Return took the selection live, Space advanced the live slide, Shift-Space went back.
- After a click on a bin tile: section `mediaBin`, focusedControl nil. Right/Right/Left/Left moved the bin selection across the three items (live slide and background unchanged), Down stayed (one row), Return set the selected item as the live background, Space advanced the live slide. A click in the sidebar or the inspector kept the bin; a click back in the grid returned the arrows to the slides.
- Sheet open: Right changed nothing. After the sheet closed: all keys worked again.
Not done by hand: a real keyboard, Tab with Keyboard navigation on.

Item 4 in the app: bin picture live, Clear background (key path): override false, hidden true; Next: override false, hidden false, the slide's own background shows. Item 6: the menu actions on slides 3 and 5: cleared, Undo restored, set from the bin, Undo reverted; live place unchanged. Item 7 on the simulated SDI card with an injected clock: two cards shown; at 4 s still shown; at 6 s none, pills still `AUD fault`, `BRD fault`; pill click shows that role's card; pointer over for 30 s keeps it; leaving fades it.

## Thumbnail cost (200 slides, debug build, simulated, one machine)

200 thumbnails with own backgrounds (video, two pictures, none): first pass 836 ms (4.2 ms each) through the same still + Compositor path as `SlideThumbnail`; second pass from the cache 148 ms; stills taken from files: 3 (once per file, cached by path, modification date and size; limit 24); players opened by thumbnails: 0 (the still is an image-generator frame); resident memory +48.7 MB, which is the preview renderer's existing 200-image cache (about 230 KB each) now also holding thumbnails with media. Picture: `AI/reports/FIX-I-thumbnails.png` (the video still with film mark and two picture backgrounds).

## Checks

`./scripts/check.sh` run twice: exit 0 and exit 0, 2720 package tests each (2667 before this slice;       75 new `@Test` functions in `FIXI_*`), and the app build passes.

## Docs

`docs/17-change-log.md` (plain words for the key change), `docs/16-known-issues.md` (KI-146 to KI-149; KI-136 is about the Props pills and is not affected, KI-129 still holds), `docs/hands-on-checklist.md` (keyboard lines changed, FIX-I section). The Cues keyboard table is `ShowShortcuts` (updated and tested) and the transport bar hints and tooltips read `TransportKeyHints`. Not updated: `docs/14-current-status.md`, `docs/15-agent-handoff.md`, feature specs (no data changed).

## Not verified

No real keyboard with Keyboard navigation on; whether `FocusState` on the grid container stays false while one of its own descendants has focus (assumed); VoiceOver for the section mark and the pill as a button; a real unplugged display or card for the fault card (only the simulated card); Media-mode bin Up/Down by a row was exercised only by the pure function and a one-row dock; scripture passage selection was covered by a model test, not by hand. Hardware Verified and Live-Service Verified: not applicable.

## Files

New: `ControlFocusTracker.swift`, `SelectionNavigation.swift`, `WorkspaceModel+SelectionMove.swift`, `MediaWiring.swift`, `ThumbnailBackground.swift`, `FaultCardVisibility.swift` (package); `ThumbnailStills.swift`, `UISnapshotFixI.swift` (app); seven `FIXI_*` test files. Changed: `KeyRouting`, `HeaderChrome`, `LiveMedia`, `ShowCueTarget`, `SlideEditorModel`, and in the app `AppModel`, `ContentView`, `CentrePane`, `ModeViews`, `ShowMode`, `MediaDockView`, `MediaBinPanel`, `Thumbnails`, `TransportBar`, `WFControls`, `WorkspaceUIState`, `UISnapshotRun`.
