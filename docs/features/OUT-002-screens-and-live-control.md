# OUT-002 — Screens, roles and live control

Satisfies: SCRN-01, SCRN-02, SCRN-03, SCRN-04, NFR-03, NFR-04, NFR-05, NFR-08, NFR-10; groundwork for LIVE-07, PRES-07, SCRN-09. Phase 1. Closes KI-008.

## Behaviour

1. **Show state.** One `ShowState` holds a preview deck and a live deck. Commands: load, trigger, next, previous, clear, stop, quick edit, restore.
   - Loading or editing a deck changes preview only.
   - Trigger takes the preview deck live at a slide. Next and Previous follow the live deck and stop at its ends.
   - Clear hides the slide on every screen but keeps the place; the audience background stays.
   - Stop drops the live deck; screens go empty.
   - Restore after a relaunch fills preview only. Nothing goes live by itself.
2. **Composition per role.** The same live state yields three scenes: audience (both languages over the background), stage (current and next, opaque, optional clock), broadcast (transparent lower third).
3. **Routing.** Each screen profile names a role and a destination: a display or a window. A missing display faults that screen only. Two screens cannot share a display. A full-screen output never covers the operator's display. A faulted screen is never moved to another display on its own.
4. **Output coordinator.** Starts and stops outputs from the routing plan, re-plans when displays change, and reports each screen's status and fault to the operator.
5. **Operator readout.** Per screen: destination, running or fault message, refresh rate, presented, dropped and late counts. An occluded output says "hidden", not zero.
6. **Sleep.** Display and system sleep are prevented while any output is running, and allowed again when all stop.
7. **Benchmark.** An offscreen test renders four 1080p scenes per frame for 600 frames and records the mean and worst frame time.

## Acceptance

| Check | Level |
|---|---|
| `ShowStateTests`, `SceneComposerTests`, `OutputRouterTests` pass | Unit Tested |
| Coordinator re-plans on a simulated display change: the faulted screen stops, the others keep running | Unit Tested with fake outputs |
| Offscreen four-output benchmark recorded | Measured on this Mac |
| Audience on the second display and stage in a window show different compositions of one slide; unplugging the display leaves the app running | Seen running. Needs a free display. |
