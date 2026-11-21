# OUT-004 report: operator workspace (with LIB-001/2/3, SLIDE-005)

## Files
Created (OperatorCore): `DebouncedSaver.swift` (SaveClock, RealSaveClock, DebouncedSaver, ManualSaveClock), `WorkspaceModel.swift`, `WorkspaceModel+Library.swift`, `+Playlists.swift`, `+Editing.swift`, `+Transport.swift`, `ImportPlan.swift`. Deleted `Placeholder.swift`.
Created (tests, new only): `Tests/OperatorCoreTests/WorkspaceModelExtraTests.swift`, `ImportPlanTests.swift`.
App: created `Thumbnails.swift`, `ControlPanels.swift` (moved panels), `LibrarySidebar.swift`, `CentrePane.swift`, `TransportBar.swift`, `ImportSheet.swift`, `WorkspaceUIState.swift`; rewrote `ContentView.swift`, `WorshipFlowApp.swift`; edited `AppModel.swift`, `SoakConfig.swift` (SoakDeck); deleted `SampleSlides.swift`.
Not touched: coordinator tests, Package.swift, project.yml, Persistence, LibraryModels, other agent's files.
Screenshot: `AI/reports/OUT-004-workspace.png`.

## Decisions
- Return/Space/arrows/Escape are handled by the existing key monitor (skips text editing and sheets), not menu key equivalents, which would fire while typing. The Show menu lists them in item titles. Cmd-N, Cmd-I, Cmd-F, Cmd-E are real menu shortcuts.
- The model takes an injectable `SaveClock` (default real). Typed text: 2 s debounce, 5 s cap; place: 0.5 s. `flush()` writes both. App flushes on resign active and on terminate (terminateLater).
- Place is one JSON value under state key `workspace.place`.
- Deleting the last library is refused (error message). Slide add/move/delete is refused while a playlist item plays a custom section order (indices would be ambiguous); message tells the volunteer what to do.
- Deleting the open presentation loads an empty preview deck; live keeps its own copy. Next/Previous cross playlist items using `liveItemID` + `liveSlideIDs`; empty items are skipped; a second Next during a boundary hop is dropped.
- `ImportPlan` (OperatorCore) holds sheet split and break moves; with no moves it equals `Reflow.contents` (tested). Model gained `importLyrics(title:results:)`, `reflowPresentation(id:results:)`, `lyricsText(of:)`, `createPresentation`, `editSlide`, `createArrangement`, playlist CRUD, `goLive(at:)`.
- `--library <path>` launch argument added. Single `Window` scene (not WindowGroup). Soak mode opens no library and uses `SoakDeck`.
- Previews: one `Compositor` on a private serial queue; thumbnails cached (200), live previews uncached, 100 ms debounce (about 10/s max). Video background is not shown in previews (fallback colour only).

## Commands run
- `swift test --package-path Packages/WorshipFlowKit --filter OperatorCoreTests`: 35 tests passed (19 coordinator + 16 mine).
- `./scripts/check.sh`: exit 0; its package step: `Test run with 239 tests in 35 suites passed` (full suite, including the other agent's tests, which compiled by then).
- Debug app built via xcodebuild (BUILD SUCCEEDED) and run with a library in the scratchpad.

## Exercised in the running app (background accessibility control)
First-run seed (Songs, Service), import sheet with a bilingual song (live split, section names), save, thumbnails drawn by the Compositor, add to playlist, relaunch restored the open song and slide to preview, Go Live (window outputs opened, live previews of audience and stage updated), Next button, editing slide text (preview and thumbnail changed, live unchanged, row written to SQLite within ~3 s), Quick edit popover opened and "Apply to live" pressed (text unchanged).

## Not verified
- Keyboard keys (Return, Space, arrows, Escape) and Cmd shortcuts: background control cannot send them to a local monitor; the Import menu item showed disabled in the background. Not exercised.
- Quick edit with changed text through the UI (popover text could not be typed in the background); covered only by the unit test.
- Moving a break in the sheet, re-flow, search UI, drag reorder, rename/delete prompts, library switching, arrangement picker UI, error bar display, library-open-failure screen, force-quit kill test (KI-010), terminate flush.
- At launch the toolbar search field takes focus (screenshot shows its ring), so keys go to it until the operator clicks elsewhere. Needs a fix or a decision.
- No UI for creating arrangements (model API exists). Tests only; no UI tests.
- Performance with large libraries; the Release build; multiple displays.
- Real display outputs: I set the audience profile to Window in my own screen-profiles.json before going live so no display was covered; no display-mode change.

## Tests believed wrong
None.

## Cleanup
Removed `~/Library/Application Support/WORSHIPFLOW` (did not exist before; contained only the screen-profiles.json the run created). The run library is in the session scratchpad, not the real path. App quit.
