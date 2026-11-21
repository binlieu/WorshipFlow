# Brief: APP-001 — integration pass on the operator workspace

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/16-known-issues.md` (KI-011, KI-021 to KI-025), `AI/reports/OUT-004-report.md`, `AI/reports/SYS-002-report.md`, `AI/reports/OUT-003-report.md`, all of `App/Sources` and `Sources/OperatorCore`.

Catalogue: PRES-04 (arrangement interface), PRES-06 (theme interface), SCRN-08, MEDIA-08.

## Goal

Close the gaps between the workspace and the storage and rules that already exist. Five parts, in this order.

1. **Settings from SQLite (KI-025).** Screen profiles, Looks and props are read from and written to `LibraryStore` (`screenProfiles`, `saveScreenProfiles`, `looks`, `saveLook`, `deleteLook`, `props`, `saveProp(_:bookmark:)`, `bookmark(forProp:)`, `deleteProp`) instead of JSON files. On first launch with an existing `screen-profiles.json` or Looks file and empty tables, import them once, then leave the JSON files in place untouched (do not delete user files). Put the logic in `OperatorCore` (for example a `SettingsModel`, `@MainActor @Observable`) with tests: load, save, one-time import, and that a failed save sets an operator-readable error rather than throwing.
2. **Keyboard focus (KI-021).** At launch and after any sheet closes, keyboard focus is on the slide grid, not the search field. Space, arrows, Return and Escape reach the transport unless a text field or text editor is being edited. Command-F focuses search; Escape in the search field returns focus to the grid. Extract the "should this key go to the transport?" decision into a pure, tested function in `OperatorCore` (inputs: key, whether a text input is first responder, whether a sheet is open).
3. **Section order editor (KI-023).** For the open song: list its section orders, create, rename, delete, and edit one by adding sections from a palette, removing and drag-reordering entries; pick a section order for a playlist item. Uses the existing store and `WorkspaceModel` methods; add model methods with tests where missing.
4. **Theme editor (KI-023).** Create, duplicate, rename and delete custom themes; edit background (media, colour, image, transparent), and for each language block: font, size, colour, outline, frame (numeric fields are enough) and alignment, with a live thumbnail rendered by the compositor. Choose a theme for the open presentation (`setTheme(_:forPresentation:)`), and make custom themes appear in the per-screen theme picker. The presentation's theme must actually reach the outputs through `ThemeResolver` — add a model-level test that a presentation theme changes the audience scene and not the broadcast one.
5. **Live preview with video (KI-022).** If cheap, show the current video frame behind the audience live preview; otherwise leave KI-022 open and say so.

## Do not modify

- Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Persistence`, `Sources/Domain` files for stage layouts and timers, `Tests/StageTests`, `Tests/StageStoreTests`, `docs/19-data-dictionary.md`: another agent is adding schema v4 and stage rules there now. Use only store methods that exist today. Backward-compatible additions to other `Domain` files are allowed if genuinely needed.

## Seeing it run

Launch the Debug app with `--library <temporary path>` (it must not create or touch the real library or the real Application Support folder for this run; if settings JSON paths are derived from Application Support, make them derive from the library's folder instead so a temporary library is fully isolated). Exercise as much as you can through accessibility controls, save screenshots of the theme editor and the section order editor as `AI/reports/APP-001-theme-editor.png` and `AI/reports/APP-001-section-order.png`, look at them, describe them, and quit the app. Keep each run under a minute, never cover a display full-screen, never switch display modes: the owner is working on this Mac.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only. Views stay thin: decisions live in `OperatorCore` with tests. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests'` passes with your new tests; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step could not run because of the other agent's unfinished work.
2. Both screenshots exist and you have described them.
3. `AI/reports/APP-001-report.md` records, per part, what was built, which paths you exercised in the running app, commands run with exit status, and everything not verified.
