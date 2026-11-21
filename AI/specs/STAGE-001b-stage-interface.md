# Brief: STAGE-001b — stage layout editor, timers and clocks in the workspace

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/16-known-issues.md`, `AI/reports/STAGE-001a-report.md`, `AI/reports/APP-001-report.md`, `Sources/Domain/StageLayout.swift`, `ShowTimer.swift`, `TimeFormat.swift`, `Sources/Persistence/LibraryStore+Stage.swift`, all of `Sources/OperatorCore` and `App/Sources`.

Catalogue: LIVE-01 (stage layout editor), LIVE-02 (current and next), LIVE-04 (countdowns and clocks), SCRN-03.

## Goal

Stage screens are driven by `StageComposer` with a chosen layout, the operator can edit layouts and run timers, and the stage picture updates every second while a clock or timer is visible.

## What to build

**`OperatorCore`** (with tests you write, in new files under `Tests/OperatorCoreTests`):
- `StageModel` (`@MainActor @Observable`): loads and saves custom layouts and timers through `LibraryStore`; the layout chosen for each stage screen (persist the choice per screen id; an app-state key is acceptable); create, duplicate, rename, delete layouts (the built-in one is read-only: editing it offers Duplicate); add, remove, move, resize and restyle elements using the `StageElement` helpers; create, rename, delete timers; start, pause, reset with the current time injected; failures set an operator-readable error.
- A pure function that says whether a layout needs a per-second refresh (it has a time-of-day or timer element) so the app only ticks when needed.
- Stage scenes are produced by `StageComposer.scene(layout:context:)` with the live `ShowState`, the timers, the time-of-day text from `TimeFormat` (12 or 24 hour is a setting), the current slide's speaker notes, and the stage message (nil for now). Test that the published stage scene changes when a timer value changes and that audience and broadcast scenes never contain timer or notes text.

**App**:
- Publish stage scenes from `StageModel`; a one-second timer republishes only while needed. Published snapshots stay immutable.
- A stage layout editor sheet: layout list (built-in and yours), a 16:9 canvas showing the layout rendered by the compositor with sample content, selectable elements that can be dragged and resized on the canvas (clamped by the helpers), an inspector for the selected element (kind, font size, colour, alignment, show second language, numeric frame), buttons to add each kind of element and to delete the selected one.
- A timers panel in the right-hand column: list with live values, start, pause, reset, add (countdown with minutes and seconds, elapsed, countdown to a time today), rename, delete. An overrun countdown is shown in the warning colour.
- A per-stage-screen layout picker in the screens panel.
- A clock style setting (12 or 24 hour, seconds on or off).

## Do not modify

- Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Domain`, `Sources/MediaEngine`, `Sources/RenderEngine`, `Sources/OutputEngine`, `Sources/Persistence`, and the test targets `MediaRulesTests`, `MediaEngineTests`, `RenderEngineTests`, `OutputEngineTests`: another agent is extending the media engine and compositor there now, keeping existing APIs source-compatible. Use those modules only through the API that exists today. If the package fails to compile solely because of its unfinished files, wait a few minutes and retry.

## Seeing it run

Launch the Debug app with a temporary `--library` path, open the stage layout editor and the timers panel through accessibility controls, start a countdown, and save `AI/reports/STAGE-001b-layout-editor.png` and `AI/reports/STAGE-001b-timers.png`; look at them, describe them, quit the app. Keep each run under a minute, never cover a display full-screen, never switch display modes, and leave nothing behind under `~/Library/Application Support/WORSHIPFLOW`.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. Views stay thin; decisions live in `OperatorCore` with tests. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests'` passes with your new tests; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step could not run and why.
2. Both screenshots exist and you have described them.
3. `AI/reports/STAGE-001b-report.md` records what was built, which paths you exercised in the running app, commands run with exit status, and everything not verified.
