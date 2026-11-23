# OUT-002d report: for each dropped frame, say whether the app or the system was late

Feature IDs: OUT-002, KI-007. Model: Sonnet. Verification: Implemented, Unit Tested. Not run in a soak (the coordinator runs that). Reporting only: what is rendered, when it is scheduled and how it is presented are unchanged.

## 1. What the soak report now contains

New, before the event list (after "longest interval while visible"): the classification rule, one count per class, and a fixed histogram of tick work. Each event line of OUT-002b is unchanged and gets one more line below it. Sample (from a throwaway test with injected timings; the test was deleted):

```
classification rule (OUT-002d): each event is judged from the ticks that started from 3 frame periods before the previous presentation up to the event, checked in this order:
  app slow: a tick's own work (getting the drawable + building the scene + encoding and committing) exceeded the frame period; the largest part is named
  app late: no tick was slow, but a tick started more than 1.5 periods after the previous tick started, or ran more than 1.5 periods after the display link's own timestamp (the callback arrived late or the render thread was busy)
  unknown: a tick in that window was skipped (two frames were still on the GPU), or no tick was recorded near the event, or the event is past the log cap
  presented late: every tick near the event started on time with work within the period, yet a refresh was skipped (the system or the display presented late)
event detail lines: class and reason | nearest slide advance and video loop point in s (positive: the event is after it; ...) | ticks, oldest first: start ms relative to the event, cb = ..., m = ..., d/b/e = drawable/build/encode ms, flags H gate holding, C scene changed, V new video frame, S skipped
classes: app slow 1, app late 0, presented late 0, unknown 0
tick work over the run: 2 ticks that produced a frame, maximum 27.80 ms, over the frame period: 1
tick work buckets (drawable + build + encode): < 0.5 ms: 0, 0.5 to 1 ms: 0, 1 to 2 ms: 1, 2 to 4 ms: 0, 4 to 8 ms: 0, 8 to 12 ms: 0, 12 to 16 ms: 0, 16 to 20 ms: 0, 20 to 33 ms: 1, 33 to 66 ms: 0, >= 66 ms: 0
ticks skipped because the GPU was behind: 1
...
events (time s, kind, interval ms, window):
  5.000, dropped 1 + late, 33.30, visible
    app slow (building the scene took 27.0 ms of 27.8 ms work in the tick at -70.0 ms, frame period 16.67 ms) | advance -0.020 s, loop -75.000 s | ticks: -100.0 cb+1.0 m+29.0 d0.1 b0.5 e0.4 | -70.0 cb+0.5 m-11.1 d0.2 b27.0 e0.6 C | -33.3 cb+0.5 m+15.7 d0.1 b0.4 e0.4 H
drops while visible: 1
```

(The legend lines are shortened here; the report carries them in full. The last line is still `drops while visible: N`.) With no video, `loop n/a`; with no advances, `advance n/a`.

## 2. Classification rule

Per event, on the ticks that started in `[event - gap - 3 periods, event]` (event = presentation time of the late frame, gap = its interval since the previous presentation, period = the output's target frame period), checked in this order, first match wins:

1. **app slow**: a tick's own work (drawable + build + encode) exceeded the period. The largest of the three parts is named (getting the drawable, building the scene, encoding and committing).
2. **app late**: no tick was slow, but a tick started more than 1.5 periods after the previous tick started (looked up in the whole ring), or ran more than 1.5 periods after the display link's own timestamp: the callback arrived late or the render thread was busy.
3. **unknown**: a tick in the window was skipped (two frames still on the GPU), or no tick was recorded in the window, or the event has no ring (past the 2,000 cap, which is not stored at all).
4. **presented late**: otherwise. Every tick was on time and short, the presentation time still skipped a refresh: the system or the display.

Order reason: a slow tick makes the next tick start late, so slow is checked before late. The 1.5 factor on the link timestamp is deliberate (see "Not verified").

Per-tick data recorded: start time, the link's timestamp and target presentation time (0 when none), time to get the drawable (and command buffer), time to build the scene (scene provider, `ScenePreparationGate`, media frame resolve, video texture fetch), time to encode and commit, and flags: gate holding, scene changed on this tick, new video frame, tick skipped. The per-event line also shows `cb` (ms after the link's own timestamp) and `m` (ms between the tick's end and the link's target time; negative means the tick ended after it). `m` is shown only; no rule uses it.

## 3. Per-tick cost added

- **Clock reads: 4** (`CACurrentMediaTime()`): tick start, after the drawable and command buffer, after the scene build (including video fetch, before `encode`), after commit. A tick skipped because the GPU is behind reads 1.
- **Stores: one `TickSample` into the preallocated ring** (7 fields, one index increment, one count compare), plus the histogram: a compare chain over 10 edges, one bucket increment, one `ticks` increment, a max compare and an over-period compare. About 25 stores/compares in all; no allocation (array reserved at init, mutated in place), no string work, no logging.
- Also three plain stores of the gate flags (`isHolding`, `adoptedOnLastCall`, the video `!==` pointer compare), and two reads of the link's `timestamp` and `targetTimestamp` in the display-link callback.
- **Locks: none added on a tick that submitted a frame.** The ring and histogram are written in the lock section the tick already took after commit (`submittedFrames += 1`). A tick that made no frame (GPU behind, no drawable, encode error) now takes that lock once.
- A notable frame (dropped, late, over 2x) copies the ring once (an 8-element array) under the lock `record` already took; past the 2,000-event cap the copy is not made (autoclosure not evaluated). Event cap unchanged at 2,000; each event carries at most 8 ticks (about 1 MB at the cap).
- The tick's order, the drawable wait and the presentation are not changed. Nothing is reordered; the gate and the compositor are called as before.

