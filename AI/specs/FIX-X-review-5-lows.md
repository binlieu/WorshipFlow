# FIX-X: three low findings of the fifth review: L3, L9 and L13

Feature IDs: SLIDE (video objects), MEDIA, CUE-33 (markers). Model: Sonnet. One agent in the main folder; nothing else is in flight. No migration.

Read `AI/reports/REVIEW-5.md` findings L3, L9 and L13 (file, line and scenario), and `AI/reports/FIX-W-report.md` for what changed yesterday in the same files. Confirm each in the code first; if one is not real, say so with the evidence.

## Fixes, each test-first

1. **L3: Blackout closes the video-object players, and lifting it restarts each clip from its first frame.** A Blackout that is lifted must show the video objects where they would have been had they kept playing (the same rule the background and foreground media layers follow under Blackout: read how they behave and match it; if they pause instead, match that and say so). Players stay bounded (the limit of 4 is unchanged) and are still released when the slide leaves Live, on Clear and on Stop. Blackout itself must stay immediate and must never wait for a player. Say what Clear does today and leave it. Tests with fake players and an injected clock; no wall-clock assertions.
2. **L9 and L13: deleting a marker is one click with no confirmation and no undo,** in Media and in Cues. A marker that has actions must ask before it is deleted, naming the marker and how many actions go with it; a marker with no actions may be deleted at once. Use the app's existing confirmation style (FIX-V removed the system red from confirmations: red is only for on air; follow what FIX-V did). Keyboard: Return must not be the destructive choice by default; Escape cancels. Accessibility labels kept. Both places use one shared decision (a pure function "does this delete need a confirmation, and with what text") that is unit tested; the view wiring is listed for hands-on. No undo system: do not build one.

## Rules

- Out of scope and not to be touched: `OutputEngine/ScenePreparationGate.swift`, `MetalOutput.swift`, `OutputRenderer.swift`, the SDI adapter, the scheduler, Fill/Key. If L3 cannot be fixed without touching them, stop that item and report.
- New tests in `FIXX_*.swift`. Do not edit or weaken existing tests; source-rule tests (`FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests`, `FIXU_ViewSourceTests`) pin sentences in the Show code: if a fix conflicts with one, stop that fix and list it.
- Smallest change. No new abstraction. No force unwraps. Swift 6 strict concurrency clean in Debug and Release. Nothing ticks while idle. Editing never changes Live.
- If any test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271).
- Do not edit `docs/` (change-log text, known-issues text unnumbered and hands-on entries go in the report), `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/FIX-X-report.md`.
- No git state changes: the coordinator commits. No advisor tool. No full computer control. Never open the owner's real library and never touch `/Applications/WorshipFlow.app` or `~/Library/Application Support/WORSHIPFLOW`; temporary `--library` only; stop only process ids you started; never `pkill` by name. Do not run a soak. Do not change display or system settings.
- The repository is public: no personal strings in any file.
- Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0 (if only `MIDIRouterTests`, `ToolProcessRunnerTests` or `ScriptureLibraryTests` fail on timing, re-run once and report both).
