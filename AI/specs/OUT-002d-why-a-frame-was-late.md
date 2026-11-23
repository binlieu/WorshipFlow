# OUT-002d: for each dropped frame, say whether the app or the system was late

Feature IDs: OUT-002, KI-007. Model: Sonnet. One agent in the main folder; nothing else is in flight. No migration. Reporting only: no change to what is rendered, when it is scheduled, or how it is presented.

## Evidence so far

After OUT-002c a 10-minute soak on a 60 Hz display, never covered (`AI/reports/soak-screen2-600s-20261123-0818.log`, not in git), dropped 4 single refreshes of 35,984 at 343.1, 544.8, 567.8 and 580.6 s; the run before the fix had one such drop at 531.7 s. They are not first shows of a slide. The report (OUT-002b) gives only time, interval and visibility, so nobody can tell whether the app's own frame took too long, the app started its frame late, or the system presented a frame late that the app delivered on time. The Mac was in use over Remote Control during both runs.

## What to do

1. Read how a frame is produced and presented for a display output (`OutputRenderer.tick` and `record`, `MetalOutput`, the display link, `ScenePreparationGate`, the media frame fetch) and how OUT-002b logs events (`FrameEventLog`, `AI/reports/OUT-002b-report.md`).
2. For every tick keep, in a small fixed ring (for example the last 8 ticks, preallocated, written with plain stores on the render thread, no allocation, no extra lock beyond the one `record` already takes or a lock-free single-writer ring read only at the end): the tick's start time, the display link's target presentation time if the link provides one, time spent getting the drawable, time spent building the scene (provider, gate, media frame fetch), time spent encoding and committing, whether the gate was holding a scene, whether the scene changed on this tick, and whether a new video frame was available. When a notable frame is recorded (dropped, late or over 2x period), copy the ring's entries for the frames around it into the event (bounded: the event cap stays 2,000 and each event carries at most the ring).
3. The soak also records each slide advance time and each video loop time (bounded list), so the report can say for each event: seconds since the nearest advance and since the nearest loop point.
4. The report gains, per event, one line that a person can read: the tick timings around the drop, and a classification by stated rule: **app slow** (a tick's own work exceeded the frame period: say which part), **app late** (the tick started late: the link's callback arrived late or the render thread was busy), **presented late** (every tick was on time and short, the presentation time still skipped a refresh: the system or display), **unknown**. Give the rule in the report text. Also a summary count per class, and the distribution of tick work time over the run from a fixed histogram (bucket counts, no per-frame storage) with the maximum.
5. Tests first for the pure parts (ring, classification rule with injected timings, histogram, report text, bounds); no wall-clock assertions. New tests in `OUT002d_*.swift`. Do not edit existing tests.
6. Do not run a soak on a real display: the coordinator runs it. Show by reading the code that the per-tick cost is a handful of stores and a few clock reads, and state how many clock reads per tick you added.

## Rules

- If a timing cannot be had without changing presentation behaviour (for example the drawable wait), measure around the existing call only; do not reorder or restructure the tick.
- SDI, the scheduler and Fill/Key untouched. Swift 6 strict concurrency clean in Debug and Release.
- Do not edit `docs/` (change log and known-issues text go in the report), `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/OUT-002d-report.md`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library, never touch `/Applications/WorshipFlow.app`; stop only process ids you started; never `pkill` by name; no display or system settings.
- The repository is public: no personal strings.
- If a test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271). Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0 (timing-flaky suites `MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`: re-run once, report both).
