# UI-001 report: tokens, icon, six-mode shell, Show mode, Blackout

Result: `./scripts/check.sh` exit 0. `✔ Test run with 1552 tests in 229 suites passed after 39.892 seconds.` Verification level: Implemented and Unit Tested; interface checked in a running Debug build by self-drawn pictures and in-process key events only (see "Not verified").

## Parts

| Part | State |
|---|---|
| 1 Blackout | Done, test first |
| 2 Tokens and icon | Done |
| 3 Six-mode shell | Done |
| 4 Show mode to the design | Done, with the differences listed below |

### Part 1 Blackout
- Tests written first: `Tests/DomainTests/UI001_BlackoutTests.swift`, `Tests/OperatorCoreTests/UI001_BlackoutTests.swift`. Failing output before implementation: compile errors only, because the API did not exist (`type 'ShowCommand' has no member 'blackout'`, `value of type 'ShowState' has no member 'isBlackedOut'`, `KeyboardKey` has no `.b`, `WorkspaceModel` has no `blackout()`). After implementation 23 tests pass. No coordinator-owned test was changed.
- `ShowCommand.blackout` toggles; `ShowState.isBlackedOut`. Audience: opaque black, nothing drawn. Broadcast: fully transparent, nothing drawn. Stage: unchanged plus a "BLACKOUT" layer in the layout's `warningColor` (`StageComposer.blackoutLayer`, also used by the legacy `SceneComposer` stage). Deck, index and the clip transport are untouched. `trigger`, `next` and `previous` (when they move) lift it; a second `blackout` lifts it; `clear` and `clearAll` keep it and apply when it lifts; `stop` ends it.
- `LiveOutputKey` includes `isBlackedOut`, otherwise the publication gate would not republish.
- `KeyRouting`: B (key code 11) is `.transport(.blackout)`; passes through while typing, with a sheet open, with Command, Control or Option, or with Shift; ignored on key repeat. `WorkspaceModel.blackout()`.
- Decisions the brief left open: blackout with nothing live is ignored (there is no picture to black out; "stop ends it"); Next at the last slide, or Previous at the first, does not move and therefore does not lift it.

