# OUT-002b report: the soak report says when each dropped and late frame happened

Feature ID: OUT-002 (soak, KI-007). Model: Sonnet. Verification: Implemented, Unit Tested. Not run in a real soak.

## What changed

- `Packages/WorshipFlowKit/Sources/OutputEngine/FrameEventLog.swift` (new): `PresentationOutcome`, `FrameEvent`, `FrameEventLog` (fixed cap, default 2,000 events, the rest only counted), `VisibilityTimeline` (covered spans, 1 s grace) and `SoakDropReport` (split totals and the report text). Pure Foundation, injected times only.
- `FrameStatistics.recordPresentation(at:)` now returns the gap, missed intervals, late and over-2x flags (`@discardableResult`; counters unchanged).
- `OutputRenderer`: keeps one `FrameEventLog` beside `stats`, appended in the same locked section that already updates `stats`.
- `MetalOutput`, `OutputTarget` (default: empty log), `OutputCoordinator.frameEvents(for:)`: read the log out at the end of a soak.
- `App/Sources/AppModel.swift` (`runSoak`): the existing 250 ms visibility sample also feeds a `VisibilityTimeline` (media clock); the report gains the new section before `status:`. `import QuartzCore` added.
- Tests: `Packages/WorshipFlowKit/Tests/OutputEngineTests/OUT002b_DropTimesTests.swift` (12 tests). No existing test edited.

## Visibility basis (stated in the report too)

The nearest 250 ms visibility sample, not occlusion notifications (those would need a hook inside the output window). A covered span starts at the last sample that saw the window visible and ends at the first visible sample after it; an event counts as covered inside a span or up to 1 s after it ends (the first frame after a cover carries the whole covered gap). Resolution is therefore 0.25 s.

## Per-frame cost

Per presented frame, under the lock the renderer already took: `recordPresentation` builds a small value (gap, missed, two flags: a few assignments and compares), then `events.record` returns at once unless the frame is notable (dropped, late or over 2x period). A notable frame does one `append` into storage reserved at init (`reserveCapacity(2000)`), so no allocation; past the cap it is one integer increment. No new lock, no logging, no file or string work. The text is built once at the end of the run. Visibility is read only from the existing 250 ms main-actor sample.

Limit: one stored event per notable frame; with more than 2,000 notable frames the rest are counted ("further events not listed or classified") and "drops while visible" says "at least". Frames below 1.5x period (not late, not dropped) are not recorded, so "longest interval while visible" is among recorded events.

## Sample of the new report section (from `reportTextListsEventsSpansAndTheResultLine`)

```
events recorded: 2 (cap 10), further events not listed or classified: 0
visibility basis: 1 covered span(s) from 250 ms visibility samples; a span starts at the last sample that saw the window visible, and an event counts as covered up to 1 s after the window is visible again
while visible: dropped 2, late 1, intervals over 2x period 1
while covered or within 1 s after becoming visible again: dropped 58, late 1, intervals over 2x period 1
longest interval while visible: 30.00 ms
covered spans (start s, length s):
  10.000, 1.000
events (time s, kind, interval ms, window):
  5.000, dropped 2 + late + over 2x period, 30.00, visible
  11.000, dropped 58 + late + over 2x period, 590.00, covered
drops while visible: 2
status: completed
```

## Checks actually run

- `swift test --filter "OUT002b|FrameStatisticsTests"`: 17 tests passed (after fixing two wrong expectations in my own new tests: 1.6 periods rounds to one missed interval; a span opens at the last visible sample).
- `./scripts/check.sh`: exit 0; package tests 3,488 passed, app Debug and Release builds succeeded, "Release app carries none of the measuring hooks" OK. No flaky suite failed, so no re-run was needed.
- Removed the built `WorshipFlow.app` from the check derived-data folders.

## Change-log and known-issues text for the coordinator (docs not edited)

- Change log: "feat(OUT-002b): the soak report lists each dropped, late and over-2x-period frame with its time and whether the output window was covered, splits the totals into visible and covered, lists covered spans, and ends with 'drops while visible: N'. Reporting only."
- KI-007: the next soak answers whether the 75 drops fall inside the covered spans; read the line 'drops while visible'.

## Not verified

- No soak was run (not on a real display, no offscreen mode exists), so the section has never been produced by the live output path.
- That `presentedTime` shares the `CACurrentMediaTime` clock base was taken from the API contract, not measured; if it does not, every event would classify as visible. First real soak should show event times between 0 and the run length.
- Covered/visible classification has 0.25 s resolution and a 1 s grace.
- No hardware or SDI path touched; SDI outputs return an empty log.
- Render and scheduler logic, the SDI adapter and presentation logic are unchanged. The one touch to the output path is the recording hook in `OutputRenderer.record` (needed because only `FrameStatistics` knows the per-frame interval).
