# Brief: OUT-002 screens, roles and live control

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/features/OUT-002-screens-and-live-control.md`, `docs/16-known-issues.md`, the three coordinator test files `ShowStateTests.swift`, `SceneComposerTests.swift`, `OutputRouterTests.swift` under `Packages/WorshipFlowKit/Tests/DomainTests/`, and the existing code in `Sources/Domain`, `Sources/OutputEngine` and `App/Sources`.

## Goal

Replace the spike's ad hoc live handling with a tested show state, per-role scene composition, screen routing with failover, and an output coordinator; wire them into the existing operator window.

## Do not modify

- Test files marked "Owned by the coordinator". Add new test files freely.
- `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Persistence`, `Tests/PersistenceTests`, and these Domain files owned by another agent working at the same time: anything it adds for search folding, libraries, presentations, slides, playlists (for example `SearchFolding.swift`, `Library*.swift`, `Presentation*.swift`, `Playlist*.swift`). Do not create files with those names. If the package fails to compile because of that agent's unfinished files, do not fix them; wait a minute and retry, and run your own tests with `--filter`.

## What to build

**`Domain`** (Foundation only, new files; the tests fix the API):
- `ShowDeck`, `ShowCommand`, `ShowState` with `apply(_:)`, `previewDeck`, `liveDeck`, `liveIndex`, `selectedIndex`, `liveSlide`, `nextSlide`, `isCleared`, `isStopped`. `ShowState` is `Equatable` and `Sendable`. A fresh state is stopped.
- `SceneComposer.scene(for:state:clockText:)` with `clockText` defaulting to nil. Keep default styles in one place so themes can replace them later (SLIDE-002).
- `OutputDestination` (`.display(UInt32)`, `.window`), `ScreenProfile`, `RoutingFault` (`.displayMissing`, `.displayInUse(by:)`, `.operatorDisplay`, each with an `operatorMessage` a volunteer can act on), `RoutingPlan`, `OutputRouter.plan(profiles:availableDisplays:operatorDisplay:)`.

**`OutputEngine`**:
- `OutputCoordinator` (`@MainActor`): given profiles, a way to list displays, and a factory that makes an `OutputTarget` for a destination, it starts, stops and re-plans outputs. On a display change it stops only the outputs whose plan changed. It exposes per-screen status (running, hidden, stopped, fault message) and statistics. Inject the display list and the factory so tests can use fakes; add tests for start, a display disappearing, a display returning (the screen stays faulted until the operator restarts it — never auto-redirect; auto-resume on the same display is allowed and should be tested), and stop.
- Fix KI-008: report "hidden" when the window is occluded instead of looking like a stall.
- `SleepGuard`: holds a power assertion that prevents display and idle system sleep while at least one output runs; released when none do. Test the counting logic with an injected assertion backend.
- An offscreen benchmark test in `RenderEngineTests` or a new test target file: render four 1920×1080 scenes (audience, stage, broadcast, audience again) per frame for 600 frames into offscreen textures, wait for GPU completion each frame, and print mean and worst frame time. Assert only a generous ceiling (mean under 16 ms) so it does not flake; the numbers go in the report.

**App**:
- Replace the spike's live logic in `AppModel` with `ShowState`, `SceneComposer` and `OutputCoordinator`. Keep the sample slides for now (libraries arrive with a later slice).
- A screens panel: list of screen profiles (name, role picker, destination picker listing displays by name plus "Window"), enable toggle, status and fault message, frame counters. Persist profiles as JSON in Application Support for now (the SQLite table comes later; say so in the report).
- Default profiles on first run: "Audience" on the first non-operator display if there is one, else a window; "Stage" in a window; "Broadcast" in a window, disabled.
- Buttons and keys: Go Live on the selected slide (Return), Next (right arrow, space), Previous (left arrow), Clear (Escape), Stop. Selecting a slide changes preview only.
- No alert, sheet or system dialog may ever be attached to an output window (NFR-08). Errors show in the operator window.
- Keep soak mode working.

## Constraints

- Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only.
- The scene provider closures run on render threads: hand them immutable snapshots, never the observable model.
- A slide trigger must reach every output on the same frame: publish one snapshot that all outputs read (NFR-04).
- Do not commit, stage, stash or reset anything in git.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit` passes (or, if the other agent's files are mid-edit, your filtered run passes and you say so).
2. `./scripts/check.sh` exits 0.
3. A 20-second windowed soak exits 0 or, if the window is occluded by a full-screen app, reports "hidden" clearly; say which happened.
4. `AI/reports/OUT-002-report.md` records files, decisions, benchmark numbers, commands run with exit status, and everything not verified.
