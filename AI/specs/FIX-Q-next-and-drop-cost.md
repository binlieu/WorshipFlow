# FIX-Q: Next, Previous and drops cheap on the main thread (KI-186, KI-187, KI-189)

Feature IDs: OUT, UI (Show), CUE, SYS. Model: Sonnet. One agent in the main folder. No migration.

Measured in a debug build with 200 slides and 100 bin items (`AI/reports/FIX-O-report.md`, `AI/reports/FIX-P-report.md`): Next and Previous hold the main thread 20 to 35 ms, inside the model call that composes scenes and publishes them to the outputs; a grid drop still stalls 8 to 38 ms; MIDI commands at one every 7 ms under load fall more than a second behind for the same reason. The owner's words: "drag and drop feels janky and laggy also sometime sluggish".

## Items, in this order

1. **The release build is part of the gate.** `scripts/check.sh` compiles the app in Release as well as Debug (compile only; keep the added time small and say how much it is). A release-only compile error reached packaging on 2026-11-22 unseen.
2. **Measure in a release build first.** Make the timing hooks usable in a release-configuration measuring build without shipping them (a build setting or flag, off in the packaged app; prove it is off). Report Next, Previous, Go Live, Blackout, Clear, each drop kind and the MIDI burst in debug and in release. If release already meets the targets for some rows, say so and do not change code for them.
3. **Next and Previous.** Profile where the 20 to 35 ms goes (scene composition per output, text layout, thumbnail or preview renders, database reads, publication, observation). Fix causes, keeping the meaning of every command and the order of what reaches each output exactly as today. Likely candidates, to be confirmed by the profile, not assumed: composing each output's scene once and not again for preview; caching text layout per slide content and theme revision; doing preview and thumbnail work after the live publication and off the main thread; no database read on the Next path. The live outputs' frame for the new slide must not arrive later than today: measure command-to-publication time before and after.
4. **Drops on the grid and dock.** The remaining cost after FIX-O: the dropped cell's thumbnail, the grid's own body and layout. Render the thumbnail off the main thread with the old picture shown until it lands; do not rebuild the grid body for a change to one cell.
5. **MIDI burst.** After item 3, repeat FIX-P's measurement (`scripts/fixp-run.sh`). If commands still queue behind one another, coalescing is **not** allowed for Next and Previous (each press is a step); say what remains and update KI-189.

## Targets

Release build, 200 slides, 100 bin items: Next and Previous under 8 ms on the main thread at the median and 16 ms at worst; drop stall under 8 ms; MIDI at one message every 7 ms under load keeps up (median under 50 ms, worst under 200 ms). Report honestly each row that misses, with the cause.

## Tests

Test-first for logic you add (caches keyed by content and theme revision go stale correctly; preview work never precedes or delays the live publication; the sequence of published scenes for a recorded command sequence is byte-identical to today's by digest, for audience, stage and broadcast outputs including Fill and Key). New files `FIXQ_*.swift`. Do not edit existing tests. No wall-clock assertions: timings go in the report. Drive the running app through the debug hooks in every mode after the change and check for stale views (grid live marker, preview, live monitor, Stage and Screens panels, state tag).

## Rules

- Editing never changes Live. No change to what any command does or to output content. Anything that touches the shared output scheduler is one small, reviewed change, described in the report.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, or anything under `.claude/`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; use your own scratch folder, a temporary `--library` and `--silent-audio`, and stop only what you started.
- The repository is public: no personal strings in any file or picture. Known issues continue from the highest number in `docs/16-known-issues.md`.
- Keep at most one scratch build folder and delete it before you finish.
- If you are running out of room, stop at an item boundary with the check passing and say what is done.
- Run each check in the foreground; leave no wait timers or background work; send one final message. Finish with `./scripts/check.sh` twice and one run of `scripts/package-test-build.sh` into a scratch output if the script allows it (do not leave anything in `dist/`). Report to `AI/reports/FIX-Q-report.md`; update the change log, known issues and hands-on checklist.
