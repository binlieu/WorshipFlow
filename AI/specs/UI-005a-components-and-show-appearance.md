# UI-005a: shared components and Show, matched to the design

Feature ID: UI-005a. Model: Sonnet. One agent owns the app's view files. Starts after FIX-G is committed.

## Read first, in this order

1. `CLAUDE.md`.
2. `AI/specs/UI-005-design-match-plan.md`: the owner's decisions, the coordinator's defaults, what the design may not override, and how the match is checked. All of it binds this task.
3. `AI/reports/UI-005-audit-show.md`: the work list. Every row marked S or M is yours. Rows marked L belong to UI-005b: do not build them, and do not draw a control for a feature that does not work yet.
4. The cross-screen component rows in `AI/reports/UI-005-audit-edit-media-stage.md` ("Shared") and `AI/reports/UI-005-audit-screens-cues-looks.md` ("Cross-screen components").
5. The design: `docs/UI/screens/01-operator-show.png`, `01b-operator-show-quick-edit.png`, `09-operator-show-light.png`, `08-components.png`, `10-components-light.png`; `docs/UI/mockups/01-operator-show.html`, `08-components.html`, `ui.css`, `ui.js`; `docs/UI/design-tokens.json`; `docs/UI/README.md`. The pictures win where sources disagree.

## What to build

1. **The comparison tool first.** Extend the debug snapshot hook so the app can be captured at exactly 1440 by 900 points at 2x, in dark and light, in a state that reproduces each design picture as closely as the data allows (a seeded temporary library with the same number of libraries, songs, playlist rows, slides, dock tiles, props, Looks and timers, and with the design's sample names where they are plain data). Add `scripts/compare-design.sh` (or a small Swift or Python tool it runs) that takes a design picture and an app capture and writes a side-by-side and a difference image, and prints the share of pixels differing by more than a small tolerance, overall and per named region (toolbar, sidebar, playlist, centre, dock, inspector, transport bar). It is run by hand, not by `scripts/check.sh`. Capture the "before" set now.
2. **The shared components, built once to the design** in `Components.swift` and `DesignTokens.swift` (split into more files if it helps): button variants, pills and badges, tags, segmented control, toggle, checkbox, slider, pop-up button, text field, search field, tabs with the underline, section headers, list rows, tiles and thumbnails with the idle outline and the live ring at the design's gap, monitors with their badges, meters, the message card, tooltips and key hints. Each takes its numbers from named tokens; add tokens where `ui.css` has a value the token file lacks, and keep the existing parity test between the asset catalog and `design-tokens.json` passing (extend it; do not edit `docs/UI`). Every component keeps its accessibility label, value and keyboard behaviour; custom controls must work with the keyboard and VoiceOver exactly as the system control they replace.
3. **Show, region by region,** closing every S and M row of the audit: window and panel widths, toolbar (including the sidebar toggle button if the audit marks it M and it needs no model change; the service-date title is L and waits), sidebar and library list, playlist rows, centre header and slide grid, media dock and controller, the inspector's monitors, Look row and tabs, the stage message, the transport bar, the error message card (the card and its one existing action; the extra actions are L). In both appearances.
4. **The extras the design does not show** go where the plan says: Quick edit stays in the centre header only; "Edit live slide…" and the live-override row share one slim row under the monitors; the screens button moves from the transport bar to the toolbar; the Cues tab content and the scripture row use the new components. Nothing the operator can do today is lost; list where each one went.
5. **The transport bar is hidden in Edit, Stage and Screens.** Keyboard transport keeps working in every mode; add a test for that at model level and say how the operator sees what is live in those modes.
6. Use the new components in the other modes only where it is a drop-in replacement of the same control (so the app does not look half old and half new); layout changes in those modes belong to their own slices.

## Limits

- No model or schema change, no new feature, no change to what any command does. If a row cannot be closed without one, leave it and list it for UI-005b.
- Editing never changes Live; Preview, Live, Clear, Blackout and Stop keep their meanings; red only for on air; the SIMULATED mark stays.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder. Existing tests may be edited only where they assert a layout number or a label that the design changes; list each.
- No git state changes. No advisor tool. No full computer control.
- Never open the owner's real library. If you launch the app: your own uniquely named scratch folder, a temporary `--library`, `--silent-audio`, stop only what you started, nothing left in the home folder, no packaged builds left in `dist/`.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture.

## Done means

- Every S and M row of the Show audit and the shared-component rows is closed, or listed in the report with the reason.
- `AI/reports/UI-005a-report.md` holds, for each of the five design pictures: the app capture, the side-by-side, the difference image, the differing share before and after per region, and a plain explanation of every region still above tolerance (sample text that differs is a valid reason; a wrong size is not). Pictures go in `AI/reports/UI-005a-*.png`, scaled so each is under 1 MB.
- `./scripts/check.sh` exits 0, run twice; test counts reported truthfully.
- `docs/17-change-log.md`, `docs/16-known-issues.md` and `docs/hands-on-checklist.md` updated.
- The report ends with: what the owner should look at first, what was not verified (real pointer, VoiceOver, a second display), and the open rows handed to UI-005b.
