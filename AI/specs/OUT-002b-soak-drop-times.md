# OUT-002b: the soak report says when each dropped and late frame happened

Feature ID: OUT-002 (soak, KI-007). Model: Sonnet. One agent in the main folder; nothing else is in flight. No migration, no change to the render or output path's behaviour.

A 60-minute soak on 2026-11-23 at 100 Hz (`AI/reports/soak-screen1-3600s-20261123-0524.log`) presented 358,901 frames with 75 dropped, 10 late and a longest interval of 590 ms; the window was covered in 39 of 14,115 visibility samples. The report has only totals, so nobody can tell whether the drops fall inside the covered seconds (macOS stops presenting to a hidden window: not a fault) or during normal running (a fault in the output path).

## What to do

1. Read how the soak counts presented, dropped and late frames and samples visibility (`App/Sources/SoakConfig.swift` and what it calls).
2. Record, with bounded memory (a fixed cap, for example the first 2,000 events, plus a count of the rest), each dropped frame, late frame and each interval over twice the frame period: seconds since the start, the interval in ms, and the window's visibility at that moment (use the occlusion state change notifications, or the nearest visibility sample, and say which). Record each covered and uncovered transition with its time.
3. The report gains: totals split into "while visible" and "while covered or within 1 s after becoming visible again"; the list of events (time, kind, interval, visibility); the covered spans (start, length); and the longest interval while visible. The status line says "completed" only as today; add a plain line "drops while visible: N" that a person can read as the result.
4. Nothing on the per-frame path may allocate, lock for long or log: append to a preallocated buffer; write the report at the end as today. Show by reading the code that the per-frame cost is a few assignments.
5. Tests first for the pure part (the classification of an event as visible or covered given the transition times, the cap, the split totals, the report text) with injected times; no wall-clock assertions. New tests in `OUT002b_*.swift`. Do not edit existing tests.
6. Do not run a soak on a real display (it covers the owner's screen): the coordinator runs it. You may run the soak code path only if it has an offscreen or test mode already; otherwise unit tests only.

## Rules

- Do not change what is rendered, the scheduler, the SDI adapter or the display output's presentation logic: this is reporting only. If the existing counters cannot give a per-event time without touching the output path, stop and report exactly what hook is missing.
- Do not edit `docs/` (put change log and known-issues text in the report), `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/OUT-002b-report.md`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library, never touch `/Applications/WorshipFlow.app`; stop only process ids you started; never `pkill` by name; no display or system settings.
- The repository is public: no personal strings.
- If a test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271). Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0 (timing-flaky suites `MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`: re-run once, report both).
