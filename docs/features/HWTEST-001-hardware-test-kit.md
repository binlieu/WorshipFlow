# HWTEST-001: hardware test kit and log bundle

Verification level: **Implemented and Unit Tested; Simulated at most.** The kit has only ever run against the simulated card. Nothing here is Hardware Verified. It exists so a person with a real DeckLink Duo 2 can produce evidence for UNV-02, UNV-03 and UNV-04.

## Where things are
- `SDIEngine`: `SDIInputPort` and `SDIDevice.openInput(connector:)` (`SDIInput.swift`); the simulator's BNC cable and fault injection (`SimulatedSDIDevice.connect(output:toInput:)`, `setFaults`); `TestPattern`, `CounterFrameSource` (`TestPattern.swift`).
- `OutputEngine/HardwareTest`: `HardwareTestRunner`, the nine steps, bundle, summary, zip, launch arguments, `HardwareTestController`. (It is here and not in `OperatorCore` because `OperatorCore` does not depend on `SDIEngine` in `Package.swift`.)
- App: `HardwareTestView` (window), `HardwareTestSupport` (displays, driver check, launch mode). Since HW-004 the real card provider is connected: `AppHardwareTest.realProvider()` wraps the DeckLink bridge (`AppSDI.deckLink`) and the kit finds cards through `SDIDeviceProviding`. It has only ever run in the "driver not installed" state; no real device has been seen.

## Steps and pass criteria
All thresholds are written into each step's result.

| # | Step | Needs | Pass when |
|---|---|---|---|
| 1 | Environment | nothing | OS version readable. Records app, macOS, Mac model, chip, memory, displays and refresh rates, driver state. No user name, home path or serial number. |
| 2 | Devices | nothing | A connected device is reported. Records model, connectors, keying, profile, modes per connector for output and input, simulated or not. |
| 3 | Output run | a device | Colour bars plus frame counter at 1080p59.94: zero dropped, zero late, at least 90% of expected frames, still running. Per-second samples; times of problems listed. |
| 4 | Loopback | cable SDI 1 to 3 | Signal in 1080p59.94 within 5 s; no missing, repeated or out-of-order frames; all counters readable; at least 90% of frames; pixel error at most 24 of 255 (mean 3.0). Delay in frames is reported, not judged. |
| 5 | Fill and key loopback | cables 1 to 3 and 2 to 4 | Fill and key where the device reports them (with no report, fill on SDI 1 and key on SDI 2), measured and compared with the device's report and the manual's table (UNV-03); asks before changing a card's profile (KI-054); key within 16 levels of the alpha at box centres and surround, mean error at most 4; fill premultiplied or straight as configured; alpha ramp within 24. Both alpha modes. |
| 6 | Mode sweep | a device | The device says 1080p59.94 is supported for output and with fill and key (UNV-02). No video runs: it is the device's own answer. |
| 7 | Four outputs | four connectors | Zero dropped and late on all four; memory and CPU sampled each second (UNV-04). |
| 8 | Unplug and replug | optional | Engine reports the failure within 10 s, app answers within 1 s, device found again, output restarts. |
| 9 | Human checks | optional | Tester answers yes to what they see; any no fails; photos attached by neutral name. Unanswered: needs a person. |

The runner never stops at a failure. A step that throws is marked failed; one that hangs is abandoned at its timeout (time spent waiting for the tester does not count). Steps that cannot run are skipped with the reason. The bundle folder is rewritten after every step.

## Bundle
One `.zip`: `report.json` (versioned schema, every result and raw samples), `summary.txt` (statement, table of steps, details, findings), `engine-log.txt`, `photos/`. File name: `<date>-WORSHIPFLOW-hardware-test.zip`, with `SIMULATED-` added for a simulated run, whose first summary line also says SIMULATED. Load one with `HardwareTestBundle.load(from:)`; `fullSummary` renders every measurement.

## Launch
- `--hardware-test`: open the window.
- `--hardware-test --simulated --quick --output <path>`: no window; run, write the bundle (`.zip` path, or a folder), exit 0 if written. Add `--inject-faults` to drop every 7th frame and swap fill and key. `--standard` and `--long` pick other lengths.

## Not verified
Real card, real timing, whether `SDIInputPort` fits the real bridge, the window's buttons in a running app, long runs.
