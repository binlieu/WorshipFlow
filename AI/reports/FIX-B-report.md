# FIX-B report: review fixes in the operator core, app, domain and storage

Result: `./scripts/check.sh` exits 0. `swift test`: "Test run with 658 tests in 110 suites passed". App builds with no warnings from my files. No git state was changed.

Method note. Each finding got tests first. Where the fix was new API, the first run was a compile error (recorded below as "compile error"); for R1, R3, R13 I then added a do-nothing or old-behaviour seam so the tests ran and failed on their assertions, and recorded that output. For R4, R6, R8/R17, R11, R12, R15 and the clip rule I recorded only the compile error before the fix (no behavioural pre-fix run).

## Coordinator decision needing your eye (R13)
`ThemeEditingTests.aPresentationThemeChangesTheAudienceSceneAndNotTheBroadcastOne` (coordinator-owned) asserts that `workspace.liveThemeID` follows `setTheme` immediately, which is the old behaviour. I did not edit it. Instead `liveThemeID` keeps its meaning ("theme currently chosen for the live presentation") and a new `shownThemeID` carries the captured theme; the app publishes `shownThemeID`. That test passes unchanged but still encodes the old contract through the old name. Decide whether to update it.

## R1 key repeat and serial transport: fixed
- Fix: `KeyRouting.decision(... isRepeat:)` returns the new `.ignore` for transport keys on a repeat (Delete and other keys pass through, text fields still repeat). The monitor passes `event.isARepeat` and swallows `.ignore`. `WorkspaceModel.goLive/next/previous` run through a serial chain; Clear, Clear all, Stop and a direct trigger bump an epoch that abandons any queued or in-flight command that started before them.
- Failed before: KeyRepeatRoutingTests: compile error ("extra argument 'isRepeat'", "no member 'ignore'"). TransportSerialisationTests: `twoNextsArrivingTogetherBothAdvanceInOrder` ("b1" == "c1"), `stopDuringAPlaylistStepIsNotUndoneByTheStep` (isStopped false), `clearDuringAPlaylistStepStaysCleared` (isCleared false), `nextThenPreviousArrivingTogether...` ("b1" == "a1"). Pass now (30 repeated runs after I made the test start its tasks in a fixed order).
- Unverified: the real NSEvent monitor.

## R3 draft saves: fixed
- Fix: `pendingDrafts` leaves only on a successful write (or on a slide that no longer exists, with a message). Failure sets persistent `draftSaveProblem` (reason, not cleared by dismissing the error bar), retries at 2, 4, 8 ... 30 s, and `flush()`/`flushDrafts()` write drafts whose earlier write failed. Deleting a presentation or library drops only drafts of the presentations deleted; closing no longer clears everything. Reopening a song shows still-unsaved typing. Seam: internal `draftWriter`.
- Failed before (DraftSaveRetryTests, seams stubbed): `aFailedWriteIsRetriedWithBackOffUntilItSucceeds` (attempts 1 vs 2, 1 vs 3), `flushWritesADraftWhoseEarlierWriteFailed`, `closingTheOpenPresentationDoesNotThrowAwayAnotherSongsUnsavedTyping` (hasUnsavedDrafts false: blanket clear), `theIndicatorNamesTheReason...` (nil), `reopeningASongShowsTypingThatIsStillWaiting...` ("one" vs "typed"). All 8 pass now.
- Unverified: the red "not saved" bar (`UnsavedBar`) is SwiftUI, not tested.

## R4 menus and quit: fixed (pure decision tested; glue not)
- Fix: `QuitPolicy.decision(for:screensOpen:)` and `mayHide`. Quit with screens open asks (Cancel is the default button) and flushes all four models before terminating; last-window-closed does not quit while screens are open; the operator window's `windowShouldClose` is refused with a sheet while screens are open; Command-H is disabled while screens are open (app-visibility menu group replaced).
- Failed before: QuitPolicyTests compile error (`cannot find 'QuitPolicy'`). Pass now (5 tests).
- Unverified: the window-delegate proxy (`OperatorWindowGuard.swift`) refusing the close, the Quit alert and the disabled Hide were NOT exercised with screens open. I only launched the app with a temporary library, confirmed it runs, and that AppleScript Quit with screens closed flushes and exits. A system logout while screens are open will also show the Quit alert.

## R6 main-thread file stats: fixed
- Fix: `ImageUsage.pathsInUse` (only enabled audience/broadcast screens, props that are on, backgrounds of themes actually resolved, honouring hidden layers) and `ImageAvailabilityMonitor` (one pass at a time on a detached utility task, latest paths win). `AppModel.updateReadouts` no longer touches the file system.
- Failed before: compile error (`cannot find 'ImageUsage'`). Pass now (8 tests; the monitor test asserts the probe never ran on the main thread).
- Not covered: `MediaModel.usable` still checks readability synchronously on a user click (not on a timer).

## R8 Clear all: fixed
- Fix: `ShowCommand.clearAll`, `WorkspaceModel.clearAll()` plus `onClearAll` (the app wires it to stop the foreground clip), `TransportCommand.clearAll`, Shift-Escape, a Clear all button and menu item. `docs/features/OUT-002-screens-and-live-control.md` states both rules. Clear is unchanged.
- Failed before: compile error (`no member 'clearAll'/'onClearAll'`). Pass now (ClearAllTests, ClearAllCommandTests, ClearAllKeyTests).

