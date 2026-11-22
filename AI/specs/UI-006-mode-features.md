# UI-006c/d/e/f/g: the features each mode's design draws and the app lacks

Feature IDs: UI-006c (Edit), UI-006d (Media), UI-006e (Stage), UI-006f (Screens), UI-006g (Cues). Model: Sonnet. One agent per mode, each in its own git worktree, at the same time. This brief is the same for all; the table says what differs.

UI-005c to g matched each mode's rectangles and left out every control whose feature did not exist ("open, needs a feature slice"). This slice builds those features, most useful to an operator first.

| Slice | Mode | Design | The open list | Your files |
|---|---|---|---|---|
| UI-006c | Edit | `docs/UI/02-editor.png`, mockup `02-editor.html` | "left out" / "open" rows in `AI/reports/UI-005c-report.md` | `App/Sources/Edit*.swift`, `SlideObjectsEditor.swift`, `ThemeEditorSheet.swift`, `SectionOrderSheet.swift` |
| UI-006d | Media | `05-media-audio.png`, `.html` | `AI/reports/UI-005d-report.md` | `App/Sources/Media*.swift`, `BinPlayer*.swift`, `HotFolderSupport.swift`, `AudioPanel.swift` |
| UI-006e | Stage | `04-stage.png`, `.html` | `AI/reports/UI-005e-report.md` | `App/Sources/Stage*.swift`, `TimersPanel.swift` |
| UI-006f | Screens | the Screens picture and mockup named in `AI/reports/UI-005f-report.md` | that report | `App/Sources/Screens*.swift`, `ControlPanels.swift`, `SDIProviders.swift` |
| UI-006g | Cues | `06-cues.png`, `.html` | `AI/reports/UI-005g-report.md` | `App/Sources/Cues*.swift`, `CueSupport.swift` |

## Read first

`CLAUDE.md`; `AI/specs/UI-005-design-match-plan.md` (the owner's decisions and "what the design may not override" bind you); your UI-005 report and audit rows; `docs/MASTER-SPEC.md` and the `docs/features/` spec for each feature you take; `App/Sources/WFControls.swift`, `Components.swift`, `DesignTokens.swift`; `AI/reports/FIX-O-report.md` (views read `showParts`, `slideList`, `layerParts`, never the whole show state).

## What to do

1. **List and rank.** From your report's open list, write the candidate features with, for each: what the operator gains, what it needs in the model (nothing, a pure function, a new stored field), and its size. Rank by operator value over size.
2. **Build, top down, as complete vertical slices:** model logic in the package with tests first, then the control at the mockup's rectangle with the shared controls and type styles, then the hands-on entry. A feature is taken only if you can finish it: working, persisted where it should persist, undoable where editing is undoable, keyboard reachable, accessibility labelled, in dark and light. No dead controls, no faked data, nothing drawn as fact that the app has not observed.
3. **No schema change in this slice.** A feature that needs a new stored column or table is **not built**: list it under "needs a migration" with the exact fields you would add, so the coordinator can brief one migration for all modes. Features that can live in existing fields or settings stores may be built.
4. **No public interface change to shared package types** (`WorkspaceModel`, `ShowState`, `ObservedShow`, output and scheduler types, `LibraryStore`'s existing methods). Additive new files and new methods in your own new package files are fine; if you need a change to a shared type, make it additive, keep it small, and list it.
5. **After each feature:** the mapped rectangles for your mode still pass (`scripts/compare-rects.py` with your `scripts/design-map-<mode>.json`, extended for the new control); report the table.

## Working in a worktree beside other agents

- You are in your own git worktree on your own branch; the coordinator merges. **Touch only your files** (the table) plus new files with your prefix (`Edit*`, `Media*`, `Stage*`, `Screens*`, `Cues*`; package files and tests `UI006<letter>_*.swift`).
- Do not edit shared app files (`WFControls.swift`, `Components.swift`, `DesignTokens.swift`, `ContentView.swift`, `AppModel*.swift`, `WorkspaceUIState.swift`, `CentrePane.swift`, `UISnapshotRun.swift`), scripts other than your own map file and your own new scripts, `project.yml`, or `Package.swift` unless a new test target is truly needed (list it). One clearly commented line in a shared file is allowed where unavoidable; list it.
- Do not edit `docs/` (change log, known issues, checklist, feature specs): put those entries in your report under "Change log", "Known issues" (unnumbered; the coordinator numbers them), "Hands-on checklist", "Feature spec updates". Write only `AI/reports/UI-006<letter>-report.md`.
- Builds: use your own build folder: `WF_DERIVED_DATA="<a scratch folder of your own>" ./scripts/check.sh`. Keep one build folder and delete it when done. Several builds run at once: if only a timing-sensitive test fails, re-run once and report both.
- Git: when finished, commit everything in your worktree to your own branch, message starting `feat(UI-006<letter>):` and ending with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push, do not touch `main`, do not merge or rebase.

## Rules

- Test-first for logic. Existing tests are not edited. No wall-clock assertions.
- Editing never changes Live; red only for on air; output mapping stays visible; speaker notes never reach an audience screen; a hardware feature is at most **Simulated** and is labelled so.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, `.claude/`.
- No advisor tool. No full computer control. Never open the owner's real library; use a temporary `--library` and `--silent-audio`; stop only what you started.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture.
- If you are running out of room, stop at a feature boundary with the check passing, commit, and say exactly which features are done.

## Done means

Your report has: the ranked list; for each built feature what it does, its tests, and its verification level (Implemented, Unit Tested, Simulated; nothing higher); the features not built and why; the "needs a migration" list with fields; the rectangle table; shared-file lines; the docs entries; the check's exit status and test count; what is not verified.
