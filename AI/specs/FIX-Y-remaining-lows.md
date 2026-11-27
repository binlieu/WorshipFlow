# FIX-Y: the remaining low findings outside the output path

Feature IDs: SLIDE, MEDIA, CUE-33, LIB, OUT (screens), STAGE. Model: Sonnet. One agent in the main folder. Another agent is working in its own worktree on the capture sample text (files `App/Sources/UISnapshot*.swift`, `EditDesignCapture.swift`, `ComponentsBoard.swift`, `LooksProbe`, and tests that quote the sample song): do not touch those files. No migration: if an item seems to need a schema change, stop that item and report.

Read `AI/reports/REVIEW-5.md` (findings named below, with file, line and scenario), `AI/reports/REVIEW-4.md` (L1, L7), and `AI/reports/FIX-W-report.md` and `FIX-X-report.md` for what already changed. Confirm each finding in the code first; if one is not real, say so with the evidence.

## Items, each test-first, smallest change

1. **REVIEW-5 L2:** a video object ignores the in and out marks set on its clip. It must play between the marks, as the same clip does as a background or foreground layer.
2. **KI-280:** Clear closes the video-object players and restarts them from the first frame when un-cleared. Make Clear behave as Blackout does since FIX-X (players kept and silenced, nothing opened or waited for), if and only if the slide's own background layer also keeps playing under that Clear; match the existing rule for each kind of Clear (words, all, background, foreground) and state it. Stop still closes everything.
3. **L4:** focusing and leaving a mark or marker time field must not change the stored time (no rounding to 0.1 s unless the operator typed a new value).
4. **L7:** package import must refuse or repair, by the same rules the store and model use, marks that are equal or reversed and marks on a picture or sound; it must not silently drop a duplicate marker id or the marks and markers of a clip already in the library: say in the import result what was kept and what was not. Hostile input stays bounded.
5. **L8:** marker actions are JSON-decoded on every 50 ms tick and every view body. Decode once when the markers load or change.
6. **L10:** the marker list going stale after Add while the first load is in flight.
7. **L11:** correct the "stored only" comments in the source for fields that are now honoured (the data-dictionary text goes in your report: do not edit `docs/`). For the package format version: do not change the format; say in the report what an older build does with a video object and whether the version should rise (a decision for the coordinator).
8. **L14:** a typed key note or signal-chain label lost when the screen selection changes while its field has focus: commit the field to the screen it was typed for.
9. **L15:** the Look panel says a Look applies to every screen at once: correct the text where a screen keeps its own Look, and show in Show which screens do. Deleting a Look asks first, in FIX-V's style (no system red, Cancel is the default).
10. **L16:** one hung volume blocks every later offline check in Media: a check that does not return within a stated limit is abandoned for that volume and the next activation checks again; still one check at a time per volume, threads bounded.
11. **REVIEW-4 L1:** Identify screens is dismissed when the operator opens the screens and when the screen list changes.
12. **REVIEW-4 L7:** hiding a stage element the layout needs (the current slide on a layout with nothing else) asks first or is refused with a reason: choose the smaller, say which.

## Rules

- Out of scope, not to be touched: `OutputEngine/ScenePreparationGate.swift`, `MetalOutput.swift`, `OutputRenderer.swift`, `FrameEventLog.swift`, `TickTimeline.swift`, the SDI adapter, the scheduler, Fill/Key (REVIEW-5 M6 and L17 to L23 are another task).
- New tests in `FIXY_*.swift`; run each new test against the old code and record that it failed for the stated reason. Do not edit or weaken existing tests; the source-rule tests (`FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests`, `FIXU_ViewSourceTests`) pin sentences in the Show code: if a fix conflicts with one, stop that fix and list it.
- No new abstraction. No force unwraps. Swift 6 strict concurrency clean in Debug and Release. Nothing ticks while idle. Editing never changes Live. Red only for on air. Accessibility labels and keyboard behaviour kept. Speaker notes and stage layouts never reach an audience or broadcast screen.
- If any test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271).
- Do not edit `docs/`, `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/FIX-Y-report.md`: per item what the code did, the failing test, the change, what is not verified; then change-log text, known-issues text (unnumbered), hands-on entries.
- No git state changes: the coordinator commits. No advisor tool. No full computer control. Never open the owner's real library, never touch `/Applications/WorshipFlow.app` or `~/Library/Application Support/WORSHIPFLOW`; the owner's own copy of the app may be running: do not quit or disturb it; temporary `--library` only; stop only process ids you started; never `pkill` by name. No soak. No display or system settings.
- The repository is public: no personal strings.
- Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0, reading the exit status itself (timing-flaky `MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`: re-run once, report both). Do not leave monitors or wait loops running when you report.
- If you are running out of room, stop at an item boundary with the check passing and say what is done.