## 4. Slide advances and video loop points

- `runSoak` stores the media-clock time of every slide advance it sends (`EventMarks`, bounded to 2,000).
- `LoopingVideoSource.itemChangeTimes` (new, bounded to 2,000): the media-clock time each time the player's current item was replaced after the first. `AVPlayerLooper` replaces the item at each loop boundary, so this is the loop point (taken from the KVO callback, not from the 250 ms sample). Setup at start can add an early entry.
- The report prints for each event the signed seconds to the nearest advance and nearest loop point (positive: the event is after it). Nearest in either direction, since a command is sent slightly before it reaches the screen.

## 5. Tests (written first)

`Packages/WorshipFlowKit/Tests/OutputEngineTests/OUT002d_TickRecordTests.swift` (33 tests in 7 suites, no wall clock, injected timings): ring order and wrap and bound; flags; histogram buckets, maximum, over-period count, fixed size, skipped; the classification rule (each part named, work within period is not slow, late by start interval, late by link timestamp, slow beats late, presented late, skipped is unknown, no ticks and period 0 are unknown, window excludes old and later ticks, the long-gap window); nearest mark and bounded marks; event log carries the ring and period, no snapshot for a non-notable frame or past the cap, cap stays 2,000 and at most 8 ticks per event; report text (rule, class counts, event line, histogram, `n/a`, existing last line); the gate's `isHolding` and `adoptedOnLastCall`; and an offscreen renderer tick that leaves one sample with the link times, `sceneChanged` and non-negative phases. The red phase was a compile failure (the types did not exist yet); no existing test was edited. Two of my own first expectations were wrong in the test text (a tick exactly on the window edge, and a slow-tick case whose ring had a one-second hole, which correctly classifies as late); fixed in the new test only.

## 6. Files

- New: `Packages/WorshipFlowKit/Sources/OutputEngine/TickTimeline.swift` (`TickSample`, `TickRing`, `TickWorkHistogram`, `EventMarks`, `LatenessClass`, `FrameLateness`), `Packages/WorshipFlowKit/Tests/OutputEngineTests/OUT002d_TickRecordTests.swift`, this report.
- Changed: `OutputEngine/OutputRenderer.swift` (ring, four clock reads, link times, record), `OutputEngine/FrameEventLog.swift` (event ticks and period, histogram, report lines), `OutputEngine/ScenePreparationGate.swift` (two read-only flags), `OutputEngine/MetalOutput.swift` (the display link handler passes `timestamp` and `targetTimestamp`), `MediaEngine/LoopingVideoSource.swift` (`itemChangeTimes`), `App/Sources/AppModel.swift` (`runSoak`: advance marks, loop times into the report).
- SDI, the scheduler and Fill/Key untouched (SDI outputs still return an empty log). `docs/` not edited.

## 7. Check

`./scripts/check.sh`: **exit 0**; package tests **3,540 passed** in 559 suites (3,507 before plus 33 new), app Debug and Release builds succeeded (Swift 6 strict concurrency clean in both), "the Release app carries none of the measuring hooks" OK. No flaky suite failed, so no re-run. Built `WorshipFlow.app` removed from the check derived-data folders.

## 8. Text for the coordinator (docs not edited)

- Change log: "feat(OUT-002d): the soak report classifies each dropped or late frame as app slow, app late, presented late or unknown from a ring of the last 8 render ticks (start, link timestamp and target, drawable, build and encode times, gate hold, scene change, new video frame, skipped), lists the ticks around each event and its distance to the nearest slide advance and video loop point, and adds a histogram of tick work. Reporting only."
- KI-007: the next 10-minute soak shows, for each of the sporadic single drops, which class it falls in. Read `classes:` first, then the lines under each event.

## 9. Not measured

- Nothing in a soak: no live tick timings exist yet, so the per-tick cost is argued from the code (4 clock reads, about 25 stores) and not measured as time.
- The classes of the 4 known sporadic drops (343.1, 544.8, 567.8, 580.6 s) are unknown until the coordinator's soak runs.

## 10. Not verified

- That `CADisplayLink.timestamp` and `targetTimestamp` have the base and meaning assumed (same clock as `CACurrentMediaTime`, `timestamp` near the callback time, `targetTimestamp` the intended presentation). The rule only uses `timestamp` with a 1.5-period margin, and `targetTimestamp` is shown, not ruled on. The first real report should be read for `cb` values near 0 to a period; if they are constant near one period the semantics differ.
- That a tick's phases line up with the presented frame the event describes: the ring is copied when the presented handler runs, so the frame's own tick is among the last 8 only while presentation follows commit within about 8 ticks.
- That `itemChangeTimes` marks the loop point on a real file (not exercised: no test plays video); the first loop of a run may include a start-up entry.
- "presented late" is a conclusion by elimination, not a measurement of the system; it does not say whether the system or the display caused it.
- The drawable time includes the command buffer creation (one guard statement; the two calls cannot be split without restructuring the tick).
- Hardware Verified, Live-Service Verified, SDI path, Release build timing: Not Verified. No soak ran.
