# Independent review, fourth pass: findings

Range reviewed: a5ae9b2 to 8590d5a (FIX-S, FIX-T, UI-006c Edit, UI-006d Media, UI-006e Stage, UI-006f Screens, UI-006g Cues). Read-only, by reading code through git (`git show`, `git diff`, `git grep` at 8590d5a). Nothing was built, run or launched; no git state was changed. Line numbers are as of 8590d5a. Reports were not trusted; each finding below was read in the code.

Confidence words: "confirmed" means the code path was read end to end. "Plausible" means the path exists but a timing, platform or input condition was not established.

Count: 0 high, 5 medium, 9 low.

## High

None found. The review-3 high (H1) is fixed (see the verification list).

## Medium

### M1. The Edit "Stage" preview does not show the stage screen's layout
- Where: `App/Sources/EditCanvasChrome.swift:38-42` (`editPreviewScene`), `OperatorCore/UI006c_EditFeatures.swift` (`EditPreviewScene.scene`, builds `PublishedScenes(...)` with no `stageScenes:`), `OperatorCore/PublishedScenes.swift:22-31`, `Domain/SceneComposer.swift:160-164`.
- A stage screen is drawn from its `StageModel` layout only when `stageScenes[profile.id]` is passed. The Edit preview never passes it, so `PublishedScenes` falls through to `SceneComposer.stage(...)`, which draws the built-in Standard layout with no timers and no message, and a one-slide deck so there is no "next" line.
- Scenario: the operator gives the stage screen the "Speaker" preset (notes and timer), or hides the Next element with the new eye, or turns Auto-fit on. In Edit they press "Stage" to check the slide. The canvas draws the Standard layout (current slide, next absent), not the layout the stage screen will use, and says "Stage screen, read-only". The preview is wrong exactly for the features UI-006e added.
- Safety side: no notes are passed, so no speaker notes appear; this is a correctness and trust problem, not a leak. Broadcast is composed by the real composer and is correct.
- Confidence: confirmed by reading. The caption should say "Standard stage layout" or the real layout should be passed.

### M2. `retiring` in the output coordinator is only emptied when an SDI output starts or a waiting stop is asked
- Where: `OutputEngine/OutputCoordinator.swift:412-428` (`stopTarget`, `retiring`, `awaitRetiredTargets`), `:433-436` (`targetChanged`). The app calls `stopScreens(waitForPorts: false)` and `stopScreen` with `waitForPorts: false` (`App/Sources/AppModel.swift:921`, `:1543-1545`); the only drains are `awaitRetiredTargets()` at `:154`/`:378` (SDI start) and the `waitForPorts: true` paths (quit, soak).
- Scenario: a Mac with display and window outputs only (the normal case until a card is owned). Every Close screens, Retry, destination change or profile change appends the stopped targets to `retiring`; nothing removes them. Each retained target keeps its window, Metal layer and textures alive for the life of the app. For SDI the ring (about 13 frames of 8 MB) is held the same way until the next SDI start.
- Result: unbounded retention across open/close cycles in a long session. No crash; memory grows by the size of one output's resources per cycle. Not seen in a run.
- Confidence: confirmed that the list is never trimmed on the display path; the size of the leak per target is plausible, not measured.

### M3. `removeSection` and `moveSection` act on a position captured by the view, so two quick edits remove or move the wrong section
- Where: `OperatorCore/WorkspaceModel+SectionOrders.swift:38-49` with `writeOrder` at `:51-55`; the index is the row position in `App/Sources/SectionOrderSheet.swift:126` (`ForEach(Array(order.groupIDs.enumerated()), id: \.offset)`).
- Scenario: order [Verse, Chorus, Bridge]. The operator removes row 1 (Chorus) and, before the list is re-read, removes row 2 (the Bridge as drawn). Both calls read `arrangements` at entry, so the second computes from the old list: it removes the entry at index 2 of [Verse, Chorus, Bridge] and writes [Verse, Chorus], undoing the first removal and deleting the Bridge. The song's playing order is silently wrong. FIX-T knew of the lost update and left it; the cause is wider than a lost update: the id is the identity, the index is not (`id: \.offset`).
- Confidence: confirmed by reading; needs two actions inside one write-and-reload round, which is a click or a drag in quick succession.

