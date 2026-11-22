# FIX-P: fixes from the independent review of FIX-N and FIX-M

Feature IDs: FIX-N, FIX-M, UI-005e. Model: Sonnet. One agent in the main folder, after FIX-O is committed. No migration.

The review of commits 58cc234 and 1e5db03 is `AI/reports/REVIEW-FIX-N.md`: no high finding, five medium (M1 to M5), six low. Read it in full; it gives file, line and failure scenario for each. Confirm each finding by a failing test (or by driving the running app through the debug hook where the review says "not judged without running the app") before fixing it; if a finding does not reproduce, say so with the evidence and leave the code alone.

## Items, in this order

1. **M1 (confirmed): Undo on the slide "Apply to all slides" was applied from does not undo the apply.** The group step must be on every slide that took part, including the source, so the first Undo from any of them restores all. The existing undo tests select another slide first: add tests that undo from the source slide.
2. **M2 (confirmed): group undo silently skips slides edited after the apply.** Decision: the undo restores the slides it still can and says so in one plain message ("Position restored on N of M slides; K were edited since"); it never overwrites a later edit silently and never fails silently.
3. **M3: a drag or nudge run cut short by a layout change** commits against the layout and element it started with, or is dropped whole; never a write to the wrong layout and never an empty undo step.
4. **M4: a drag ended by the window resigning key must not restart** and move the box a second time; the resign observer watches only the canvas's own window. Establish in the running app whether events keep arriving after the resign.
5. **M5: a stale Stage selection** (a box not in the current layout) is cleared when the layout changes, and arrows then move the slide selection as if nothing were selected.
6. **Low findings:** fix each that reproduces: the reorder tracker reset when the presentation or playlist changes; old slide text shown briefly after a reload while a draft is pending; arrows in a radio group after a canvas click go to the radio group; the nudge quiet period against the system key-repeat delay (read the system value, do not guess); the `gridHasFocus` reset.
7. **MIDI latency (review's note on the burst test):** measure, in the running app under a UI load (a 200-slide grid scrolling, a video playing), the delay from a MIDI message arriving to its command running. Report the numbers. If it exceeds 50 ms at the median or 200 ms at worst, record a known issue with the cause; do not redesign the router in this task.

## Rules

- Test-first, failing output recorded per item. New tests in `FIXP_*.swift`. Do not edit existing tests.
- Editing never changes Live. Typing, Space and Return in a text field never reach the show.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, or anything under `.claude/`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; use your own scratch folder, a temporary `--library` and `--silent-audio`, and stop only what you started.
- The repository is public: no personal strings in any file or picture. No wall-clock assertions. Known issues continue from the highest number in `docs/16-known-issues.md`.
- If you are running out of room, stop at an item boundary with the check passing and say what is done.
- Run each check in the foreground; leave no wait timers or background work; send one final message. Finish with `./scripts/check.sh` twice. Report to `AI/reports/FIX-P-report.md`; update the change log, known issues and hands-on checklist.
