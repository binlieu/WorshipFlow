# HW-002 / OUT-005 report: SDI outputs and mirrored outputs

Verification level: **Simulated at most. Nothing here is Hardware Verified.** No card, no vendor SDK, nothing downloaded. Every SDI path ran against `SimulatedSDIDevice`, and the interface says "Simulated" wherever that device is shown.

## Built
- **Domain** (`OutputRouting.swift`): `OutputDestination.sdi(deviceID:connector:keying:fillAlphaMode:)`, `SDIAlphaMode`, `VideoModeDescription` (default 1080p59.94, same list as the engine), `ScreenProfile.mirrors` and `videoMode` (decoding tolerant of their absence; init params defaulted). `OutputRouter` ignores SDI destinations; its tests are unchanged.
- **Persistence**: migration **v6** adds `screenProfile.extra` (JSON, NULL for plain profiles, so v5 rows read unchanged). The brief assumed JSON storage, but profiles live in SQL columns, so a migration was needed.
- **OutputEngine**: `OutputPlanner` (one plan for displays, windows, SDI connectors, mirrors; per-slot faults `OutputFault`, connector faults carried through; primaries planned before mirrors); `SDIOutput` (offscreen compositor render, BGRA readback on the card's callback thread or its own queue, ring of reused buffers, stats and health from the session, "Nothing will key: background is opaque" warning, device-loss stop); `SDIEnvironment`/`SDIDeviceHandle` (injected device provider and target factory); `OutputCoordinator` rewritten around slots (primary or mirror), with `devicesChanged()`, `connectorMaps()`, `sdiDevices()`, mirror and SDI readouts, same-device auto-resume including a quick unplug/replug race; `ConnectorMapPresenter`.
- **SDIEngine** (additive): `SDIOutputSession.onStop`, `SimulatedClockDriver` (real-time, ref-counted, own thread), `FillKeySplitter` rewritten with optimised pointer loops (identical output; 330 ms to 22 ms per frame in Debug).
- **OperatorCore**: `ScreenEditing` + `SDIDeviceSummary` (connector choices, keying caption "Uses connectors N and N+1", alpha mode, mode list, mirror add/remove/set), `SettingsModel.showSimulatedSDIDevice` (off by default, stored in `appState`).
- **App**: destination pickers with SDI connectors and mirrors, keying/alpha/mode controls, per-mirror status lines, connector map per card, Developer section ("Show simulated SDI device", simulate unplug/replug), checkerboard behind the live preview of a keyed screen. The simulated card and its clock live in `AppModel`.

## Tests (all written before the code; failures were compile failures on the missing API, except the persistence tests, which I wrote first but only saw fail at compile time through an exhaustive-switch error)
New: 93 tests in `HW002_*` files across DomainTests, SettingsStoreTests, SDIEngineTests, OutputEngineTests, OperatorCoreTests. Includes: 600 frames through `SDIOutput` with 0 late/0 dropped; keyed pair pixels (fill on 1, key on 2, premultiplied and straight); two screens on one connector; unplug/replug incl. quick replug; mirror = same pixels; buffer reuse (0 reallocations in steady state); scene read never on the main thread.
Heavy loops run off the main thread: my first version hogged the main queue and made unrelated AVFoundation tests time out in the full run.

## Commands
- `./scripts/check.sh`: **exit 0**. `Test run with 842 tests in 136 suites passed` (749 + 93).
- App build is part of check.sh (Debug). Release benchmark: `swift test -c release -Xswiftc -enable-testing --filter HW002_SDIBenchmark` exit 0.

## Four-output benchmark (UNV-04, first evidence), 1080p59.94, 600 frames after 10 warm-up, readback included, M4, simulated card, driven as fast as possible
| Build | Mean per frame (4 outputs) | p99 | Worst | Per output render+readback mean / worst |
|---|---|---|---|---|
| Debug (check.sh) | 5.6 to 7.2 ms (several runs) | 8.1 to 13.6 ms | 11.3 to 23.8 ms | 1.4 to 1.8 ms / 3.0 to 11.3 ms |
| Release | 5.805 ms | 8.942 ms | 10.258 ms | 1.447 ms / 3.315 ms |
Late 0, dropped 0 in all runs. Two keyed pairs (four connectors): Release mean 4.347 ms, worst 8.743 ms; Debug mean about 50 ms because the simulator splits fill/key per frame. Asserted ceilings: mean < 16 ms (four outputs), < 200 ms (keyed). Measures compositing, GPU wait and memory copy only; no SDI hardware path, no real-time pacing (manual clock, as fast as possible).

## Running app (Debug build, temporary `--library`, `--silent-audio`, quit after about 40 s)
Screenshots: `AI/reports/HW-002-screens.png` (connector map and keyed broadcast status) and `HW-002-screens-mirror.png` (same panel scrolled: mirror status). The screenshot shows the Screens panel: an "SDI connectors" box for "Simulated SDI card (4 connectors)" with a Simulated badge listing connector 1 fill for Broadcast, 2 key for Broadcast, 3 output for Broadcast (mirror 1), 4 unused; the Broadcast row set to the simulated card, connectors 1 and 2, "Fill and key" ticked with "Uses connectors 1 and 2", Fill alpha Premultiplied, Video mode 1080p59.94, status "Running (Simulated)", 59.94 fps, presented 440, dropped 0, late 0, "health OK, frames repeated 0". The second image adds "Mirror 1: running (Simulated)", presented 594, dropped 0, late 0, health OK. Earlier capture of the live preview showed the checkerboard behind the keyed broadcast screen.
Exercised in the running app: launch, the Screens panel rendering from stored settings, a keyed SDI screen and an SDI mirror running live on the real-time simulated clock, connector map, live-preview checkerboard, a windowed mirror (the window opened). Home folder: nothing new left (prefs plist unchanged by hash; no Application Support entry).
**Not exercised in the app**: the window was off my Space at first, so I seeded the settings (developer setting, profile with SDI/mirror/keying) straight into the temporary library with sqlite3 and added two launch flags for runs that cannot click (`--open-screens`, `--show-screens-panel`). I did not click the destination pickers, Fill-and-key toggle, alpha control, mode picker, Add/Remove mirror, the Developer toggle, Simulate unplug/replug, or Go Live. Those paths are covered only by the `ScreenEditing`/coordinator unit tests. The Developer section was seen collapsed only. Unplug/replug in the UI was not run. No Go Live: the library had no presentation, so the keyed screen carried an empty transparent scene.

## Deviations and caveats
- Migration v6 (brief expected none); explained above.
- `--open-screens` and `--show-screens-panel` launch flags added to the app (test hooks, harmless otherwise).
- `FillKeySplitter` internals rewritten (behaviour identical; existing tests pass). `@_optimize(speed)` is used on its two loops.
- A simulated card has one clock: every connector ticks at the rate of the first running output's mode.
- The opaque-background warning is decided from the scene (colour alpha, video, background image or media), not from rendered pixels.
- A keyed Debug run of the app is heavier than Release because of the simulator's splitting; health stayed OK in my short run but I did not soak it.
- No `docs/` (status, change log, data dictionary for the new `extra` column, known issues) edited: not in my brief's scope; the coordinator should update them.

## Not verified
Real DeckLink hardware, real SDI timing/genlock, alpha behaviour on a real switcher, 59.94 vs 60 on a real card, Release-build app behaviour, long runs, the interface paths listed above, mirrors on a second physical display, `displayInUse` between a mirror and another screen in the UI.
