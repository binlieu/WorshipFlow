# OUT-002e report: the display output no longer waits a whole refresh for its drawable

Feature IDs: OUT-002, KI-007. Model: Sonnet. Verification: Implemented, Unit Tested (the new report statistics), Simulated: none. Measured on one real 60 Hz display (A/B soaks of 90 s, not the 10-minute soak). Not Live-Service Verified.

## 1. Mechanism

Sure (read from the code, the SDK headers `CAMetalLayer.h`, `CAMetalDisplayLink.h`, `MTLDrawable.h`, and the soak numbers):

- Before: `MetalOutput` used an `NSView.displayLink` (`CADisplayLink`) added to a private run-loop thread; its callback ran `OutputRenderer.tick`. The tick called `layer.nextDrawable()` first. `CAMetalLayer.h` says it "always blocks until a drawable is available". Layer: `maximumDrawableCount = 3`, `displaySyncEnabled = true`, `framebufferOnly`, `bgra8Unorm`, `presentsWithTransaction` default (false), `allowsNextDrawableTimeout` default (true, 1 s). The frame is presented with `cb.present(drawable)` in the command buffer (no `atTime`). The only things holding drawables are the swap queue and the presented handler; the two-frames-on-GPU guard (`inFlight`, 2) does not hold drawables.
- In the "blocked" mode the tick waits one refresh in `nextDrawable()` (d 16.3 to 16.7 ms), ends at the link's target time (margin about -0.6 ms) and commits then. So the frame is presented one refresh later than the target. Measured here: the time from the start of a tick to its frame on screen is 49 ms mean (3 refreshes), against 33 ms with the Metal display link, and about 17 ms in the fast mode (inferred from its margin of +15.9 ms: the frame is presented at the target).
- Why a full pool means a wait: 3 drawables = one on screen, two committed and waiting for a vsync; the tick has none to take until the on-screen one is replaced.

Inferred (consistent with every log, not proven):

- The number of frames queued ahead is conserved: each tick adds one frame and each vsync takes one, so once the output runs one frame deeper (two ticks back to back after a late callback, such as the first-scene encode of 37 to 50 ms at start-up) nothing drains it, and it stays deeper. Only a long stall (the 109 ms `nextDrawable` in the 600 s soak, which drops 5 refreshes) empties the queue and returns to the fast mode. That explains the two modes, the start in one of them, and the long stay in the blocked one.
- In the blocked mode the app has no margin: it finishes exactly on the target, so any hiccup is a missed refresh.

## 2. Options and their latency (tick start to frame on screen, measured unless marked)

| Option | Latency | Result |
|---|---|---|
| Today, blocked mode (swap queue 3 deep) | 49 ms | stays blocked |
| Today, fast mode | about 17 ms (inferred) | not stable; unreachable once the queue is deeper |
| `maximumDrawableCount = 2` | not measured | **rejected**: 2,373 dropped frames in 90 s (with the 2-frames-on-GPU guard the output paces at half rate) |
| Drop a tick when 2 frames are pending (own governor, counting presented handlers) | 33 ms | **rejected**: the presented handler fires too late for the count to be reliable; it skipped every other tick (599 dropped in 30 s) |
| `CAMetalDisplayLink` (macOS 14+; the package targets macOS 15, no fallback needed) | 33 ms | **chosen**: the system hands the drawable to the callback; no wait; the tick ends 32.5 ms before the presentation target |
| Get the drawable later in the tick | n/a | not tried: the wait is for a free drawable, not for time spent before it |
| `present(atTime:)` / `afterMinimumDuration` | n/a | not tried: they delay a presentation; they do not remove the wait for a drawable |
| `preferredFrameLatency` 0.5, 1, 2, 3 | 33 ms for every value | no effect seen on this Mac; the value 1 (lowest) is kept explicit |

Latency statement: against today's typical state (blocked, 49 ms) the change **removes** 16 ms. Against the fast mode today (about 17 ms, inferred), it is one refresh **more**. This is the price of a documented, system-paced path; it is not hidden: the soak report now prints the measured latency.

## 3. A/B runs (90 s each, screen index 2, 60 Hz "MNN", `caffeinate -d -i`, Release build with the same code and an environment switch, alternating)