### M4. Remove screen: not blocked while the screen is on air, and the confirmation understates what is lost
- Where: `App/Sources/ScreensDetail.swift:56-72`, `OperatorCore/SettingsModel.swift:212-224`, `UI006f_ScreenListEditing.swift:21-24`.
- Only the last screen cannot be removed. The only audience screen, a running screen, or the screen that is live to the projector can be removed with one confirmation. `OutputCoordinator.setProfiles` then stops that output at once (correct and shown in the text "Its output stops"). Not undoable.
- The dialog says "destination, mirrors and notes are forgotten". `removeProfile` also deletes the screen's entry in every Look (theme, layers) except when it hands it to a surviving screen of the same role, and the stage layout choice stays orphaned in app state (`StageModel.layoutChoices` is keyed by the removed id and never pruned). A Look entry handed to a sibling can change that sibling's appearance only when no sibling had its own entry (as designed).
- Scenario: Live, one audience projector and one more audience window. The operator meant to remove the window, selects the projector row by mistake, confirms: the projector goes dark mid-song; its theme and layers entry moves to the window.
- Confidence: confirmed by reading. Consider disabling Remove while that screen's output is running, or naming "and its Look settings" in the text.

### M5. A macro's function key bypasses the focus rules that every other show key obeys
- Where: `App/Sources/AppModel.swift:675` (called before `KeyRouting.decision`), `App/Sources/CuesKeyTrigger.swift:10-16`, `OperatorCore/UI006g_CueKeys.swift:81-88`.
- Checked and sound: the monitor is a local monitor (only while the app is active), it returns early for windows that cannot become main (menus, popovers, panels, the Identify labels), the Hardware Test and About windows are excluded, a text field or search field (`NSText`, `NSTextField`, `.textInput`, `.searchField`), a sheet, any held Command/Control/Option/Shift and a key repeat all stop it, and keys 122/120/99/118/96/97/98/100/101/109/103/111 are the correct F1 to F12 codes. No other binding uses an F key (grep of `keyboardShortcut` and `KeyboardKey`).
- What it does not check: it runs with a button, toggle, slider or pop-up focused, in every mode (Edit with an object selected, Stage canvas with a box selected), and in any other main window (for example Settings) that is not a text field. A macro that runs "Go Live", "Blackout" or "Next" therefore fires from a stray F-key press while the operator is editing slides or dragging a stage box. A function key is not typed text, so this is by design, but the design text says it "works when no text field has focus" and the show's own transport keys are stricter. Also: on a Mac keyboard the F-keys reach the app only with Fn held or the "Use F1, F2 etc. as standard function keys" setting; F11 and F12 may be taken by the system first.
- Confidence: confirmed that nothing between the monitor and `runKeyTrigger` checks mode or control focus; whether that is a defect is the owner's call. Listed medium because a macro can change Live.

## Low

### L1. Identify screens is not dismissed when the operator opens the screens, and is not tied to the screen list
- `App/Sources/ScreensIdentify.swift:18-47`. The overlays are at `.statusBar` level and output windows are at the shielding level (`DisplayOutput.swift:30`), so a running output stays on top: no output is covered. The labels do stay on the operator's and other displays for the remaining seconds after Open screens, and `ScreensIdentifier.shared.dismiss()` is called from nowhere else (quit, mode change). The hide is one cancellable task: nothing ticks while idle. Confirmed.

### L2. Hot-folder items can be put in a Media collection and then disappear from it
- `MediaModel+Collections.swift:26-34`, `:57-60` accept ids through `asset(_:)`, which also finds hot-folder items (`MediaModel.swift:128-130`), but `binChanged` and `loadCollections` prune with `assets.map(\.id)` (the bin only) (`:7-18`), and `MediaCollections.assets(in:from:)` is given `assets`. Drag a hot-folder tile onto a collection: the count rises; at the next bin change it silently drops. Confirmed.

### L3. Collections and macro keys can be overwritten after an unreadable stored value
- `MediaModel+Collections.swift:7-11` (`try?` then an empty `MediaCollections`; the next add writes the empty list plus one over the stored text) and `UI006g_CueKeys.swift:107-113` (an unreadable `cue.macro.keys` leaves no keys; the next `setKey` replaces them). Needs a damaged app-state row. Plausible. Also: `reload()` runs `pruneKeyTriggers()` before `loadKeyTriggers()` in `start()` (`CueModel.swift:134`, `CueModel+Settings.swift:33`), so the first prune sees an empty table and is a no-op; later reloads prune and save correctly. Two `setKey` calls in a row save whole snapshots through an async write; if the writes reorder, the older snapshot wins (plausible, low).

### L4. A removed stage-screen choice and several screen-keyed values are never pruned
- `StageModel.layoutChoices` (`StageModel.swift:34`, `:93`) and the Look entries of removed screens' siblings are the only references; see M4. Harmless unless an id is reused.