## R11 reflow damage: fixed
- Fix: `ReflowImpact.sectionOrderLosses` (Domain), `LibraryStore.reflowImpact`, `WorkspaceModel.reflowImpact(id:results:)`, shown in the import sheet before saving. `emptyPlaylistItemIDs` marks an item "empty" in the playlist. Next and Previous now stop on an item with no slides and set `lastError` naming it, instead of skipping. Behaviour change to note: a playlist item whose song has no slides at all also stops Next now (it was skipped before).
- Failed before: compile error (`cannot find 'ReflowImpact'`). Pass now (9 tests).

## R12 settings and media flush and retry: fixed
- Judgement: `SettingsModel.flush()` and `MediaModel.flush()` already existed; the defect was that the app never awaited them. `flushWorkspace` now awaits workspace, stage, settings and media (called at resign-active and quit).
- Fix: `RetryingWriteChain` (keyed writes, back-off, flush retries, a newer write supersedes a failed older one) used by both models; `writeProblem` shown in the same persistent bar. Prop bookmarks survive a superseded failed add.
- Failed before: WriteRetryTests compile error (`extra argument 'clock'`, no `writeProblem`). Pass now (5 tests).
- Not done: `StageModel` writes are still not retried (not in the brief).

## R13 live theme: fixed (see decision above). KI-027 unchanged and tested (`editingAThemeThatIsInUseStillChangesTheScreensAtOnce`).
- Failed before (stub = old behaviour): `choosingAThemeForTheLivePresentation...` (lowerThird id vs fullScreen id), `movingToTheNextSlideOfTheLiveSong...` (non-nil vs nil). Pass now (6 tests).

## R14 texture cache flush: fixed (untested glue)
- `PreviewRenderer` calls `VideoTextureConverter.flush()` (already present in MediaEngine) at most every 2 s after a render. It lives in the app target; no test and no long-run memory measurement.

## R15 typing republishes everything: fixed
- Fix: `LiveOutputKey` + `LivePublicationGate`; `AppModel.showChanged` publishes only when the live deck, place, cleared state or live notes changed. Thumbnails read a new `appearanceRevision` (Look, theme, props, screens) instead of `sceneRevision`, so only the edited slide's thumbnail rebuilds (its render is already debounced 100 ms).
- Failed before: compile error (`cannot find 'LivePublicationGate'`). Before the fix every one of the 20 notifications in the test led to a full publish; now 0 (`typingInASlideThatIsNotLiveRepublishesNothing`). Pass now (6 tests).
- Not measured: no 200-slide timing. Thumbnail behaviour is SwiftUI glue, untested.

## R17 Close screens: fixed
- Fix: `MediaModel.screensClosed()` (stops the foreground clip, keeps the background), called from `AppModel.stopScreens`, so the registry closes the player and its audio.
- Failed before: compile error (`no member 'screensClosed'`). Pass now (2 tests). Sound actually stopping needs a real clip; not verified.

## Engine API wiring (coordinator note)
- Wired: `OutputCoordinator.warmUp()` at launch; `ImageWarmer.warm(scenes:)` for the selected preview slide on every enabled non-stage screen, debounced 300 ms, off the main actor, never awaited by a trigger, unreadable paths merged into the operator's unavailable-images list; `ScreenReadout.renderProblems` listed per screen row ("Left out of this screen"); `MediaRegistry.setOnAvailabilityChange` mapped to the new OperatorCore `ClipAvailability` and `MediaModel.availabilityChanged`.
- Rule and tests (ClipAvailabilityTests, 5, compile error before): a failed or stalled foreground ends and the error names the file and reason; a failed or stalled background reports and falls back to the theme; `.notOpen/.starting/.delivering` and other assets change nothing.
- Not wired or not verified: the registry callback, the warm-up and the panel text are app glue, untested; the warm-up only covers the selected slide, not the next one.

## Files
Created: `Sources/OperatorCore/{QuitPolicy,RetryingWriteChain,ImageAvailability,LivePublication}.swift`, `Sources/Domain/ReflowImpact.swift`, `App/Sources/OperatorWindowGuard.swift`, tests `FixB_{Transport,DraftSave,QuitPolicy,WriteRetry,ClearAll,LiveTheme,ReflowImpactModel,ImageAvailability,LivePublication,ClipAvailability}Tests.swift` in OperatorCoreTests and `FixB_ReflowImpactTests.swift` in DomainTests (all under `Packages/WorshipFlowKit/Tests`).
Changed: `Sources/OperatorCore/{KeyRouting,WorkspaceModel,WorkspaceModel+Transport,+Library,+Playlists,+Themes,SettingsModel,MediaModel}.swift`, `Sources/Domain/ShowState.swift`, `Sources/Persistence/LibraryStore+Structure.swift`, `App/Sources/{AppModel,WorshipFlowApp,ContentView,TransportBar,ControlPanels,ImportSheet,LibrarySidebar,Thumbnails}.swift`, `docs/features/OUT-002-screens-and-live-control.md`. `WORSHIPFLOW.xcodeproj` regenerated by `check.sh`.