"Share" = ticks with work (drawable + build + encode) of 12 ms or more. "Margin" = link target minus tick end (for the Metal link: the target presentation time). Latency = tick start to presented time.

| Run | Variant | Share of ticks at 12 ms or more | Margin mean (min) ms | Dropped | Longest interval ms | Latency mean ms |
|---|---|---|---|---|---|---|
| A1 | display link, 3 drawables | 5399 of 5405 (99.9 %) | -0.75 (-33.9) | 2 | 50.0 | not yet recorded |
| R1 | display link, 3 drawables | 5351 of 5407 (99.0 %) | -0.63 (-23.5) | 2 | 33.3 | 49.6 |
| R3 | display link, 3 drawables | 5395 of 5409 (99.7 %) | -0.73 (-25.8) | 1 | 33.3 | 49.2 |
| R5 | display link, 3 drawables | 5383 of 5398 (99.7 %) | -0.71 (-26.7) | 1 | 33.3 | 49.2 |
| B1 | display link, 2 drawables | 3035 of 3038 | -13.13 (-27.6) | 2,373 | 33.3 | not recorded |
| C1 | Metal link, latency 2 | 1 of 5396 | 32.56 (-18.0) | 3 | 33.3 | not recorded |
| D1 | Metal link, latency 1 | 1 of 5408 | 32.57 (-5.4) | 1 | 33.3 | not recorded |
| X1 | Metal link, latency 0.5 | 1 of 5407 | 32.55 (-12.1) | 2 | 33.3 | not recorded |
| X2 | Metal link, latency 3 | 1 of 5408 | 32.57 (-5.8) | 3 | 33.3 | not recorded |
| R2 | Metal link, latency 1 | 1 of 5396 | 32.56 (-9.2) | 3 | 50.0 | 32.9 |
| R4 | Metal link, latency 1 | 1 of 5406 | 32.55 (-5.0) | 3 | 66.7 | 32.9 |
| R6 | Metal link, latency 1 | 1 of 5404 | 32.55 (-17.5) | 3 | 66.7 | 32.9 |
| F1 | final code (Metal link, latency 1, no switch) | 1 of 5399 | 32.56 (-15.2) | 4 | 50.0 | 32.9 |

Also run for latency only (30 s): display link 3 drawables (1,794 of 1,807 at 12 ms or more, latency 49.2 ms, 1 dropped), Metal link 1 and 2 (1 of 1,807 and 1 of 1,796, latency 32.9 ms, 4 dropped each), governor (599 dropped). Rows A1, B1, C1, D1, X1, X2 ran before the latency line existed.

Drops: in every Metal-link run all drops happen in the first 0.36 s (the first scene is drawn cold: one tick of 37 to 50 ms encode; the known start-up cost left by OUT-002c). In the remaining 90 s of the four runs that listed their events there is no drop. Display link runs: one of them (R1) also had a drop at 38.8 s (app slow, 19.1 ms in `nextDrawable`). Start-up drops are 3 to 4 for the Metal link against 1 for the display link, because the callback is two refreshes ahead of the presentation, so a 40 ms first tick is felt as one more missed refresh. Not changed here (see section 6).

All 6 display-link runs started in or entered the blocked mode within the first second. None of the 90 s runs showed the fast mode for a long time, so "the output can start in either mode" is seen only in the 600 s soak, not reproduced here.

## 4. What changed and why