### L5. `slideActionPresentations` is read only in `reload()`
- `CueModel.swift:134`. The other presentations' rows and counts in the Cues sidebar do not change until a reload; only the open presentation is counted live (`CuesMode.swift:118-127`). A count can be stale after actions are added elsewhere or a slide is deleted. Confirmed by reading; cosmetic.

### L6. Newer stage layouts are lossy in an older build
- `Domain/StageLayout.swift:36-76` adds `isHidden` and `autoFit` as optional keys. An older build ignores them: a hidden Notes or Clock element is drawn on the stage screen again, and the next save by the older build drops the keys. Nothing blocks a library with these keys from opening in an older build (no schema bump). Stage layouts are not in program packages (grep of `ProgramPackage`), so packages are unaffected. Confirmed; low because mixed-version use is unusual.

### L7. "Hide" on a stage element has no guard for the element the stage needs
- `UI006e_StageModelExtras.swift:65-67`. The eye can hide Current slide on a custom layout and the stage screen then shows nothing from the show. A hidden Message element still lets a sent message through as the fallback banner (`StageLayout.swift` change at the banner check), which is the safe direction. No warning text for a layout with no visible Current slide. Confirmed.

### L8. The Media offline check blocks threads on a stalled volume and runs at every activation
- `MediaModel+Offline.swift:13-24`: `Task.detached` with `FileManager.fileExists` per item; cancelling the parent does not stop the detached work, and the check is requested at every app activation, mount and unmount while Media mode is shown (`MediaMode.swift:22-25`) and at every bin change. On a stalled network volume each run can hold a cooperative-pool thread. No timer or polling. Plausible.

### L9. Remove-screen and other destructive dialogs use the system red
- `ScreensDetail.swift:65`, `MediaMode.swift` (Delete collection), `StageInspector.swift:268`: `role: .destructive` is drawn red by the system. The project rule is red only for on air; the source comment on the Remove button claims no red. The button in the dialog is red. Cosmetic.

## Tests that do not test, or test less than they say

