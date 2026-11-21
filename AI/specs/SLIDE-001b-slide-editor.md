# Brief: SLIDE-001b — slide editor for objects, and an interface clean-up pass

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/16-known-issues.md` (KI-019, KI-020, KI-028, KI-029, KI-036), `AI/reports/SLIDE-001a-report.md`, `AI/reports/STAGE-001b-report.md`, `AI/reports/MEDIA-001-report.md`, `Sources/Domain/SlideObject.swift`, `SlideContent.swift`, `Reflow.swift`, all of `Sources/OperatorCore` and `App/Sources`.

Catalogue: PRES-01 (slide editor), MEDIA-07 (object fills and effects), PRES-05 (reflow fixes).

## Part 1 — slide editor

**`OperatorCore`** (tests you write, new files under `Tests/OperatorCoreTests`): a `SlideEditorModel` (`@MainActor @Observable`) for the selected slide of the open presentation: add a text box, rectangle, ellipse, rounded rectangle or image (image through an injected file chooser result, so tests need no panel); select; move and resize through the `SlideObject` helpers; edit text, font, size, colour, outline, shadow, alignment; fill, stroke colour and width, corner radius; opacity; bring to front, send to back, forward, backward; duplicate (offset slightly); delete; undo and redo of every editing action (a simple snapshot stack bounded to 100 steps is acceptable). Edits save through the existing debounced path, update the preview deck, and never change the live output until re-triggered (reuse the rule already tested for text edits; add a test for an object edit).

**App**: an editor canvas for the selected slide (16:9, rendered by the compositor with the slide's resolved theme so it matches the output; selection outlines and handles drawn by the view on top), direct manipulation (drag to move, corner handle to resize, double-click a text box to edit its text), an inspector for the selected object, an insert menu, Delete key removes the selected object when no text field is active, Command-Z and Shift-Command-Z, Command-D duplicate. New objects are placed in free space where possible, not on top of existing ones (also apply this to new stage layout elements: reported after STAGE-001b).

## Part 2 — reflow fixes

- KI-019: re-flowing a presentation keeps speaker notes and slide objects for slides whose words are unchanged (match by folded primary text within the same section; unmatched notes are listed to the operator before saving, not silently dropped).
- KI-020: two blocks with the same section label but different words become separate sections, the second named with a number suffix ("Chorus 2"); identical repeated blocks still share one section.
- These touch `Sources/Domain/Reflow.swift` and `Sources/Persistence/LibraryStore+Structure.swift`. The coordinator tests `ReflowTests`, `ArrangementTests` and `SongStructureStoreTests` must keep passing unchanged; add new tests for the new behaviour. If a coordinator test contradicts the fix, stop and report rather than editing it.

## Part 3 — small fixes

- KI-028: the clipped "Background video" label in the theme editor.
- Any control whose label is truncated at the default window size: find by looking at your screenshots.

## Seeing it run

Launch the Debug app with a temporary `--library`, import a short song, open the slide editor, add a rectangle and a text box through the insert menu, change the fill colour through whatever control accessibility can reach, and save `AI/reports/SLIDE-001b-editor.png`; look at it and describe it. Then go live in window outputs and save `AI/reports/SLIDE-001b-live.png` showing the object on the audience preview. Quit the app. Keep each run under two minutes, never cover a display full-screen, never switch display modes, and leave nothing behind under `~/Library/Application Support/WORSHIPFLOW`.

## Do not modify

Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`. Existing migrations.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. Views stay thin; decisions live in `OperatorCore` or `Domain` with tests. Do not commit or change git state. Do not consult any advisor tool. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0. Paste the test summary line.
2. Both screenshots exist and you have described them.
3. `AI/reports/SLIDE-001b-report.md` records, per part, what was built, which paths you exercised in the running app, commands run with exit status, and everything not verified.
