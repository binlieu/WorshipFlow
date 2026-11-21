# Brief: OUT-004 — operator workspace (with LIB-001, LIB-002, LIB-003, SLIDE-005)

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/features/OUT-004-operator-workspace.md`, `docs/16-known-issues.md`, `AI/reports/OUT-002-report.md`, `AI/reports/OUT-003-report.md`, `AI/reports/SLIDE-003-report.md`, the coordinator test `Tests/OperatorCoreTests/WorkspaceModelTests.swift`, the public API of `Sources/Persistence` and `Sources/Domain`, and all of `App/Sources`.

## Goal

Replace the sample-slide spike interface with the real operator workspace backed by the SQLite library, with its logic in a tested `OperatorCore` target and only SwiftUI and AppKit views in the app.

## Do not modify

- Coordinator-owned tests. `Package.swift`, `project.yml` (already updated with `OperatorCore`), `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Persistence`, `Sources/Domain/LibraryModels.swift`, `Tests/SettingsStoreTests`, `Tests/PersistenceTests`, `docs/19-data-dictionary.md`: another agent is adding schema v3 there right now. Use only store methods that exist today (see the SYS-001 and SLIDE-003 reports). Its test target may not compile until it finishes; yours (`OperatorCoreTests`) compiles independently of it.

## What to build

**`OperatorCore`** (delete `Placeholder.swift`):
- `WorkspaceModel` (`@MainActor`, `@Observable`, final) with exactly the properties and methods the tests use: `libraries`, `selectedLibraryID`, `presentations`, `playlists`, `selectedPlaylistID`, `playlistItems`, `selectedPlaylistItemID`, `openPresentationID`, `slides`, `arrangements`, `searchResults`, `show`, `lastError`; `load()`, `flush()`, `dismissError()`, library, presentation, playlist, slide, search, arrangement and transport methods. It never throws to the interface: failures set `lastError` with a message a volunteer can act on.
- The place (open playlist, item, presentation, selected slide) is saved through the store's app-state keys and restored by `load()` into preview only.
- A change callback or observation point the app uses to publish scenes whenever `show` changes.
- `DebouncedSaver<Value>` and a `SaveClock` protocol with a real implementation and `ManualSaveClock` for tests (in the main target, not the test target, since the tests construct it).
- No AppKit, SwiftUI, Metal or AVFoundation imports in `OperatorCore`; `Observation` and `Foundation` only.

**App**:
- Open the library with `LibraryStore.open(at:)` in `~/Library/Application Support/WORSHIPFLOW/Library.sqlite` (ADR-0004 decision 11). If it cannot be opened, show a clear message with the path; do not delete or overwrite the file.
- Build the workspace window described in the feature spec. Native controls: `NavigationSplitView` or `HSplitView`, `List` with drag reordering, a slide grid with section headers and group colours, `.searchable`, toolbar items, and menus with keyboard shortcuts (Return to go live, right arrow or space next, left arrow previous, Escape clear, Command-F search, Command-N new presentation, Command-I import lyrics). Keys must not fire while a text field is being edited.
- Slide thumbnails and the per-screen live previews are rendered by the existing `Compositor` (`renderImage`) from the same scenes the outputs use, at reduced size, off the main thread, throttled (about ten per second for live previews). Never a second, separate drawing path.
- Import sheet: two text editors side by side (first language, second language), a lines-per-slide stepper, a live list of the resulting slides with section names, and buttons to move a break up or down (`Reflow.moveBreak`). Saving calls `importLyrics`, or `replaceContent` when re-flowing an existing presentation.
- Slide editing: a detail pane with both text fields and notes for the selected slide, saved through `DebouncedSaver`; a "Quick edit live slide" action that edits what is on screen.
- Keep the screens panel, Looks, props, background video chooser and the soak mode from the existing app working; move them into the right-hand column. Remove the sample slides.
- Flush pending saves when the app resigns active and on termination.
- Errors in a dismissible bar at the top of the workspace. Nothing modal over an output window.

## Seeing it run

After it builds, launch the Debug app once, wait for the window, capture a screenshot of the workspace window only (for example with `screencapture -l <window id>`, finding the id through CoreGraphics window listing), save it as `AI/reports/OUT-004-workspace.png`, and quit the app. Look at the screenshot yourself and describe what it shows. Use a temporary library path for this run if you add a `--library <path>` launch argument (recommended, and useful for tests); otherwise say that the real library file was created. Do not leave the app running. Do not cover a display full-screen, do not switch display modes, and keep any run under a minute: the owner is working on this Mac.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only. Scene provider closures run on render threads: hand them immutable snapshots. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests'` passes; the full suite too once the other agent's work compiles (say which you ran).
2. `./scripts/check.sh` exits 0, or you state exactly which step could not run and why.
3. The screenshot exists and you have described it.
4. `AI/reports/OUT-004-report.md` records files, decisions, commands run with exit status, which interface paths you actually exercised, and everything not verified.
