# UI-003 report: Show mode to design revision 2, and the KI-079 flaky test

Verification level: Implemented and Unit Tested (decisions in `OperatorCore` and `Domain`, 2010 package tests). Interface checked only in a Debug build through the `--ui-snapshots` hook (pictures drawn from the layer tree) plus real key events sent to the running app. Nothing here is Hardware Verified. No advisor consulted. No git state changed. `docs/UI/`, `docs/adr/`, `Package.swift`, `CLAUDE.md`, the unwired engines and coordinator-owned tests were not touched.

Commands and results are in the last section.

## Parts

| Part | State |
|---|---|
| 0 Flaky relaunch test (KI-079) | Done. Cause found and reproduced deterministically; it was in the test rig, not in `WorkspaceModel.load()` |
| 1 Show mode, revision 2 | Done, with the left-out and unverified items below |
| 2 Other modes | Done for what the revision changed and what the app can do (list below) |
| 3 Checklist and pictures | Done |

## Part 0: the cause

`UI002_PlaylistItemsTests.rig()` built the first session's `WorkspaceModel` on the real clock. Every `addToPlaylist` and `openPlaylistItem` schedules a debounced save of the place (a real half-second timer). The test then stored the place it wanted (a playlist header) and started a second model. Under load the first session's timer fired between those two steps, wrote the first session's own place (a song open, no playlist item selected) over it, and the relaunch read that: `selectedPlaylistItemID` came back nil.

`WorkspaceModel.load()` itself has no ordering race: it reads the stored place once, then loads libraries, presentations, playlists and playlist items one after the other, then applies the place. A real quit flushes the place saver first, so a stale write cannot land after a relaunch.

Reproduction (red before the fix): `anEarlierSessionsPendingPlaceWriteCannotReplaceTheStoredPlace` drives the first model with a `ManualSaveClock`, stores the header place, moves the clock past the debounce and relaunches. Without the flush it fails with `selectedPlaylistItemID` nil, exactly the field failure. Fix: `rig()` uses a `ManualSaveClock` and a helper `leaveBehind(_:in:)` flushes the first session before storing the place, as a quit does; both relaunch tests use it. No sleeps; the assertions were not weakened.

Five consecutive full runs after the fix: see the last section. (An earlier series of five was cut to four good runs because my own new test files were mid-edit during the fifth; the final series is on the finished tree.)

## Part 1: what was built

Decisions (all in `Packages/WorshipFlowKit/Sources/OperatorCore/ShowRevision2.swift`, `StageModel+Messages.swift`, `MediaModel.swift`, `SettingsModel.swift`, `Domain/StageLayout.swift`, `Domain/MediaLayers.swift`), tests in `UI003_*` files.

