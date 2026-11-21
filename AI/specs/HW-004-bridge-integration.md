# Brief: HW-004 — wire the real DeckLink bridge into the app and the hardware test kit

Read first: `CLAUDE.md` (hardware rules, verification levels), `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md`, `docs/adr/0006-decklink-sdk-licence.md`, `docs/16-known-issues.md` (KI-052 to KI-056), `AI/reports/HW-003-report.md` (all of it, especially sections on what `SDIEngine` lacks and the questions for the hardware test), `AI/reports/HWTEST-001-report.md`, `AI/reports/HW-002-report.md`, `Sources/SDIEngine`, `Sources/DeckLinkSDI`, `Sources/OutputEngine` (`SDIEnvironment`, `OutputPlanner`, `SDIOutput`, `HardwareTest/`), `Sources/OperatorCore`, `App/Sources/AppModel.swift`.

**This Mac has no DeckLink card and no Desktop Video driver.** Everything here can be compiled, unit tested against fakes and the simulator, and run in the "driver not installed" state. Nothing becomes Hardware Verified in this slice. Say so wherever status is written.

## Rules

Test first for every decision: failing test, recorded output, then the fix. Keep the vendor files in `Sources/DeckLinkC/sdk/` untouched. Do not edit coordinator-owned tests; if a change genuinely contradicts one (for example the planner's fixed fill-on-first-connector assumption in `SDIEngineTests`), stop and report it with the exact test names instead of editing — the coordinator owns that decision.

## What to build

1. **Fold the bridge's gaps into `SDIEngine`** (KI-056), source-compatibly:
   - `SDIError.hardwareFault(detail:)` (or equivalent) so SDK failures are not reported as "disconnected"; the bridge maps to it.
   - A provider protocol (`SDIDeviceProviding`: current devices, hot-plug events as an async stream or callback, environment status with an operator-readable message) that both the simulator and `DeckLinkDeviceProvider` conform to; a composite provider that merges several.
   - A device-reported **key route** per connector pair (which connector carries fill, which key) and device-reported connector roles and profile state, as data on the device info. The simulator reports the route it implements.
2. **The connector planner follows the device** (KI-053): `SDIConnectorPlanner` (or the `OutputPlanner` that calls it) takes the device-reported route when one is given and plans fill and key accordingly; with no reported route it behaves exactly as today so the existing coordinator tests pass unchanged. The connector map, the keying caption ("Uses connectors N and M: fill on N, key on M") and the hardware test's expectations all read the same reported route. Add simulator tests with the route reversed.
3. **Profiles for keying** (KI-054): when a keyed output is requested on a device that reports it needs a profile change, the app asks the operator before changing it (it can interrupt the other connectors), activates it through the bridge, and reports success or the reason for failure. Decision logic tested with a fake device.
4. **The app's SDI provider**: the app uses the composite provider — the real DeckLink provider always, plus the simulated card only when the developer setting is on. With no driver: the Screens panel shows one calm line ("Blackmagic Desktop Video is not installed on this Mac. SDI outputs need it." with what to do), never an error dialog, and everything else works (DIST-06, DIST-07). Add `DeckLinkSDI` to the app target's dependencies in `project.yml` if it is not there.
5. **The hardware test kit uses the real provider** by default and the simulator only when asked. Its environment step records the driver state, the API version, the entitlement check (can the framework be loaded: KI-055), and the device-reported key route; its fill-and-key step compares the measured route with the reported one and with the manual's table, and states plainly which the hardware agrees with. Its report must make it obvious on the first screen whether a real device was tested.
6. **A dry run here**: run the kit headless on this Mac without `--simulated`. Expected: it finds no driver, says so clearly, writes a bundle, exits 0. Include that `summary.txt` in your report. Then with `--simulated`: include that too.
7. **Docs**: update `docs/hardware-test-guide.md` if the steps or wording changed; update `docs/16-known-issues.md` entries KI-053 to KI-056 with what changed (do not mark anything verified).

## Do not modify

Coordinator-owned tests. `Package.swift` (say what is needed if anything), `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, the vendor files, existing migrations.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, nothing blocking the main thread, no exceptions crossing the Objective-C boundary. Do not commit or change git state. Do not consult any advisor tool. Do not download or install anything (in particular not the Desktop Video driver). Do not request full computer control. If you launch the app: temporary `--library`, `--silent-audio`, under a minute, never cover a display, leave nothing in the home folder. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0. Paste the test summary line.
2. Both headless summaries are in the report.
3. `AI/reports/HW-004-report.md` records what was built, any coordinator test that needs a decision, commands run with exit status, and everything not verified — stating plainly that no real device has been seen.
