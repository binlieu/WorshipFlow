# Brief: HW-002 and OUT-005 — SDI outputs and mirrored outputs in the app

Read first: `CLAUDE.md` (hardware and video-output rules, verification levels), `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md`, `AI/reports/HW-001-report.md`, `AI/reports/OUT-002-report.md`, `AI/reports/FIX-A-report.md`, `Sources/SDIEngine`, `Sources/Domain/OutputRouting.swift`, `Sources/OutputEngine`, `Sources/OperatorCore/SettingsModel.swift`, `App/Sources/ControlPanels.swift`, `AppModel.swift`.

Catalogue: SCRN-11 (SDI output), SCRN-10 (alpha-key output), SCRN-05 (mirrored displays). **Highest level reachable: Simulated.** There is no card and no vendor SDK. Everything SDI runs against `SimulatedSDIDevice`, and the interface must say "Simulated" wherever a simulated device is shown.

## Rules for this slice

Test first for every decision: write the failing test, record its output, then implement. `OutputEngine` now depends on `SDIEngine` (already done in `Package.swift`).

## What to build

**`Domain`** (source-compatible; stored profiles must keep decoding):
- `OutputDestination.sdi(deviceID: String, connector: Int, keying: Bool, fillAlphaMode: …)` (use a Domain-level alpha-mode type or a Bool so `Domain` does not import `SDIEngine`).
- `ScreenProfile.mirrors: [OutputDestination]` (default empty, decoding tolerant of its absence): extra destinations showing the same scene as the primary destination.
- `ScreenProfile.videoMode` for SDI destinations: a Domain-level description of the mode (default 1080p59.94), validated against what the device supports.
- Routing: the existing display and window rules apply to every destination, primary and mirror, each routed and faulted on its own (a missing mirror display never stops the primary). New faults for SDI: device missing, and the connector faults from `SDIConnectorPlanner` carried through with their operator messages. Because `Domain` cannot import `SDIEngine`, put the combined planner in `OutputEngine` (for example `OutputPlanner`) and keep `OutputRouter` as it is for displays; existing coordinator tests for `OutputRouter` must pass unchanged.

**`OutputEngine`**:
- `SDIOutput: OutputTarget`: renders each published scene with the shared compositor into an offscreen texture at the mode's size, reads it back as BGRA (off the main thread; reuse buffers; no per-frame allocation in steady state), and feeds an `SDIOutputSession` as its frame provider. Statistics and health come from the session and are mapped into the existing readout (presented, dropped, late, plus health and "frames repeated"). Keyed outputs pass the alpha through; the scene for a keyed output must have a transparent background or the readout warns "nothing will key: background is opaque". Unplug stops that output only and reports it; replug follows the same same-device auto-resume rule as displays (KI-012).
- The render clock for an SDI output is the device's completion callbacks, not a display link (ADR-0005 decision 5). With the simulator, provide a real-time driver that advances the simulated device at the mode's frame rate on its own thread, so the app can run a simulated output live, and keep the manual clock for tests.
- `OutputCoordinator` opens and closes SDI outputs and mirrors from the combined plan, with an injected SDI device provider (the app passes one that returns the simulated Duo 2 when a "Show simulated SDI device" developer setting is on, and nothing otherwise — there is no real provider yet).
- Tests against the simulator: a 600-frame run through `SDIOutput` with zero late and zero dropped; a keyed output puts fill on connector 1 and key on connector 2 with the expected pixels for a lower-third scene; two screens asking for the same connector fault the later one; unplug and replug; a mirror showing the same pixels as its primary.
- An offscreen benchmark: four simulated SDI outputs at 1080p59.94 driven as fast as possible for 600 frames, reporting mean and worst time per frame including readback, asserting only a generous ceiling. Put the numbers in the report: this is the first evidence on UNV-04.

**`OperatorCore` and App**:
- Screens panel: destination picker gains SDI devices and their connectors (labelled "Simulated" when simulated), a keying toggle that shows "uses connectors N and N+1", an alpha-mode choice for keyed outputs, a mode picker limited to supported modes, and an "add mirror" control listing extra destinations with their own status lines. A connector map for each SDI device shows what each connector carries (unused, output, fill, key and for which screen).
- A developer setting "Show simulated SDI device", off by default, so a real operator never sees a fake device by accident.
- Live preview for a keyed screen shows the checkerboard-over-transparency convention so the operator can see what is transparent.

## Do not modify

Coordinator-owned tests. `Package.swift`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`. Existing migrations (profiles are stored as JSON; no migration should be needed — if one is, name it `v6`).

## Seeing it run

Launch with a temporary `--library`, turn on the simulated device, set a broadcast screen to simulated SDI connector 1 with keying, go live, and save `AI/reports/HW-002-screens.png` showing the connector map and the screen's status; describe it. Keep runs under a minute, never cover a display, never switch display modes, play no sound, do not request full computer control, quit the app, leave nothing behind in the home folder.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only, bounded queues, no blocking on the main thread. Do not commit or change git state. Do not consult any advisor tool. Do not download anything. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0. Paste the test summary line.
2. The screenshot exists and you have described it.
3. `AI/reports/HW-002-report.md` records what was built, the benchmark numbers, which paths you exercised in the running app, commands run with exit status, and everything not verified — stating plainly that nothing is Hardware Verified.