- `OutputEngine/MetalOutput.swift`: the `CADisplayLink` and `DisplayLinkTarget` are replaced by `CAMetalDisplayLink` and `MetalLinkTarget` (the delegate passes the callback's target time, the presentation target and the drawable to `OutputRenderer.tick`). Frame rate range is set to the display's refresh rate and updated on a screen-parameter change; `preferredFrameLatency` is set to 1. Applies to every display output (audience and stage) through `MetalOutput`. SDI untouched.
- `OutputEngine/OutputRenderer.swift`: `tick(linkTimestamp:linkTarget:drawable:)`; with a handed drawable the tick does not call `nextDrawable()`; without one (tests, offscreen) it does as before. The size passed to the preparation gate is the drawable's own size. Preview/Live/Blackout/Clear, the OUT-002c gate, the frame statistics and event log and the two-frames-on-GPU guard are unchanged (a tick skipped for the GPU being behind simply releases the unpresented drawable).
- Reporting: `TickSample.margin`, run-wide margin statistics, "ticks with work of 12 ms or more", and `PresentLatencyStats` (tick start to presented time) in `TickTimeline.swift` and `FrameEventLog.swift`; three new report lines. These made the A/B comparable.
- The temporary environment switches used for the A/B (`WF_AB_*`) are removed; the final binary contains none (`strings` check).

## 5. Tests written first

`Packages/WorshipFlowKit/Tests/OutputEngineTests/OUT002e_TickMarginTests.swift` (10 tests, injected values, no wall clock): margin is target minus tick end and nil without a target; the histogram keeps count, mean, minimum and the late count; recording without a margin behaves as before; the report states the share at 12 ms or more, the margin and the latency (and says so when there is no target or no presented frame). Red phase for the margin tests: a compile failure (`margin:` did not exist). The latency tests were written in the same step as their statistics type without a separate red run. No existing test edited. The presentation itself (Metal display link) has no unit test: it needs a display; it is verified only by the soaks above.

## 6. Check

`./scripts/check.sh`: **exit 0**; package tests **3,550 passed** in 561 suites (3,540 before, plus 10 new), Debug and Release app builds succeeded (Swift 6 strict concurrency clean), "the Release app carries none of the measuring hooks" OK. No flaky suite failed, so no re-run. The scratch build folder and the scratch app copy were deleted; the check's own Debug app stays by design.

## 7. Files

- Changed: `Packages/WorshipFlowKit/Sources/OutputEngine/MetalOutput.swift`, `OutputRenderer.swift`, `TickTimeline.swift`, `FrameEventLog.swift`.
- New: `Packages/WorshipFlowKit/Tests/OutputEngineTests/OUT002e_TickMarginTests.swift`, this report.

## 8. Text for the coordinator (docs not edited)

- Change log: "fix(OUT-002e): display outputs are driven by CAMetalDisplayLink, which hands the drawable to the render callback, instead of CADisplayLink plus nextDrawable(); the output no longer sits with every tick waiting one refresh for a drawable (99.9 % of ticks in 90 s runs), the tick ends 32 ms before its presentation target instead of at it, and the latency from tick start to screen is 33 ms instead of 49 ms. The soak report adds the margin to the target, the share of ticks with 12 ms or more of work, and the tick-to-screen latency."
- KI-007: the 600 s soak should now show almost no tick over 12 ms and no sporadic drops attributed to the drawable wait; a 10-minute soak on the 60 Hz display must confirm it. The start-up drop (first scene drawn cold) is not fixed and now costs 2 to 3 refreshes instead of 1.

## 9. Not done

- The first scene of a run is still drawn cold (OUT-002c "Not done"); a later task could prepare it before the first callback.
- The two sporadic fast-mode events of the 600 s soak (a tick 68.9 ms late at 212.5 s, a refresh skipped at 442.9 s) were not reproduced in 90 s runs and are not attributed to the app.
- No fallback for macOS earlier than 14 (the deployment target is 15).

## 10. Not verified

- No 10-minute soak, no run on the 100 Hz displays (only the 60 Hz display "MNN" was used), no Release-packaged app run, no hardware/SDI path (untouched). Hardware Verified and Live-Service Verified: Not Verified.
- The conserved-queue explanation is inferred; it was not proven by instrumenting the swap queue. The fast-mode latency of about 17 ms is inferred from the margin, not measured (it did not last long enough in any 90 s run).
- That `preferredFrameLatency` has no effect is seen on this Mac, in a 60 Hz run, with the four values tried; the header documents no semantics.
- That `targetTimestamp` (used as the "link timestamp") and `targetPresentationTimestamp` mean what the names say: the margin of 32.5 ms and the measured latency of 33 ms agree with each other, which supports it, but is not independent proof.
- Behaviour across display sleep/wake, display unplug, a window moved to another display and a refresh-rate change with the new link: not exercised (code paths follow the old ones; the rate range update is untested).
- Whether the visible output has any judder from the extra start-up drops: not observed by eye.