- Search at the top of the sidebar's Libraries section (titles and lyrics, shows Title or Lyrics on each hit, filters the list beneath, Command-F, Escape clears it and puts focus on the grid, the search field is a SwiftUI field so `AppModel` reads `ui.searchHasFocus` for the key router). No search field in the toolbar. The old "Filter songs" box and the centre results page are gone (their job is done by the one search).
- Toolbar timers (`ToolbarTimersView`, `StageModel.toolbarTimerRows`): default first elapsed and first countdown; the operator marks others with a toolbar toggle per timer in the Timers panel (kept in `stage.toolbarTimers`); start or pause on a countdown only; overrun in the warning colour; nothing when there are no timers; visible in every mode.
- Slide grid: `SlideGridLayout.columnCount` (five at the design's 812 pt centre column).
- Media dock (`MediaDockView`): Backgrounds, Videos, Images, Audio; Background or Foreground choice (hidden on Audio); "+" adds files; drop files; fold with the chevron; drag the top edge to resize; height and folded state in `settings.mediaDock`. Click a tile: `MediaDock.action` decides (background, foreground, or a sound cue). Rings: red and LIVE only for what is on screen now, blue and PREVIEW for what is chosen, a cyan SOUND tag for a sounding cue (`MediaTileMarks`). The Backgrounds tab is every picture and video (the bin has no other notion of background; KI-082).
- Media controller row (`MediaControllerRow`): clip over the slide, else the latest sound cue, else the background video. Restart, play or pause, stop, name, elapsed, scrubber, remaining, loop, mute and volume, and the screens it is on (AUD or BRD from the real Look and theme settings, or the output device name for sound). Loop on a clip restarts it at its end (`MediaModel.foregroundLoops`); a background always loops and is shown as "Loops". Background video gained pause, resume, seek and restart. The row stays when the dock is folded so a clip can always be stopped. In Show it replaces the clip strip; the other modes keep the strip.
- Monitors: Preview and Live side by side; every other enabled screen beneath (Stage, Broadcast, further audience screens), each with its destination text and a SIM badge where true; "Configure…" switches to Screens.
- Look: one row sized from the names (`LookRow.capacity`), the rest in a chevron menu; the selected Look is always on the row.
- Tabs: Props (the props list with toggles and AUD or BRD chips only for the roles whose screens show the props layer under the Look), Cues (a note that nothing is wired), Audio (the audio panel), Quick edit (only while open).
- Quick edit: Command-E (menu), the header button, the button under Preview or the slide's context menu open the tab for the SELECTED slide: two language fields, speaker notes, a "Preview only" chip and Done (Escape, a cancel-action button, so it works while typing). It replaces the strip under the grid. It never touches the live output (shown by test and in the running app: typing changed the selected slide, the live slide did not change).
- The two meanings of quick edit kept apart: the old live-slide popover is "Edit live slide…" with its own key (Option-Command-E, menu "Quick Edit Live Slide…"; Shift-Command-E was tried first and rejected: in the running app a synthesized Shift-Command-E was taken by the Command-E item, so the two meanings could have been confused), its own button under the Live monitor outlined in the warning colour with the sentence "This changes what the audience sees now…", and a button in the Edit header. The README's semantics table still says Command-E is "the one edit that changes the live slide" while its Show section makes Command-E the preview-only tab; I kept both, gave the live one Option-Command-E, and the README was not edited (docs/UI is off limits). `docs/hands-on-checklist.md` says so.
- Stage message (LIVE-03): text field, Send, Clear and a recents menu in the Show inspector and in the Stage mode; it goes to stage screens only (the layout's message element, or a bottom banner for a layout without one: `StageComposer`), survives slide changes, Clear removes it, Stop removes it (`StageModel.showStateChanged`), last five kept (`stage.recentMessages`).

## Part 2: other modes

- All modes: the toolbar timers (the revision's change to every picture).
- Stage (04): added the stage message composer (design has it bottom-left); Timers panel row gained the toolbar toggle. Left as is: layout list, canvas, element list, assigned-to (already follow the design); no Section element (no such feature).
- Media (05): added the Background or Foreground choice to the header (double-click on a tile follows it, sound plays as a cue). Left: the design's "Motion backgrounds" categories (the bin has kinds only), routing matrix, level bars, offline-file card, mark in and out, add marker (no such features); the clip strip stays above the transport bar.
- Edit (02): the header button that was "Quick edit" (which only ever changed the live slide, and had no popover to appear in) is now "Edit live slide…" (switches to Show and opens the live edit). Left: align, arrange, preview-screen switch, zoom, object tabs, saved time (no such features).
- Screens (03) and Cues (06): only the toolbar changed in the revision for what exists; Add screen, Remove screen, Identify screens and the Cues content are not features. Light pictures (09, 11): checked with the Show light picture; not pixel compared.

## Control table (UI-001 and UI-002 tables, changes only)

| Control | Before | Now |
|---|---|---|
| Search field | Toolbar `.searchable`, results page in the centre | Top of sidebar Libraries, results filter the list beneath (Title or Lyrics tag), Command-F, Escape |
| "Filter songs" (titles only) | Sidebar box | Merged into the search (it already matches titles) |
| Quick edit, Command-E | Popover that changed the LIVE slide | Quick edit tab, selected slide, Preview only |
| Live edit | Same popover | "Edit live slide…": Option-Command-E, button under Live, Edit header, Show menu "Quick Edit Live Slide…" |
| Words editor strip under the grid | Show | Quick edit tab (Edit mode keeps its full editor) |
| Search results page | Centre pane | Rows in the sidebar list |
| Screens summary grid | Right column, every screen with chips | Live monitor beside Preview; others beneath; Configure… |
| Look buttons | Two-column grid | One row plus chevron menu |
| Props and messages | Right column | Props tab (same toggles, same messages) |
| Timers panel (add, start, pause, reset, rename, delete, clock style) | Show inspector and Stage mode | Stage mode only (add, reset, rename, delete, clock style); toolbar shows marked timers with start or pause on countdowns. **Show no longer has Add timer, Reset, Rename, Delete or the clock style** |
| Audio panel | Media mode only | Media mode and the Audio tab in Show |
| Clip strip above the transport bar | Every mode | Every mode except Show (controller row under the dock) |
| Media bin double-click | Set as background | Follows the layer choice (sound plays as a cue) |
| Media bin: dock, tabs, layer choice, controller row | None in Show | New in Show; layer choice also in Media mode |
| Stage message | None | Show inspector and Stage mode |
| Toolbar timers | None | Every mode |
| Slide context menu | Go Live, move, delete | Plus Quick edit |
| Edit header Quick edit | Opened the live popover (not shown in Edit) | "Edit live slide…" |
| Everything else in the UI-001 and UI-002 tables | | Unchanged |

## Pictures (`AI/reports/`, 2880 x 1720, temporary library, `--silent-audio`, window outputs and the simulated SDI card)

`UI-003-show.png`, `-edit.png`, `-media.png`, `-stage.png`, `-cues.png`, `-screens.png`, `-show-quick-edit.png`, `-show-dock-collapsed.png`, `-show-light.png`, plus `-show-clip.png`, `-show-sound.png`, `-show-search.png`, `-blackout.png`, `-countdown.png`. The test loop video is a rainbow, which is why backgrounds look loud; the bin holds three copies of it, three generated pictures and two generated tones.

- `show`: toolbar with mode switcher, "Service 0:10" and "Sermon 25:00" with a play button, then AUD, STG, BRD. Sidebar with the search field and key hint, songs, playlist with headers and a countdown. Centre: header with labelled buttons, five-wide grid area with the LIVE (red) and PREVIEW (blue) slides, then the dock (tabs, Background or Foreground, thumbnails, the live one in red) and the controller row for the background loop. Right: Preview and Live, a Quick edit button and an "Edit live slide…" button, Stage and Broadcast cards (SIM on the card), the Look row with a chevron, tabs with Props, the stage message pinned at the bottom.
- `show-quick-edit`: the same with the Quick edit tab selected (dot on its tab), slide 4 of 5, "Preview only", Done (esc), two language fields; speaker notes are below the fold at this window height (scroll).
- `show-dock-collapsed`: the dock is only its header; the controller row remains.
- `show-light`: the same in light tokens; text, rings and tabs readable.
- `show-clip`, `show-sound`: the controller driving a looping clip over the words, and a sound (Audio tab, SOUND tag, output chip).
- `show-search`: "grace" typed; the list shows Amazing Grace tagged Title.
- `edit`, `media`, `stage`, `cues`, `screens`: as before apart from the toolbar timers, the stage message composer (Stage), the layer choice (Media) and "Edit live slide…" (Edit).

Against the design pictures: `01-operator-show` matches: toolbar timers beside the pills, search in the sidebar, five-across slides, dock with tabs and layer choice, controller row, Preview and Live side by side with Stage and Broadcast beneath, the Look row, tabs, the stage message. Differs and why: the Backgrounds tab lists every picture and video (no background category in the data); no role chips on the Look buttons; Stage and Broadcast captions read the real destination text, which for the simulated card is long; the tile row has no "Loop" or "Foreground" categories beyond what exists; thumbnail art is the test rainbow; the toolbar shows "0:10" where the design shows "00:10:32" (the app's time format); the controller shows "Loops" as a label for a background instead of a Loop button; two extra buttons (Quick edit under Preview, Edit live slide under Live) because the two meanings of quick edit must be separate; the stage message is pinned at the bottom of the column instead of under the props. `01b` matches in the tab, the chip, Done and the fields; the saved line is "Saved · …" without a time (the app has no saved-time source); notes need a scroll at this window height.

## Paths exercised in the running app (debug hook, real key events to the app)

Command-1 to 6 through the real menu; B and Right arrow from Screens; Command-F focused the search field; typed "grace" through key events and the list filtered; Escape cleared it and left the field; Command-E opened the tab on the selected slide; typing in the tab changed the selected slide and not the live slide; Escape closed the tab; the dock folded and unfolded through the same settings call the chevron uses; a clip looped past its end and kept playing from the start; a sound played with `--silent-audio`; the stage message appeared on the stage preview and was cleared by Stop; the timers, a prop, three Looks and the simulated SDI card were set up and drawn; light appearance.

Not exercised: any mouse click or drag (tile click, Send, toolbar timer button, dock resize by dragging, the chevron itself), the Option-Command-E popover (see the last line), VoiceOver, the minimum window size (1100 x 640), a real second display or card, hours-long runs.

## Deviations and everything not verified

- Failing-first evidence: the Part 0 reproduction failed for the right reason (nil selection). For the new decision tests the failure was a compile error (the types did not exist), then green; the behaviour tests were written before the code.
- `swift test` rebuilds when package sources change, so a series of runs must not overlap edits (cost one run, repeated).
- A full `./scripts/check.sh` run while I was also working failed once with two wall-clock tests (`aBrokenForegroundClipIsReportedPerAssetId`, `searchIsFastOnTwoThousandSongs`) under load; neither touches this slice. The final runs below passed.
- On this Mac an extra path argument (`--ui-snapshots <dir>`) stopped the SwiftUI window from opening; the hook now also reads `UI_SNAPSHOT_DIR` (KI-083). Runs used a copy of the built app under a throw-away bundle id, so the app's saved state is not touched. Bash's sandbox had to be lifted to start the app with a window.
- The Option-Command-E popover could not be seen: a popover cannot stay open while the app is not the active app. The hook checks that the key reached the menu item (a request counter), not the popover.
- `MediaBinPanel`, `MediaTransportStrip` and the thumbnail code are reused; the dock and the controller are new views because the dock needs a strip, rings and a layer choice the old panel does not have.
- A foreground clip's loop is the model starting the clip again, not the player looping (KI-082); the wrap gap was not measured.
- Not verified: contrast of every new control (the token pairs are unchanged), behaviour with hundreds of media items, the dock with a very small window, anything in the live service.
- Added to the docs: `docs/16-known-issues.md` (KI-079 closed, KI-081 to KI-083), `docs/17-change-log.md`, `docs/14-current-status.md`, `docs/15-agent-handoff.md`, `docs/19-data-dictionary.md` (three `appState` keys, no schema change), `docs/hands-on-checklist.md` (no check dropped, one new section).

## Files

Created: `Packages/WorshipFlowKit/Sources/OperatorCore/{ShowRevision2,StageModel+Messages}.swift`; tests `OperatorCoreTests/{UI003_ShowDecisionsTests,UI003_StageMessageTests,UI003_ToolbarTimerTests,UI003_MediaControllerTests,UI003_DockSettingTests}.swift`, `StageTests/UI003_StageMessageBannerTests.swift`; `App/Sources/{MediaDockView,ShowInspector,StageMessageView,ToolbarTimersView}.swift`; the pictures and this report.
Changed: `OperatorCore/{HeaderChrome,MediaModel,SettingsModel,StageEditing,StageModel}.swift`, `Domain/{MediaLayers,StageLayout}.swift`, `OperatorCoreTests/UI002_PlaylistItemsTests.swift` (rig clock and `leaveBehind`, not coordinator-owned); `App/Sources/{AppModel,CentrePane,ContentView,LibrarySidebar,MediaBinPanel,ModeViews,ShowMode,StageEditorView,TimersPanel,UISnapshotRun,WorkspaceUIState,WorshipFlowApp}.swift`; `WORSHIPFLOW.xcodeproj` (regenerated); the docs listed above.

## Commands run and results

- `swift test` (package, from `Packages/WorshipFlowKit`), five consecutive full runs on the final tree, each exit 0: `✔ Test run with 2010 tests in 308 suites passed after 61.6 / 61.0 / 62.0 / 61.3 / 62.1 seconds.` (Earlier on the same code, before the last shortcut change: five more green runs; and before that, four green runs after the Part 0 fix.)
- `./scripts/check.sh` (with `WF_DERIVED_DATA` pointing into the scratch folder): on the final tree exit 0, `✔ Test run with 2010 tests in 308 suites passed after 63.355 seconds.`, domain boundary clean, `xcodegen generate`, app build, `== OK`. Five check.sh runs in all: exit 0 on the near-final tree and on the final tree; exit 1 three times on wall-clock tests under load (`aBrokenForegroundClipIsReportedPerAssetId` and `searchIsFastOnTwoThousandSongs` once, `searchIsFastOnTwoThousandSongs` twice at 0.20 to 0.21 s against its 200 ms limit, with the Mac at load average about 3). `searchIsFastOnTwoThousandSongs` is coordinator-owned and passed alone and in all fifteen plain full runs (KI-084).
- `xcodebuild -scheme WORSHIPFLOW -configuration Debug` into the scratch folder, many times; the app copied under throw-away bundle ids and run with a temporary `--library`, `--silent-audio`, windows only (about a dozen runs, each under two minutes, each quit; `pgrep` found no WORSHIPFLOW process afterwards).
- The owner's library folder: recorded at the start (folder 04:52:25, `Library.sqlite`, `-shm`, `-wal` 05:41:43) and compared again after my last app run: identical. Checked a last time at the very end, `-shm` and `-wal` had changed (07:50:57 and 07:51:22): the owner had launched their own Release build (`WORSHIPFLOW-release/.../WORSHIPFLOW`, pid 34041, parent launchd, started 07:50:57) on their real library. I never ran that binary; all my runs used `--library` in the scratch folder.
- Left behind in the home folder: nothing (the preference files of the throw-away bundle ids were removed; the app's own `org.worshipflow.app.plist` is unchanged since 04:59:54).
