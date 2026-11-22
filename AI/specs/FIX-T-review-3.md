# FIX-T: fixes from the third independent review

Feature IDs: SYS, LIB, OUT, HW, CUE. Model: Sonnet. One agent in its own git worktree (other agents are in the main folder and other worktrees). No migration.

The review of commit a5ae9b2 is `AI/reports/REVIEW-3.md`: 1 high, 8 medium, 20 low. Read it in full; it gives file, line and failure scenario for each. For every item below, write the failing test first (record the failing output), then fix; if a finding does not reproduce, say so with the evidence and leave the code alone.

## Items, in this order

1. **H1: a program package with a huge, negative or non-finite media `duration` is stored and then crashes the Media bin every time it is drawn** (`MediaTile.clock` traps converting the number). Two fixes, both needed: the reader validates every numeric field of the manifest (duration, sizes, dimensions, counts, frames, positions: finite, in a sane range) and refuses or clamps as the package rules already do for other hostile input; and every place that formats or converts a stored number for display (`clock`, sizes, percentages) is total: no trap for any `Double` or `Int64`, so a library that already holds a bad value opens and shows "–:–" or similar. Search the app and package for `Int(` applied to a `Double` and for arithmetic on stored sizes; list what you made total.
2. **M3: summing manifest media sizes overflows and traps when the import sheet opens.** Same treatment: checked or saturating arithmetic, and a package whose sizes are absurd is refused with a plain message.
3. **M1: `step(by:)` indexes `playlistItems[j]` after an `await`,** so a playlist edited during a scripture resolve can crash or step to the wrong item on the live path. Resolve by item identity after the await (or bump the transport epoch on playlist edits, whichever fits the existing design; say which). Then audit every `await` in `OperatorCore` and the app's models for the same shape (an index or count read before an await and used after) and fix each.
4. **M2: `deleteSlide(at:)` checks an index, awaits, then uses it; and the delete confirmation holds a position, not a slide id,** so the wrong slide can be deleted. The confirmation and the delete carry the slide's id; a slide that no longer exists makes the delete a no-op with a message. This is user data: test the interleavings.
5. **M7: imported playlist media and announcement items are not remapped when a bin entry is skipped,** so they can point at a row that does not exist. Confirm it first (the reviewer did not re-read the payload claim), then remap to the existing entry the skip matched, inside the same import transaction.
6. **M4: a failed SDI `start()` never closes the port,** so the connector claim leaks and every retry fails. Close on every failure path; test with the simulator that start, fail, start again succeeds. **M6: SDI `finish()` blocks the main actor for up to about two seconds per output, and a stop can run before a queued start.** Move the wait off the main actor and serialise start and stop per output so they run in the order requested. **M5: `SDIFrameRenderer.lock` is held across the GPU wait while main-actor readouts take the same lock.** Readouts must not wait on a frame: copy the readout state under a short lock or publish it atomically. These three touch the output path: each is one small change with its own test; nothing here may be called more than **Simulated**.
7. **Low findings worth fixing now:** transport keys disabled by window title (a playlist named "Hardware Test" turns them off): key the check on the window's identity, not its title; `ShowHeader` reading an `@ObservationIgnored` property (stale header): read an observed part; the `wf-test-data-import` tool treating an unusable `lsof` as "free" (make it refuse unless `--force-unchecked` is given) and taking no backup (copy the library file set beside it before the first write, name printed). For the remaining low items, fix those that are one or two lines and confirmed; list the rest as known issues text for the coordinator.

Not in this task: M8 (the status and handoff documents contradict each other), which the coordinator fixes; migrations v11 and v13 depending on today's types (list what a frozen copy would need, do not change a shipped migration).

## Working in a worktree

- Touch only what the items need. Do not edit `App/Sources/CentrePane.swift`, `SlideGridCell.swift`, `EditMode.swift`, `scripts/check.sh`, `scripts/package-test-build.sh`, `FIXO_ViewSourceTests.swift` (another agent owns them in the main folder) or any `Edit*`, `Media*`, `Stage*` view file except where item 1's display formatting lives (`MediaTile.clock`: keep that edit to the formatting function).
- Do not edit `docs/`: put the change log, known issues (unnumbered; the coordinator numbers them) and hands-on checklist entries in your report. Write only `AI/reports/FIX-T-report.md`.
- Builds: `WF_DERIVED_DATA="<your own scratch folder>" ./scripts/check.sh`; keep one build folder, delete it when done. If only a timing-sensitive test fails with other builds running, re-run once and report both.
- Git: commit everything in your worktree to your own branch, message starting `fix(FIX-T):` and ending with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push, do not touch `main`, do not merge or rebase.

## Rules

- New tests in `FIXT_*.swift`. Do not edit existing tests. No wall-clock assertions.
- Editing never changes Live. No change to what any command does beyond the fixes.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, `.claude/`.
- No advisor tool. No full computer control. Never open the owner's real library; use a temporary `--library` and `--silent-audio`; stop only what you started.
- The repository is public: no personal strings in any file.
- If you are running out of room, stop at an item boundary with the check passing, commit, and say what is done.