### Part 2 Tokens and icon
- `App/Resources/Assets.xcassets`: `AppIcon` set (the ten PNGs of `docs/UI/icon/AppIcon.iconset`) and 30 colour sets, one per token in `design-tokens.json`, dark and light, same names. Alias tokens (`role-*`, `status-ok`, `section-*`) hold the resolved values. `project.yml`: `App/Resources` added to sources and `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (nothing else).
- `App/Sources/DesignTokens.swift`: `Tok` (colours), `Space`, `Radius`, font styles. Views use these; the only literal colours left in new code are none.
- `Tests/OperatorCoreTests/DesignTokenParityTests.swift` fails if a token has no colour set, a colour set has no token, or any of the 60 dark and light values differ; it also checks the icon set (runs in `swift test`, so in `check.sh`).
- Output colours stay engine constants (the `canvas`, `lyric-ink`, `plate` sets exist only for the parity rule and are not used by views).

### Part 3 Shell
- Toolbar: service (playlist) name and library, mode switcher (a custom segmented control of icon and word; a SwiftUI segmented `Picker` in the toolbar drops the words), AUD, STG, BRD pills, search. Command-1 to 6 are in a new Mode menu. The mode is restored on relaunch from the library file (`workspace.mode` in `appState`), not from UserDefaults, so a `--library` run leaves the home folder alone.
- Decisions are in `OperatorCore`: `WorkspaceMode`, `RolePills`, `OutputHealth`, `SectionRuns`, `LiveSummary`, `LibraryFilter` (file `ShellPresentation.swift`), plus `WorkspaceModel.mode/setMode`, `libraryCounts`, `bilingualPresentationIDs`, `livePositionLine`, and two read-only store summaries (`LibraryStore+Overview.swift`). Tests: `UI001_ShellTests.swift`.
- Transport bar in every mode with LIVE, STOPPED, CLEARED or BLACKOUT badge, live words, position line, Previous, Go Live (the only filled red button), Next, Clear plus a menu with Clear all, Blackout (active state outlined in the warning colour), Stop, Open/Close screens, frame rate and dropped or late counts, and a cyan mini audio meter when audio exists. The clip strip still sits above it. Transport keys are routed by the existing key monitor, so they work in every mode unless a text input has focus.
- Stage layout sheet retired: `StageEditorSheet` became `StageEditorView` (the Stage mode). Sheets that remain: import and re-flow, section orders, themes, quick edit (a popover).
- Cues: the one-line note only.
- Screens: the existing panel, the connector map, Looks, props, the developer section, and "Run signal test…" (opens the existing Hardware Test window).

### Part 4 Show mode
See the comparison below.

## Control inventory (before and after)

| Before (control or panel) | Now |
|---|---|
| Toolbar: New presentation | Show sidebar "+" menu; Command-N |
| Toolbar: Import lyrics | Show sidebar "+" menu; Command-I |
| Toolbar: Section orders | Edit header "Section orders…"; playlist item context menu (unchanged) |
| Toolbar: Themes | Edit header "Themes…" |
| Toolbar: Stage layouts | Stage mode |
| Toolbar search (Command-F) | Toolbar search; typing in it switches to Show where results appear |
| Sidebar library picker and menu (new, rename, delete) | Library rows with counts; "+" menu carries New library, Rename, Delete |
| Presentation list and its context menu (add, rename, delete) | Same, with the EN · VI marker and a new Filter field |
| Playlist picker, menu, items, reorder, section order and remove menu, "on screen" dot | Same; the dot is now a red LIVE marker |
| Header: title field | Show header |
| Header: Add slide, Re-flow lyrics, Add to playlist | Show header (Reflow…; Add to playlist as an icon); Add slide and Re-flow also in Edit |
| Header: Theme picker | Edit header |
| Header: Section order picker | Show header "Arrangement" menu; Edit header picker |
| Slide grid: select, double-click go live, drag to reorder, context menu (Go Live, Move, Delete), delete confirmation | Show grid (plus grid or list toggle); Edit filmstrip selects |
| Editor: Words and Objects, words fields, speaker notes | Show: compact words, second language and notes under the grid. Edit: the same row plus the objects canvas and inspector at full size (the Words or Objects toggle is gone; both show) |
| Insert menu, Command-D, Delete, Undo and Redo for objects | Unchanged; Insert switches to Edit; Delete and Command-D act only in Edit |
| Right column: Live screens previews | Show inspector: Preview and Live panes, Screens summary |
| Media bin | Media mode |
| Audio panel | Media mode |
| Screens panel (open and close, SDI line and notice, connector map, every screen row, mirrors, developer) | Screens mode (the same view) |
| Timers panel | Show inspector and Stage mode |
| Look panel (choose, new, delete, rename) | Look buttons in Show; full panel in Screens |
| Props panel (add, toggle, remove) | Toggles in Show; full panel in Screens |
| Messages list | Show inspector, "Props and messages" |
| Transport: state, summary, Previous, Go Live, Next, Clear, Clear all, Stop | Transport bar (Clear all in the Clear menu), plus Blackout |
| Transport: Quick edit live slide (popover) | Show header "Quick edit ⌘E"; Command-E from any mode switches to Show first |
| Transport: Open screens or Close screens | Transport bar icon button; Screens mode |
| Clip transport strip | Unchanged, above the transport bar |
| Error and unsaved bars | Unchanged, restyled |
| Menus: New, Import, Hide, Undo, Insert, Hardware Test, Find, Show menu | Unchanged; new Mode menu; Show menu gains Blackout |
| `--hardware-test`, `--open-screens`, `--silent-audio`, `--library`, soak | Unchanged; `--show-screens-panel` now opens the Screens mode |

Nothing could not be re-homed. Two small losses to name: the Words or Objects toggle was removed (both are always shown in Edit), and "Stage message" from the design is not drawn because the app has no stage message yet (`StageModel` passes `message: nil`).

## Show mode against `01-operator-show.png`

Matches: sidebar with LIBRARIES counts, filter field, EN · VI marker, playlist with LIVE marker; header with title, Arrangement menu, EN + VI chip, Add slide, Reflow, Quick edit with key hint, grid and list toggle; coloured section headers with dots and "× 2" repeat counts (blue verse, cyan chorus, warning bridge and ending); thumbnails with the number and first line beneath; PREVIEW (blue) and LIVE (red, 3 pt) rings drawn outside the picture with tags; the compact words strip with "IN PREVIEW" and the preview-only note; inspector with Preview and Live side by side, Screens summary, Look buttons, props toggles, timers; transport bar with LIVE badge, two-line text, hinted Previous, Go Live, Next, Clear with menu, Blackout, Stop, readout and meter.

Differences and why:
- Thumbnails are dark with no teal gradient: the app's default theme draws a video background and the thumbnails have no frames; the design artwork is a mockup. With a background loop set, the Live pane and the Screens summary show it.
- Sidebar libraries are the user's own libraries (no Scripture, Sermons or Announcements rows, no per-item icons by kind); playlist headers (Pre-service, Worship) and countdown items are UI-002.
- Look buttons mark the selected one with a check and a cyan outline, not a blue ring: the design principle reserves the blue ring for Preview.
- No "Stage message" row (no such feature); no role chips next to each prop (no data on which screens show a prop).
- Window title text "WORSHIPFLOW" still shows beside the service name. Hiding it (`titleVisibility = .hidden` or `toolbar(removing: .title)`) made the right-hand pane draw empty in my captures, so I left it and noted it.
- Transport "Clear" and the Clear-all menu are two adjoining controls, not one split button. System font, not Inter. The mode switcher is custom, not a native segmented control.
- Preview shows the slide on the audience theme only; the Stage and Broadcast thumbnails are in the Screens summary.
- Sidebar and inspector widths are capped at 320 and 400 so the grid keeps room at 1440 wide.

## Pictures (`AI/reports/`, 2880 x 1720, dark)

`UI-001-show.png`, `-edit.png`, `-media.png`, `-stage.png`, `-cues.png`, `-screens.png`, `-blackout.png`. Taken in a Debug build with `--ui-snapshots` (below), a temporary library, one bilingual sample song, `loop-1080p5994.mov` as background, outputs in windows. What each shows:
- Show: as above, slide 3 live (red ring), slide 4 in preview (blue), rainbow test loop live in the Live pane and the audience summary card, stage card with words and clock.
- Edit: slide filmstrip, theme and section-order controls, a "Slide 3 is live. You are editing slide 4." strip, three words fields, and the objects canvas at full size with the "No object selected" inspector.
- Media: media bin with the loop (BACKGROUND tag, 0:20) and Audio on the right.
- Stage: layout list, the Standard layout canvas with sample words and clock, timers and clock on the right.
- Cues: centred bolt icon and the one-line note.
- Screens: the screens configuration at full size (both windows read "Hidden" because the screen was locked), Look, Props and Verification with "Run signal test…".
- Blackout: BLACKOUT badge in the transport bar and on the live slide (warning colour, no red), the audience Live pane and summary card black, the stage card still showing words with a small "BLACKOUT".
The design pictures other than 01, 08 and 09 were only glanced at (02 and 03 viewed).

## Paths exercised in the running app

Real app, `--ui-snapshots` hook (DEBUG only, `App/Sources/UISnapshotRun.swift`): import of a bilingual song, playlist add, media add and background, audience and stage in windows, Go Live, select, Command-1 to 6 sent as real key events through the app's own menu (each switched to the right mode), B sent as a real key event through the key monitor from the Screens mode (blacked out; second B lifted it), Right arrow in the Screens mode advanced the live slide (2 to 3), picture of each mode and of Blackout, library written and flushed, quit by `exit(0)`.

Not exercised: any mouse click or typing in the real window (the screen was locked, so background control could not capture or reach the window), VoiceOver, the light appearance (design 09), the Hardware Test button, sheets opening from the new places, Command-E from a non-Show mode, drag reorder, the context menus, the Clear-all menu item, resizing to 1100 x 640, a real second display, any sound. Window outputs were "Hidden" (locked screen), so pills showed "on" via the covered rule, not a measured picture on an output.

## Files

Created: `App/Resources/Assets.xcassets/**`, `App/Sources/{DesignTokens,Components,ShowMode,ModeViews,StageEditorView,UISnapshotRun}.swift`, `Packages/WorshipFlowKit/Sources/OperatorCore/{ShellPresentation,WorkspaceMode}.swift`, `Packages/WorshipFlowKit/Sources/Persistence/LibraryStore+Overview.swift`, tests `DomainTests/UI001_BlackoutTests.swift`, `OperatorCoreTests/{UI001_BlackoutTests,UI001_ShellTests,DesignTokenParityTests}.swift`, the seven pictures and this report.
Changed: `Domain/{ShowState,SceneComposer,StageLayout}.swift`, `OperatorCore/{KeyRouting,LivePublication,WorkspaceModel,WorkspaceModel+Library,WorkspaceModel+Transport}.swift`, `App/Sources/{AppModel,CentrePane,ContentView,ControlPanels,LibrarySidebar,SlideObjectsEditor,TimersPanel,TransportBar,WorkspaceUIState,WorshipFlowApp}.swift`, `project.yml`, `WORSHIPFLOW.xcodeproj` (regenerated), `docs/hands-on-checklist.md` (new UI-001 section, three location words updated, nothing dropped), `docs/17-change-log.md`.
Deleted: `App/Sources/StageEditorSheet.swift` (replaced by `StageEditorView.swift`).

## Deviations and caveats

- Mid-run, another task's test file (`Tests/PersistenceTests/ScriptureSchemaTests.swift`, LIB-004b) appeared before its code and broke the whole-package test build, although I was told I was alone. I ran my tests from a scratch mirror of the package without that file until the code arrived; the final `check.sh` run is on the real tree and is green. I did not touch that file.
- I ran `git mv` once by mistake (it staged a rename) and undid it with `git reset -q` on those two paths; nothing else was staged, committed or stashed. The old sheet file shows as deleted and the new one as untracked.
- The README says Edit, Stage and Screens drop the transport bar; the brief says every mode, so every mode has it.
- Hidden screens count as "on" in the pills (with "covered by another window" for VoiceOver); the brief allowed only on, off, fault.
- Stage "BLACKOUT" uses the layout's warning colour, which defaults to red; that follows the brief but is red on a stage screen.
- Ring colour for the live place is the warning colour while cleared or blacked out (red only when words are on screen).
- Screenshots are drawn from the window's own layer tree, not a screen capture, so they omit window chrome effects such as shadows and may differ slightly from the real glass toolbar.
- The `--ui-snapshots` hook is extra code (DEBUG only) added to be able to see and drive the app on a locked screen.
- Commands run: `swift test` (several, filtered and full), `./scripts/check.sh` (exit 0), `xcodegen generate`, `xcodebuild ... build` into a scratch derived-data folder, the app launched with `--library`, `--silent-audio` and `--ui-snapshots` under two minutes each, then terminated. No advisor tool was consulted.

## Not verified

Everything listed under "Not exercised"; light appearance; behaviour at 1100 x 640; contrast of the restyled controls; that system controls (segmented picker in the header, pop-ups) look right in the live compositor; hardware (nothing here is Hardware Verified).
