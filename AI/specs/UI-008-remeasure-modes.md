# UI-008: re-measure every mode against its design, fix or record the drift

Feature IDs: UI (Show, Edit, Media, Stage, Screens, Cues). Model: Sonnet. One agent in the main folder (no other agent is working; nothing else is in flight). No migration, no behaviour change.

Since the last full comparison (UI-005j) the app gained UI-006c/d/e/f/g, UI-007c/d/e/f, FIX-U and FIX-V. Each mode has a rectangle map (`scripts/design-map-<mode>.json`) compared by `scripts/compare-rects.py` against the design in `docs/UI`; the earlier reports (`AI/reports/UI-005j*`, `UI-006*-report.md`, `UI-007*-report.md`, `FIX-U-report.md`) say how each capture is made (the debug snapshot hook, a temporary `--library`, `--silent-audio`).

## What to do, in this order

1. **Find out why Show measures 32 of 220 within 1 pt today when UI-005j recorded 205 of 242** (FIX-U saw 32 of 220 both before and after its own change, so FIX-U is not the cause). Likely causes to check, not assume: a different window or capture size, a locked screen changing the backing scale or window frame, a changed capture hook or map, a constant offset applied to every element (then it is the measurement, not the layout). Reproduce UI-005j's method exactly on today's code and on commit `8590d5a` if needed. State the cause with evidence. If it is the measurement, fix the script or the capture so the number is true again; if it is the layout, find the commit that moved it.
2. **Measure all six modes, dark and light,** with the corrected method, and give one table: mode, appearance, mapped, within 1 pt, and the count at the last recorded measurement. List every element that is off by more than 1 pt with its offset.
3. **Fix real drift, largest first,** where the cause is small and local (a width, padding, spacing or font size): known items are the Stage inspector rows sitting 4 pt left of the design since UI-006e (KI-252), the Stage Auto-fit label at 12 pt against 13 (KI-253), and Edit's zoom field 1.8 pt wide (KI-197). After each fix re-measure that mode in both appearances and confirm nothing else got worse. A new control that the design does not have (Layers eye and lock buttons, the Section menu, the marks buttons, the Screens notes section) is not drift: leave it and list it as "not in the design".
4. **Extend the maps** for the designed elements that today's reports say are unmapped (Edit: Video button, Fit and Fill rows, Layers where the design has them; Media; Screens; Cues), only where the design really has the element.
5. Anything not fixed goes in the report as known-issue text with its measured offset.

## Rules

- Test-first for any logic you change; layout-only changes are verified by the rectangle tables. Do not edit existing tests; source-rule tests (`FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests`, `FIXU_ViewSourceTests`) pin sentences in the Show code: if a fix conflicts with one, stop that fix and list it.
- FIX-U's rule stands: do not undo its three kept splits (`ToolbarStateTag`, `ShowSlimRow`, `TransportText` with `fixedSize`). Views read `showParts`, `slideList`, `layerParts`; nothing ticks while idle; lazy cells carry their value.
- Editing never changes Live; red only for on air; accessibility labels and keyboard behaviour kept.
- After a change to a stored property of a shared domain type, or if any test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` before judging (KI-271).
- Do not edit `docs/` (put change log, known issues unnumbered, hands-on entries in the report), `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/UI-008-report.md`.
- No git state changes at all (no add, commit, stash, checkout): the coordinator commits. No advisor tool. No full computer control. Never open the owner's real library and never touch `/Applications/WorshipFlow.app` or `~/Library/Application Support/WORSHIPFLOW`; temporary `--library` only; stop only process ids you started; never `pkill` by name. Do not change display or system settings.
- The repository is public: no personal strings in any file.
- Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0 (if only `MIDIRouterTests`, `ToolProcessRunnerTests` or `ScriptureLibraryTests` fail on timing, re-run once and report both).
- If you are running out of room, stop at a mode boundary with the check passing and say what is done.
