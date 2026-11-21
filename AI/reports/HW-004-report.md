# HW-004 report: the DeckLink bridge wired into the app and the hardware test kit

**Verification level: Implemented, Unit Tested, Simulated. NOT Hardware Verified. No real device has been seen.** This Mac has no DeckLink card and no Blackmagic Desktop Video driver (`/Library/Frameworks/DeckLinkAPI.framework` does not exist here). The only runtime state the real bridge was ever in is "driver not installed". Every route, profile and key decision below that concerns a card comes from the vendor manual's table or from the simulator, never from a measurement. Nothing was downloaded or installed, no git state was changed, the vendor files in `Sources/DeckLinkC/sdk/` and everything of the scripture agent's (`ScriptureEngine`, its tests, `LIB-004`) were not touched. `Package.swift` and `project.yml` were not edited: `DeckLinkSDI` was already a dependency of the app target, and no `Package.swift` change was needed.

## What was built

**SDIEngine (KI-056, KI-053, KI-054), source compatible**
- `SDIError.hardwareFault(detail:)`. The bridge now maps SDK failures (`sdkFailure`, `outOfMemory`, `profileTimeout`, `busy` at run time, and any error it does not recognise) to it, carrying the bridge's words and the SDK result code. Only a removed device or a missing driver still means `.deviceDisconnected`.
- `SDIDeviceReport.swift`: `SDIKeyRoute` (pair's first connector, fill connector, key connector, source: manual table / simulator / assumed), `SDIConnectorInfo` (what each connector can do, and its role when keyed), `SDIProfileState` and `SDIProfileChange` (what a pair's profile is, whether it can key now, what switching would do and which connectors it may interrupt, with the question put to the operator). `SDIDeviceInfo` carries `keyRoutes`, `connectors`, `profiles`, all defaulted, so every existing initialiser call compiles unchanged.
- `SDIProvider.swift`: `SDIProvidedDevice` (a device as closures), `SDIDeviceProviding` (`currentDevices()` which never scans, `rescan()`, `events()` as an `AsyncStream<SDIDeviceEvent>`, `environmentStatus()` with an operator-readable message and one of four states: driver not installed, no card found, card found, simulated), `SimulatedSDIProvider` (unplug and replug are events), `CompositeSDIProvider` (merges devices and events; its environment is the first non-simulated provider's, so a simulated card beside a missing driver cannot hide it).
- `SDIKeyingProfile.swift`: the decision (`notNeeded` / `unavailable` / `askOperator`) and `ensure(...)`, which asks only when a change is needed, switches only after a yes, and reports `switched`, `declined` or `failed` with the reason. Used by the app and by the kit.
- Simulator: reports the route it implements (fill on the first connector of each pair, so default behaviour is unchanged), and `SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute` implements the other order on the wire, for the planner, the interface and the kit to be exercised against.
- Planner (KI-053): `SDIConnectorPlanner.plan(..., keyRoutes:)` plans fill and key on the connectors the device reports; with no route it behaves exactly as before. `SDIAssignment` gained `fillConnector` (defaulting to `connector`); `keyConnector` is now the physical key connector, which equals the pair's second connector unless the route is reversed. The port still opens on the first connector of the pair.

**DeckLinkSDI**
- `DeckLinkDeviceReport` (pure functions): key routes from the layout (the Duo 2's manual table: fill on the second connector of each pair, key on the first; marked `manualTable`; other models report the old convention marked `assumed`), connector roles, per-pair profile state, and the environment state in words.
- `DeckLinkDevice.info` now reports routes, roles and profile state; `provided()` hands the card out as an `SDIProvidedDevice` including `activateKeyingProfile`; `activateKeyingProfile(firstConnector:)` picks the card's own keying profile and waits for it.
- `DeckLinkDeviceProvider` conforms to `SDIDeviceProviding`. `events()` starts hot-plug monitoring on first use (it fans out to any number of subscribers) and ends at once when there is no driver.
- `DeckLinkEnvironment` records whether the framework's files exist on disk (`frameworkOnDisk`): files present but not loadable (the KI-055 entitlement problem) is reported as its own state, not as "not installed".

**OutputEngine and the kit**
- `SDIDeviceHandle(_ provided)`; `OutputPlanner` passes the device's routes to the planner; `PlannedSDIOutput.fillConnector`. The connector map therefore shows "Connector 1: key for X / Connector 2: fill for X" when the route is reversed.
- Kit: `HardwareTestProvider(provider:)` (the kit's view of any `SDIDeviceProviding`), `HardwareTestDevice(_ provided)`, `HardwareDriverStatus.frameworkLoadable`, `HardwareCardState.describe` (three states and their wording), `HardwarePromptKind.changeProfile`, `HardwareTestController.cardState`, `rescan()` (off the main thread), `verdictLine`.
- Environment step records the driver state, the driver API version, the entitlement check ("Framework can be loaded") and the reported key route of each connector pair.
- Fill-and-key step: reads the reported route, measures which connector carries what, compares both with the manual's table (Duo 2 only) and states plainly which the hardware agrees with, plus whether the app's old assumption holds. A card whose profile cannot key is switched only after the tester says yes; a run with no person never switches. A measurement that contradicts the device's report fails the step ("reversed"); disagreement with the manual's table is a finding, not a failure.
- Summary: the first line is `REAL DEVICE TESTED: <name>`, `NO REAL DEVICE WAS TESTED: ...` or `SIMULATED RUN: ...`; a "THE DRIVER AND THE CARD" block repeats the driver facts and routes even in the trimmed summary. `OperatorCore` still does not depend on `SDIEngine`; the runner stays in `OutputEngine`.

**OperatorCore and the app**
- `SDIDeviceSummary.keyRoutes`, `ScreenEditing.keyingCaption(connector:device:)` ("Uses connectors N and M: fill on N, key on M"), and the keyed destination label names the route when it is known. The original `keyingCaption(connector:)` is unchanged.
- App: `AppSDI.deckLink` is the one real provider; the app's provider is `CompositeSDIProvider([deckLink] + simulated card only when the developer setting is on)`. Cards are scanned once off the main thread, then followed by hot-plug events. With no driver the Screens panel shows one calm line with a Rescan button ("Blackmagic Desktop Video is not installed on this Mac. SDI outputs need it. Install ... Screens on displays and windows still work.") and no dialog. "Open screens" first asks the operator before changing a card's profile for a keyed screen (the question names both profiles and warns that other outputs may be interrupted), switches through the bridge, and shows the outcome as one line in the panel; if the operator declines or the switch fails the screens still open and the keyed screen reports its own fault.
- Hardware Test window: three states in plain words (driver not installed with what to install; driver installed but no card found, check the Thunderbolt cable and that the enclosure is switched on, then Rescan; card found), a **Rescan** button, and a verdict banner on the finished screen. The old "cannot talk to a card yet" wording and `realProviderIsConnected` are gone.

**Docs:** `docs/hardware-test-guide.md` (three states, the profile question, what the first line means, what the report compares), `docs/features/HWTEST-001-hardware-test-kit.md`, `docs/16-known-issues.md` (KI-053 to KI-056, KI-059, KI-060 updated; none marked verified).

## KI-060: the two flaky tests, and one more found

Baseline before any change (scratch copy, full suite): `Test run with 1189 tests ... failed ... with 1 issue`: `renderThreadNeverStatsTheFile` failed on `drewRed` (the first image load runs on a low-priority background thread and the test gave it 2.6 s of wall-clock time).

- `theRealTimeClockAdvancesAtTheModesFrameRate`: `SimulatedClockDriver` now takes an injected `SDIClockTimeSource` (system by default). The pacing rule is a pure `SDIClockPacer` (wait or fire one frame), tested for every video mode over ten simulated seconds, for a stalled thread and for a slightly late one. The thread-level test runs the real clock thread against a time source the test moves by hand and holds at a limit, and asserts the exact count (59 frames in one second at 59.94, 8 in 150 ms); "the clock must stop" is asserted by releasing the thread and joining it (`waitForThreadsToExit`). The shared-clock test uses the same source. No sleeps.
- `renderThreadNeverStatsTheFile`: the first load is done up front with `prepare(scene:)`, the compositor's clock is injected (`Compositor.uptime`), moved by hand past three re-check intervals, and the test waits for each background re-check through `ImageDecoder.backgroundLoadFinishedProbe` (a continuation, not a sleep). It now proves more than before: exactly three re-checks happened, all off the render thread, none on it. `changedFileIsStillReloadedInTheBackground` and `failedReloadKeepsThePreviousTextureAndReportsTheProblem` use the same method (they used a 4 to 5 s polling timeout). The unused `settle` helper is gone.
- Found by running the suite under load (14 busy processes): `secondScreenReusesTheDecodeAndDrawsOnItsFirstFrame` failed 2 of 2 under load (same cause: a 4 s `settle` that ignored its result). It now loads the first screen with `prepare(scene:)`.
- Found in one plain run: `theHealthCallbackFiresOnce` (`MediaEngineTests/EngineReviewFixTests.swift`) failed once (`TestMedia.wait` gave AVFoundation 8 s to report a failed item). `TestMedia.wait` now defaults to 60 s, documented as a hang guard rather than a threshold; every caller waits for something to happen and passes as soon as it does. This one is a poll with a deadline, not an injected clock: AVFoundation's own timing cannot be injected. The 300 ms "no second event" grace after the first event is unchanged (it can only miss a duplicate, never fail a good run).

## Tests (test-first)

New tests: `HW004_RouteAndProviderTests`, `HW004_KeyingProfileTests` (SDIEngineTests), `HW004_DeviceReportTests` (DeckLinkSDITests), `HW004_KitTests`, `HW004_PlannerAndHandleTests` (OutputEngineTests), `HW004_KeyingCaptionTests` (OperatorCoreTests), plus the rewritten clock and compositor tests above. The full scratch suite grew from 1189 to 1272 tests.

Red evidence, recorded in the session scratch folder:
- Kit and planner behaviour (`hw004-red-kit.log`): `Test run with 72 tests in 17 suites failed after 2.309 seconds with 26 issues`, for example `Expectation failed: (s.value("Route reported by the device") -> nil) == "fill on SDI 2, key on SDI 1"`, `(tester.kinds -> [connectKeyCables]).contains(.changeProfile)`, `(calls.all -> []) == [1]`, `(s.outcome -> .failed) == .passed` for a reversed card.
- Everything else (`hw004-red-modules.txt`, `hw004-red-ki060.txt`): the new test files fail to compile against the pre-HW-004 sources, for example `cannot find 'SDIClockPacer' in scope`, `type 'SDIError' has no member 'hardwareFault'`, `cannot find 'SDIKeyRoute' in scope`, `cannot find 'DeckLinkDeviceReport' in scope`, `extra argument 'keyRoutes' in call`.
- Honest note on order: for the SDIEngine, DeckLinkSDI, OperatorCore and clock/compositor areas I wrote the tests and then the code, and captured the red output afterwards by putting the pre-HW-004 sources back into the scratch copy, building, then restoring them. The kit and planner red run is a real behavioural failure captured before the kit logic was written.

## Commands and results

| Command | Result |
|---|---|
| `swift test` in `wf-hw004-57a7b291` (scratch copy of the package without `ScriptureEngine`), baseline before changes | exit 1, 1189 tests, 1 issue (`renderThreadNeverStatsTheFile`) |
| same, five runs in a row after all changes | 5 of 5: `Test run with 1272 tests in 195 suites passed` (37.2 to 38.0 s each), exit 0 each |
| same, three runs with 14 busy processes running (`yes`) after the flake fixes | 3 of 3 passed (about 61 s each). Before the fix, 2 of 2 failed on `secondScreenReusesTheDecodeAndDrawsOnItsFirstFrame` |
| `./scripts/check.sh` (with `WF_DERIVED_DATA` in scratch) | **exit 0**, `== OK`. Package step: `Test run with 1381 tests in 205 suites passed after 37.681 seconds` (the scripture agent's code compiled at that moment and is included) |
| `swift test --package-path Packages/WorshipFlowKit`, five more runs in a row | 5 of 5: `Test run with 1381 tests in 205 suites passed` (37.4 to 37.8 s each), exit 0 each. This is the real tree including `ScriptureEngine` |
| `xcodegen generate` (inside check.sh) | exit 0; `WORSHIPFLOW.xcodeproj/project.pbxproj` changed only because `App/Sources/SDIProviders.swift` is new |
| `xcodebuild ... build` (inside check.sh, and earlier by hand) | exit 0 |
| `WORSHIPFLOW --hardware-test --output real.zip --silent-audio` (no `--simulated`) | exit 0 in under a second: `NO REAL DEVICE WAS TESTED`, 1 passed, 1 failed (devices, as expected), 7 skipped. Full `summary.txt` is in the reply to the coordinator |
| `WORSHIPFLOW --hardware-test --simulated --quick --output sim.zip --silent-audio` | exit 0 in 20 s: `SIMULATED RUN`, 7 passed, 0 failed, 2 skipped |
| `WORSHIPFLOW --library <scratch>/lib.sqlite --silent-audio`, three times, 8 to 12 s each | launches and stays running with no driver and no stderr output; killed by me; window captured once with `screencapture -l` (workspace, not the Screens panel); nothing left in `~/Library/Application Support` |

## Coordinator decisions needed

None of the coordinator-owned tests contradicted anything: `SDIEngineTests` (including the fixed fill-on-first-connector planner tests) and `HW002_*` / `HWTEST_*` tests pass unchanged, because with no reported route (and with the simulator's default route) the behaviour is identical. Tests I did edit, and why:
- `DeckLinkSDITests/DeckLinkMappingTests.bridgeErrorsBecomeEngineErrorsAccordingToWhereTheyHappened` (HW-003): it pinned `.sdkFailure` and an unrecognised error to `.deviceDisconnected`; the brief requires the bridge to map them to the new hardware-fault case, so two expectations changed. Please confirm this is acceptable.
- `RenderEngineTests/EngineReviewFixTests` (`renderThreadNeverStatsTheFile`, `changedFileIsStillReloadedInTheBackground`, `failedReloadKeepsThePreviousTextureAndReportsTheProblem`, `secondScreenReusesTheDecodeAndDrawsOnItsFirstFrame`), `SDIEngineTests/HW002_SessionAndClockTests` (the two clock tests), `MediaEngineTests/TestMedia.swift` (one default): all KI-060, as the brief asked.

## Deviations from the brief and decisions

- The reported route for a DeckLink is not "queried from the device": the SDK has no attribute for it, so the adapter reports the manual's table and labels the source. The kit's measurement is the only independent answer, and its report says so.
- A DeckLink reports its route whatever the current profile is, and the pair's profile state says whether keying is available now. This lets the planner and the connector map show the route before a profile switch.
- The provider's `currentDevices()` never scans; the app scans once at start (off the main thread), on hot-plug events and on Rescan. `DeckLinkDeviceProvider.devices()` still scans, as before.
- Supported video modes for a DeckLink are still "all known modes" in the handle; per-mode probing happens when a port is opened. Not narrowed.
- Connector roles are the layout's current roles; the profile "interrupted connectors" are conservatively every connector of the card, because the SDK does not say which ones drop out.
- The profile question is asked when screens are opened, not when the keying toggle is clicked, so the operator is asked once, at a moment when interruption is the least surprising.
- `driverMissingMessage` was reworded ("SDI outputs need it", "Screens on displays and windows still work"); the driver-absent tests pin only its prefix.
- `sync.sh` in the shared scratchpad folder was overwritten by my own sync script (it was an older, unrelated script from another session; scratch only).

## Not verified

- **No real device has been seen.** Not one call that reaches `IDeckLinkOutput`, `IDeckLinkInput`, `IDeckLinkKeyer`, `IDeckLinkProfile*`, `IDeckLinkDiscovery` with real devices, or the framework loader with the driver present has run. Hot-plug events, `rescan()` with cards, `info` with real profile data, `activateKeyingProfile` (including the five second wait for `ProfileActivated`) and the profile list of a real Duo 2 are all untested.
- The key route, which connector carries the fill (KI-053), whether the Duo 2 needs the one-sub-device full-duplex profile for keying (KI-054), and whether `disable-library-validation` lets a signed build load the framework (KI-055) are all still open questions for the hardware test. The kit now records what it needs to answer them.
- The SwiftUI changes were compiled and the app launched, but not clicked: the Screens panel line and its Rescan button, the profile alert, the Hardware Test window's three card states and Rescan, and the verdict banner were never seen on screen. The wording of each state is unit tested as text. The Screens panel was not visible in the one window capture.
- The reversed route was exercised only on the simulator (planner, connector map, caption, kit); a device whose route differs from the manual's table has never been observed.
- The `.task`-driven rescan when the Hardware Test window opens, and the main-thread behaviour with a real driver (a scan is off-main by construction, not measured).
- `theHealthCallbackFiresOnce` and the other AVFoundation waits are still wall-clock polls with a 60 s guard, not injected clocks.
- The five consecutive scratch runs exclude the scripture agent's `ScriptureEngine` (by instruction); the real package was run in full by `./scripts/check.sh` and by the five runs below.

## Final five runs of the real package

`swift test --package-path Packages/WorshipFlowKit`, five times in a row after `./scripts/check.sh` had exited 0: 1381 tests in 205 suites passed on all five (37.501, 37.392, 37.771, 37.409, 37.472 s). No test failed intermittently in these or in the five scratch runs after the last fix.
