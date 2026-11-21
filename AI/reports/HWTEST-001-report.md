# HWTEST-001 report: hardware test kit and log bundle

Verification level: **Implemented and Unit Tested; Simulated at most. The kit has only ever seen a simulated card.** Nothing here is Hardware Verified. No SDK, nothing downloaded, `DeckLinkSDI` never imported, nothing under `Sources/DeckLinkC`, `Sources/DeckLinkSDI`, `Tests/DeckLinkSDITests` touched. No git state changed.

## Built
- `SDIEngine` (additive): `SDIInput.swift` (`SDIInputPort`, `SDICapturedFrame`, `SDIInputSignal`, `UnsupportedSDIInputPort`, `SimulatedFaults`); `SDIDevice` gained `associatedtype InputPort = UnsupportedSDIInputPort` and `openInput(connector:)` with a default that throws, so output-only devices still compile (tested with a legacy-only device). Simulator: `connect(output:toInput:)`, `disconnect(input:)`, `setFaults` (drop every Nth, swap fill/key, 1-pixel shift, wrong mode); an input receives what an output shows one frame later; unconnected means no signal. `TestPattern` (bars, counter strip 32 data + 8 CRC cells, alpha window, alpha ramp, grid, `decodeFrameIndex`, `compare`) and `CounterFrameSource`. `SDISessionStatistics` got public inits; the simulator caches the fill/key split of a still frame.
- `OutputEngine/HardwareTest/`: `HardwareTestRunner` + nine steps, bundle writer/loader (stored zip with CRC, own reader), summary, redactor, `HardwareTestController`, launch arguments and the headless run, `HardwareTestRig` (simulated card, cables, virtual clock, tester).
- App: `HardwareTestView` window, `HardwareTestSupport.swift`, menu Help > "Hardware Test…", `--hardware-test`, headless mode in `AppDelegate`.
- Docs: `docs/hardware-test-guide.md`, `docs/features/HWTEST-001-hardware-test-kit.md`.

## Tests (test-first)
95 new tests: `HWTEST_InputTests` 16, `HWTEST_PatternTests` 15, `HWTEST_BundleTests` 15, `HWTEST_RunnerTests` 33, `HWTEST_LaunchTests` 16 (launch, headless, controller). Each area's tests were run first and failed to compile on the missing API (output recorded in the session: "cannot find type 'HardwareStepResult'", "value of type 'SimulatedSDIDevice' has no member 'openInput'", "cannot find 'TestPattern'"), then the code was written. Behavioural failures found after: loopback counted one stale in-flight frame as 178 out-of-order frames (fixed in the simulator and the collector); a shift fault took 189 s in Debug (loop rewritten); frame stamping and decoding were unoptimised in Debug (moved to `@_optimize(speed)` pointer functions).

## Commands
- `swift test` in a scratch copy of the package (`scratchpad/wf-hwtest-pkg-7f3a`: Domain, RenderEngine, SDIEngine, OutputEngine and their tests, no other targets): exit 0, `Test run with 234 tests in 27 suites passed`, three times in a row.
- `swift test --package-path Packages/WorshipFlowKit` (real package) passed with 1189 tests earlier in the session; later runs fail to compile because other agents' unfinished `ScriptureEngine` and `CueEngine` tests/sources (`ReferenceFormatter`, `SearchFolding`, `MIDIBinding`...) are in the tree. Not mine.
- `./scripts/check.sh`: **exit 1 at the package-test step solely because of that unfinished work** (last: `BookNames.swift: cannot find 'SearchFolding'`). It had also failed with exit 1 when it did compile, on timing tests that are load-sensitive (`theRealTimeClockAdvancesAtTheModesFrameRate`, `renderThreadNeverStatsTheFile`); skipping all HWTEST tests passed 3 of 3 in one batch, but the same flakiness also appeared with my heavy suite skipped in a batch that overlapped another job, so I could not prove whether my tests add load. I serialised my heavy suites, made the simulated clock yield, and shrank durations; in the scratch package the clock test passed 3 of 3 and every full run of it. The real full run must be retried by the coordinator once the tree compiles.
- `xcodebuild ... build` (Debug, derived data in scratch): succeeded (exit 0, no errors) after the last source change.
- Headless: `WORSHIPFLOW --hardware-test --simulated --quick --output <scratch>/quick.zip --silent-audio` exit 0 in 21 s; with `--inject-faults` exit 0 in 20 s. Both summaries are in the reply message and the bundles are in `scratchpad/wf-hwtest-out/`.
- Window: `WORSHIPFLOW --hardware-test --library <scratch>/wf-hwtest-lib.sqlite --silent-audio`, screenshot `AI/reports/HWTEST-001-window.png`, app quit afterwards. Nothing left in the home folder (no Application Support folder, Desktop unchanged).

## Decisions and deviations
- The runner lives in `OutputEngine`, not `OperatorCore`: `OperatorCore` does not depend on `SDIEngine` and `Package.swift` is off limits. The files can move once the dependency is added.
- A real card provider does not exist in this build: `AppHardwareTest.realProvider()` returns no devices, and the window and report say "This build cannot talk to a card yet". Flip `realProviderIsConnected` when wired.
- Cabling is fixed: SDI 1 to SDI 3 and SDI 2 to SDI 4 (a keyed pair out on 1+2, inputs 3 and 4). The brief left it open.
- "Delay in frames" is output frames finished at arrival minus the frame's index; in the simulator it reads 1. On a real card it has about one frame of uncertainty.
- `defaultLaunchBehavior` scene modifiers did not open the hardware window or suppress the workspace in my run, so `HardwareTestLauncher` opens the hardware window and dismisses the workspace from the workspace's `.task`. The workspace window may flash briefly. Whether `dismissWindow` closed the workspace was not confirmed (a second window was still listed).
- Extra flags: `--inject-faults`, `--standard`, `--long`. `--output` takes a `.zip` path or a folder.
- AppModel: a headless run opens no library.
- `summary.txt` is a brief form (failed steps in full, others trimmed to six measurements; everything is in `report.json`; `LoadedHardwareTestBundle.fullSummary` renders all).
- Timestamps are UTC with no zone name; file name uses local time.

## Not verified
- Any real card, real SDI timing, whether `SDIInputPort` fits the real bridge, real YUV capture (thresholds 24 levels / mean 3 are guesses), UNV-02/03/04 answers (the simulator answers its own questions).
- The window's buttons in a running app: the window was off my Space, so I could take the idle screenshot but not click. Running state, prompts, Save report, Show in Finder, the save panel defaults (Desktop), and the photo picker were exercised only through `HardwareTestController` unit tests, never by clicking.
- The unplug step with a real unplug, the human step on a real monitor, responsiveness probe in the real app, long runs (Long preset never run), the displays list on a machine with other displays, Desktop Video detection (file check only).
- Debug-build timing: a quick run takes about 20 s in virtual time. A real quick run takes real time (about 100 s plus prompts).