- Source-text tests: `FIXS_CellSlotTests.noLazyClosureOf...` (greps `CentrePane.swift` and `EditMode.swift` for the strings `workspace.slides[` and `CellSlot(at:`) and `FIXO_ViewSourceTests.theGridGivesTheModeToTheLiveCellOnly` (greps for `mode: live ? app.mode : .live`). They fail if someone renames a variable, and pass if a new lazy closure indexes the model by another expression. A real lazy `ForEach` is not run by any test (`CellSlot` itself, the pure part, is tested). I did re-check the sites by reading: `CentrePane` grid (`:219`), list (`:281`), Edit film strip (`EditMode.swift:84`) all use slots; no new view added a position read inside a lazy closure (checked every `ForEach` over a model array in changed files: `ScreensMode:97`, `StageInspector:178`, `CuesMode:71/85`, `MediaBinPanel:45` are snapshots whose closures read the element, not the model by index).
- Features with no test of their behaviour in the app (pure helpers are tested, wiring is not): the AppModel key monitor path for function keys (`handleCueKeyTrigger`: only `CueKeyGate` and the model's `runKeyTrigger` are tested, not the composition of `typing`, `sheetOpen`, window and mode); Edit's preview switch (selection cleared on switch, buttons disabled, nudge and delete keys inert in Stage/Broadcast: view state only); Identify screens (labels are tested, the window code is not); Remove screen against a running coordinator (`UI006f_ScreenListTests` covers the list functions and Looks, not `OutputCoordinator.setProfiles` after a removal); Locate (plan and kind check are tested, the panel and bookmark path are not); Stage Hide and Auto-fit on a real composited frame (`UI006e_StageAutoFitRenderTests`, three tests, six expectations, is the only render check).
- Tests that are sound and did exercise the race or failure they name: `FIXT_StepAcrossAwaitTests` (parks the read, edits the playlist, releases), `FIXT_SDILifecycleTests` (a held `enable`, event order, a readout during a held frame; each carries a fallback release so a regression ends the run), `FIXT_DeleteSlideTests`, `FIXT_HotFolderIndexTests`, `FIXT_StaleReloadTests`.
- Reports admit tests written after the code for UI-006c to UI-006g; they assert on pure outputs, so none looked vacuous, but they were not seen failing.

## Review-3 findings: verified fixed or still open

- H1 (huge media duration traps the bin): fixed. `ProgramReader.validateNumbers` bounds durations, pixel sizes, object frames, shape widths and sizes (`ProgramReader.swift:100-145`); display conversions go through `MediaClock` and `Int(saturating:)` (`MediaBinPanel.swift:278`, `MediaDockView.swift:311`, `MediaStrip.swift:79`). A library that already holds a bad value now draws "–:–".
- M1 (Next onto a passage across an await): fixed. `step(by:)` keeps the target by id and looks it up again after the read (`WorkspaceModel+Transport.swift:200-250`); the test releases a parked read after removing items.
- M2 (delete slide by position): fixed. `pendingDelete` holds a `UUID` (`CentrePane.swift:162-175`); `deleteSlide(id:)` re-checks after `flushDrafts` (`WorkspaceModel+Editing.swift:124-130`).
- M3 (package sizes overflow): fixed. Bounds and `saturatingAdding` (`ProgramReader.swift:131-144`, `ProgramImportPlan.swift:345`, `ProgramImporter.swift:88`, `:113`).
- M4 (failed SDI start leaks the port): fixed for the refused mode or keying (`SDIOutput.swift:259-264` closes the port). A start that fails later on the output's queue is closed through `onStop`, `sessionStopped` and `finish`; I read that chain and it closes once.
- M5 (main thread waits on the renderer lock): fixed. A separate `readoutLock` holds every value the main actor reads (`SDIOutput.swift:44-60`, `:95-102`).
- M6 (stop blocks the main actor and can overtake a queued start): fixed in the order of events: `finish` queues `session.stop()`, `ahead.stop()`, `port.close()` on the output's own serial queue behind any start (`SDIOutput.swift:333-352`), and the app passes `waitForPorts: false`. The cost moved: see M2 (never drained on display paths) and the note on the SDI analysis below.
- M7 (imported playlist media points at a bin entry never inserted): fixed for playlist items and announcements (`ProgramImporter.swift:277-292`, `remappingAssets`). Still open, as a low case: a package asset whose id already exists in the library with a different file is skipped as "already there" (`ProgramImportPlan.swift:196`), so slides name the other file. Needs two files with one id; only a hand-made package.
- M8 (status and handoff documents contradict each other): still open. `docs/14-current-status.md` still says "Updated: 2026-11-21", "1815 package tests pass" and "keyboard control has not" been seen; `docs/15-agent-handoff.md` still has three "read this first" sections and two different installed builds. Still carries a contact address at its line 7.
- Low items checked: L10 (title-matched windows) fixed by identifier-first (`KeyRouting.swift:219-231`); L13 (`openPlaylistItemID` observation) fixed (`WorkspaceModel.swift:42`); L1 (importer) backs up and refuses when lsof says nothing (`TestDataImporter.swift`); L3 hot-folder replacement is not changed (still `try?` to `[]`); L20 `uniqueKeysWithValues` replaced at five sites, one new use in `App/Sources/MediaLocate.swift:30` (keys are the URLs of one plan; a duplicate would trap; plausible only if two bin items share a path, which `relocateMediaAsset` refuses but the bin schema does not forbid).

## SDI and identity-after-await analysis (items 4 and 5)

- Start-failure close, readout lock, queued teardown, `stopWithoutWaiting`, `stop(waitForPorts:)`: order and deadlocks read through. No deadlock found: `queue.sync {}` is only used by `stop()` and `waitUntilStopped()` on the main actor; the queued work never calls back synchronously into the main actor (`onStop` and `clockStarted` use `Task { @MainActor }`; `SDIOutputSession.stop` waits on its own teardown queue). A stop that races a queued start runs after it (the test proves the order with a held `enable`). `clockStarted` after a stop stops the clock on the main actor. A retired output can still be asked for frames by the card's callback until `session.stop()` runs; `status` is already `.stopped`, the scene is still read, and nothing is sent after `close()`. Double `ahead.stop()` (start failure plus teardown) is the only repeated call and is idempotent by its use (not read in the engine; plausible). Double `port.close()`: not found; `finish` is guarded by `status == .running`.
- At quit: `stopScreens(waitForPorts: true)` calls `awaitRetiredTargets()` and `stop()` per output: the main actor waits for each output's queue, which includes `ahead.start`'s one second timeout at worst; no unbounded wait found. A profile change that restarts an SDI output blocks the main actor on `awaitRetiredTargets()` for the old output's teardown (up to about a second), as before the change but now in `startTarget` instead of `stop`.
- Identity-after-await: `step(by:)` re-finds by id before each use (confirmed). `deleteSlide(id:)` confirmed. `reloadOpen` and `reloadPlaylistItems` re-check the open item and playlist after the read. Remaining: `reloadOpen` has no ordering token, so two reloads of the same presentation in flight can land in the wrong order (plausible, low); `removeSection`/`moveSection` (M3); `writeOrder` reads `current` before `flushDrafts`. `moveSlide` computes positions at drop time but queues writes in order with a stale check (FIX-M design).

## Areas checked and found sound

- F1 to F12 key table, `CueKeyTriggers` one-key-one-macro, pruning, JSON round trip; a macro key is not reachable from text fields, sheets, popovers, menus, the Hardware Test window, or while the app is inactive.
- Dry run: `CueExecutor.makePlan` is pure (reads the macro library, no delivery, no log); `CueDryRunText` has no division and no `Int(Double)`.
- No app-state key collisions between the new features (`cue.macro.keys`, `media.collections`; grep of every use).
- Add screen starts disabled and in a window; Remove keeps at least one screen; `setProfiles` stops a removed screen's output; the Screens view falls back to the first profile if the selected one is gone; audience fall-backs (`profiles.first { role == .audience }`) are all optional.
- Identify screens: displays only, nothing sent to a card, allowed only while screens are closed, not main-capable windows (keys ignored), 3 seconds, one task, below the output windows' level.
- Edit preview: selection is cleared on switching to Stage or Broadcast; object-bar buttons, Align and Arrange are disabled there; no boxes are drawn or hit-testable; Edit nudge needs a selected object or lyric box (none after the switch); notes are not an input to the preview scene; `Int(renderWidth)` and the zoom percentage cannot trap. Preview scenes never touch the live `ShowState` (a throwaway deck).
- Stage: hidden elements are dropped in the composer, a hidden message element still shows a sent message as the banner; `StageAutoFit.floor` is total; decoding a style goes through the clamping initialiser; `pixelRect` and `TextRasterizer.padding` are total.
- Media: Locate checks the file kind, keeps the id (slide backgrounds that name the asset recover), refuses a path another item has, and reports instead of changing; collections never move or delete files; deleting a bin item prunes collections; export reports offline media as missing (`ProgramExporter`); no timer in the offline check.
- CellSlot: all three lazy sites carry their slide; `CellSlot` cannot be asked for a position that does not exist.
- Idle ticking added by the features: the Edit "Saved ... ago" reads once a second only while the view is on screen (cancelled with the view; one small `@State` write per second, no model read beyond two properties), Identify is one scheduled call, the Media offline check has no timer. Pre-existing 0.1 s and 1 s `TimelineView`s are unchanged.
- Safety rules: nothing in the new code writes to `ShowState` from an editing action; red is not used for anything that is not on air in new code except the system-drawn destructive buttons (L9); stage-only elements and notes are composed only for the stage role.

## What cannot be judged without running the app: a hands-on script

1. Keys. In Cues, give a macro "Select Look" the key F5. Check the Mac sends F5 (hold Fn if needed). With the main window focused and the slide grid active, press F5: the Look changes once. Hold F5: it runs once. Click in a text field and press F5: nothing. Open a sheet (Import) and press F5: nothing. Open Settings and press F5: note whether it runs. In Edit, select an object, press F5: note it runs (M5). Press F11 and F12: note whether the system takes them.
2. Screens. In Screens, Add screen: it appears off, in a window. Identify screens with screens closed: labels on each display for three seconds; press Open screens during the three seconds: confirm the output stays above the labels. With a window output running as the only audience screen, press Remove screen: read the text and confirm the output closes and the Look entries of that screen are gone (M4). Remove the last screen: the button is disabled.
3. Edit preview. Give the stage screen the Speaker preset, then in Edit press Stage: confirm the canvas shows the Standard layout, not Speaker (M1). Press Broadcast: no speaker notes. Press an arrow key and Delete with Stage selected: no object moves or disappears. Return to Audience and nudge an object with an arrow: it moves. Watch "Saved ... ago" while typing: it says Saving, then Saved, and the count rises each second.
4. Media. Unplug or rename a bin file's folder: the tile shows the warning mark and the callout reads "1 file is offline"; Locate points it at the moved file and a slide that uses it as background recovers. Add a hot-folder tile to a collection and make any bin change: note whether it stays (L2). Make a collection, delete a bin item that is in it, reopen the bin.
5. Stage. Add a Band preset layout, hide Next with the eye, turn Auto-fit on for the lyric with a long verse, assign it to the stage window: confirm the stage window hides Next and the lyric shrinks to about 64 px at the smallest.
6. Output memory. With display outputs only, open and close screens twenty times; compare the app's memory in Activity Monitor before and after (M2).
7. Section order. In a song with three sections in a custom order, remove the second and, at once, the third row: confirm which sections are left (M3).
8. Quit while live on a window output and with the simulated SDI device on: confirm quit completes within a few seconds.
