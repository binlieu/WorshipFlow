# FIX-O: drops on the slide grid and the media dock stop stalling (KI-180)

Feature IDs: UI (Show), SYS. Model: Sonnet. One agent in the main folder. No migration, no behaviour change.

FIX-M (`AI/reports/FIX-M-report.md`) found that a drop onto the slide grid or the media dock still stalls the main thread for 20 to 40 ms, because `WorkspaceModel.show` is one observed value: any change to it (a preview refresh, a selection, a live change) makes every view that reads any part of it re-evaluate, including the grid, the transport bar and the inspector. The owner's words on build 115: "drag and drop feels janky and laggy also sometime sluggish".

## What to do

1. **Measure first.** In a debug build with 200 slides and 100 bin items, count view body evaluations and main-thread time for: a drop on the grid, a drop on the dock's layer, a selection change, Next, a preview refresh, a bin hover. Use the instrumentation FIX-M left (say what you reused). Put the before table in the report.
2. **Split the observation, not the model's meaning.** Views must depend only on the part of the show state they draw: selection, live position, preview picture, per-layer media state, playlist, slide list and its thumbnails each observable on their own, so a change to one does not invalidate readers of the others. Prefer the smallest change that does it (separate `@Observable` holders or per-field observation behind the existing model's interface) over rewriting callers. The one command path, the output publication path and the undo path are not changed. Say which design you chose and why in the report; if it changes a public interface of `OperatorCore`, list every caller.
3. **Target:** under 8 ms on the main thread at a drop before control returns, and a grid drop re-evaluates only the affected cells plus the target's highlight. A Next press re-evaluates the two cells whose live state changed, the transport bar and the preview, not all 200 cells. Report before and after for each row of step 1, and say plainly what misses the target.

## Tests

Test-first for the logic: a change to each part notifies only that part's observers (counted with `withObservationTracking`), for every part named above; the settled state after any sequence of commands is identical to today's (replay a recorded command sequence against the old and new paths or against stored expectations); Live is unchanged by any edit. New files `FIXO_*.swift`. Do not edit existing tests. No wall-clock assertions: timings go in the report.

Drive the running app through the debug hook for the drops and for Next, Previous, Go Live, Blackout and Clear in every mode after the change, and report what happened: a missed observation shows up as a stale view, which unit tests do not see. Check every mode's screen for stale parts (grid live marker, transport bar, pills, state tag, inspector, preview, Stage and Screens panels).

## Rules

- Editing never changes Live. No change to what any command does.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, or anything under `.claude/`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; use your own scratch folder, a temporary `--library` and `--silent-audio`, and stop only what you started.
- The repository is public: no personal strings in any file or picture. Known issues continue from the highest number in `docs/16-known-issues.md`.
- If you are running out of room, stop at a boundary with the check passing and say what is done.
- Run each check in the foreground; leave no wait timers or background work; send one final message. Finish with `./scripts/check.sh` twice. Report to `AI/reports/FIX-O-report.md`; update the change log, known issues and hands-on checklist.
