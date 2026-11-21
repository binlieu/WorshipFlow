# FIX-D report: second-review fixes in the hardware test kit, the app and the operator core

Date: 2026-11-21. Scope: findings S1, S2, S3, S4, S5, S6, S7, S14, S15 and the Blackout clip-sound decision of `AI/reports/REVIEW-2-findings.md`.
Nothing here was run against a real card or a real operator session: every kit result is SIMULATED; the app glue is unverified (last section).

## Result

- `./scripts/check.sh` exited 0 (package tests, domain boundary, project generation, app build) at the end: 1815 tests in 276 suites passed. The tree included the other agents' work at that moment.
- 78 new tests in 12 files named `FIXD_*` (OutputEngineTests 57, OperatorCoreTests 21). Evidence files with the raw runner output are in `AI/reports/fixd-evidence/` (`*-before.txt` recorded against the earlier code, `*-after.txt` after the fix).
- How "before" was recorded: where a test used only the API that existed before, it was run against a scratch copy holding the committed kit (`git show HEAD`): S3, S5, S6 (running step), S7, S14 (`S3-S7-S14-before.txt`, `S5-before.txt`, `S6-before.txt`). S1 and S2 were run against the unfixed code in the working tree (`S1-before.txt`, `S2-before.txt`; S1 needed only the test double). Tests that need new API (S4's identity, S6's offer, S15, Blackout) cannot compile against the earlier code; their "before" is the missing feature, and S4's honesty rule has a before-test in the S3 file (`fourOutputsWithNoCablesAreNotPassed`: the earlier kit says PASSED with no cable connected).
- Existing tests changed: two photo fixtures (`HWTEST_BundleTests.photosAreCopiedByNameWithoutTheirPath`, `HWTEST_RunnerTests.aNoFailsAndAPhotoIsAttachedWithoutItsPath`) used 2 to 4 raw bytes as a "photo" and compared the stored bytes with the original. S5 requires re-encoding, which cannot keep a non-picture, so the fixture is now a real small JPEG and the byte comparison became "decodable, 64 px wide, not the original bytes". Their other assertions are unchanged. No test was deleted. Two other existing tests failed first on wording and were met by wording, not edited: the first-line tests (the incomplete notice stays on the second line) and the "old assumption ... wrong" finding (kept, now conditional on the cables being as shown).

## S1 (critical): profile not restored, later steps used fixed connectors. Fixed.

- Fix: `HardwareTestLayout` (pure) chooses output, loopback, keyed pair and four-output sets from `SDIDeviceInfo.connectors` as it is now; `HardwareTestContext` records the profile before step 1 (`captureProfiles`), the runner restores after the step that switched it (`restoreProfiles`, 3 attempts), reads the card back and compares record and layout; the kit never restores by asking. Report fields `profileAtStart`, `profileRestore`; step field `profileNote`; headline line when restore failed or could not be verified ("THE CARD'S PROFILE WAS NOT RESTORED ... steps after it ran in the keying profile"). Steps that need a keying profile after the first consent (6, 9) switch again without a second question and are restored again. If no pair can receive two inputs in the layout now (both-pairs profile change) step 5 is skipped with that reason, not failed.
- Simulator: `SimulatedProfileCard` in the kit (`HardwareTestSimulation.swift`): profile per pair, `onePair` / `bothPairs` scope, faults `restoreFails`, `restoreHasNoEffect`, `switchFails`; nothing added to `SDIEngine`.
- Failed before: `S1-before.txt` (30 issues in 10 tests, e.g. mode sweep FAILED after the profile change, no restore record). Pass after: `S1-after.txt` (10 tests). Tests: `FIXD_S1_ProfileRestoreTests` (restore and verify for one pair; both-pairs; restore fails; restore with no effect; a card that cannot restore; declined change leaves no record; start in keying profile uses SDI 2; planner).
- Unverified: the real restore (`AppHardwareTest.restoreProfiles` through `DeckLinkDevice.activateProfile`), which needs a card; the Duo 2 layout is the manual's table, not hardware.

## S2 (high): Go Live after countdown then slide. Fixed (two causes).

- Fix: `WorkspaceModel.openPlaylistItemID` records the item the open song came from; `selectSlide` and `goLive(at:)` make the open song the target when a countdown was selected (`chooseOpenPresentation`); `recordLiveSource` records the live item against `openPlaylistItemID`; arrangement lookups (`reloadOpen`, `requireNaturalOrder`, `setArrangement`) use it too. Second cause found while testing the sequence countdown live then slide: `goLiveOnCountdown` left the countdown deck as the preview deck, so a slide chosen next indexed the wrong deck; it now restores the open presentation as the preview with the operator's selection.
- Failed before: `S2-before.txt` (19 issues, e.g. Go Live starts "5:00", `liveItemID` is the countdown). Pass after: `S2-after.txt`. `FIXD_S2_GoLiveTargetTests` (10): the finding's sequence with Next and Previous after it, countdown chosen last, countdown live then slide, double-click, Next with nothing live, library song, saved place.

## S3: steps PASSED with unmeasured parts. Fixed; new outcome PARTLY MEASURED.

- Fixed: unplug with the replug skipped (partial, says unplug measured, replug not), unplug with the app's response time unmeasured (partial), human checks with one question skipped or not asked (partial; before it was SKIPPED and lost the yes, or PASSED when the keyed question could not start), four outputs without identity (S4), mode sweep when the keyed answer was asked of a pair not in a keying profile (partial, "not asked").
- Audited and unchanged because they claim only what they measure: environment (passes on a readable OS version only), devices (connected device), output run (frames, late, dropped, still running), loopback (signal, order, pixels, mode), fill and key (every phase and both alpha modes must measure; a missing signal, unclear role or setup failure is a problem), mode sweep's plain answer (states it is the device's own answer), runner (a timeout or throw is a failed step).
- Before: `S3-S7-S14-before.txt`; after: `S3-S7-S14-after.txt`. `FIXD_S3_HonestStepTests`.

## S4: four outputs passed on counts. Fixed per the decision.

- Each output's connector number is in the top bits of its frame counter (`ConnectorIdentity`, covered by the counter's check bits). Step 7: cables 1 to 3 and 2 to 4 (Continue or Skip), identity phase with two outputs and two inputs; then move to 3 to 1 and 4 to 2 (Skip leaves 3 and 4 unchecked); a prompt to take the cables off; then the four outputs together. Per connector: "confirmed", "WRONG: SDI i received the picture sent on SDI k", or "ran, identity not checked (reason)"; result PASSED / FAILED / "ran, identity not checked". Step outcome: failed on any statistic or WRONG, passed only if all four confirmed, otherwise partly measured. A layout in which not all four connectors can send is skipped with the reason.
- Simulator fault: outputs wired the wrong way round inside the card (`swappedOutputs`, in the cables the simulated tester places). Swapped within a half (1 and 2) is caught as WRONG; swapped across the halves (2 and 4) shows as no signal, never PASSED.
- Tests `FIXD_S4_IdentityTests` (8) and the S3-file test above.

## S5: bundle privacy. Fixed per the decision.

- Card id: `HardwareTestHash.short` (8 hex characters of SHA-256) in `report.deviceID`. Photos: decoded (orientation applied) and written again as a plain JPEG, no metadata, `photos/photo-N.jpg`; a file that cannot be read as a picture is refused with an error that does not name it. Log: "Answer: a photo was chosen", and "A photo could not be attached ..." without name or path. Names: the redactor also scrubs the full user name, the Mac's name and the host name (4 characters or more) wherever they appear, including display and device names; other display names are kept.
- Failed before: `S5-before.txt` (17 issues: the path and file name in the log, GPS and camera tags retained, the card id as is). Pass after: `S5-after.txt`. `FIXD_S5_PrivacyTests` includes the run with a photo on `/Volumes/CHURCH-USB-STICK/...` and a photo with GPS, asserting neither survives; `FIXD_S5_NamesTests`.
- Not done: the hash is not salted (a short hash of a known id can be matched by anyone who has the id; it is not meant to resist that).

## S6: partial results invisible after a crash. Fixed per the decision.

- A real run writes its files to `<date>-WORSHIPFLOW-hardware-test-unfinished` in the Desktop (or `--unfinished-folder <dir>`); the report records `runningStep` before each step; the folder is removed after a successful save; at launch the Hardware Test window offers "Save its report..." for a folder left behind, which zips it with a first line "THIS TEST DID NOT FINISH: it stopped during step N, <title> ..." (or "THIS TEST FINISHED, but its report was not saved ..."), scrubbed. Simulated demonstrations write nothing to the Desktop. The guide explains it in two sentences.
- Before: `S6-before.txt` (the file never names the running step). After: `S6-after.txt`. `FIXD_S6_RunningStepTests`, `FIXD_S6_UnfinishedTests` (11).

## S7: crossed cables stated as fact. Fixed.

- Finding wording: "with the cables as instructed (...), the fill arrived on SDI x and the key on SDI y; ... if the cables are as shown. Two cables swapped would look the same." A result that is the reverse of the reported route asks "Please check the cables" (`confirmCables`) and repeats the window phase once; both runs are in the measurements ("First run: ..."), and the finding says whether the second run agreed with the first or reversed it ("most likely a cabling mistake"); a skipped confirmation keeps the first result and says it was not repeated.
- Before: `S3-S7-S14-before.txt`; after: `S3-S7-S14-after.txt`. `FIXD_S7_CablingTests` (5).

## S14: headline on a diagnostic export. Fixed.

- `HardwareTestSummary.headline`: "DEVICE INFORMATION ONLY: no video test was run ..." when no video step ran (passed, failed or partial); the mode sweep and a skipped step do not count. A report with no step at all keeps its old first line (it is the file written before step 1). Before/after as S7.

## S15: key monitor with the Hardware Test window. Fixed in decisions; glue untested.

- `KeyRouting.transportKeysActive(windowTitle:windowIdentifier:launchedWithHardwareTest:)` (4 tests): off for the Hardware Test window and for every window of a `--hardware-test` session. `AppModel`'s key monitor calls it. `HardwareTestGuard.screensRefusal` (tested) is called by `AppModel.startScreens()` while a run is going (the controller reports start and end through `onRunningChange`); it sets the notice and shows an alert.

## Blackout and clip sound: done at model level.

- `MediaModel.showStateChanged(isLive:isBlackedOut:)` sends the foreground player a muted level while Blackout is on and the operator's level when it lifts; volume or mute changes during Blackout stay silent; Stop ends it; the operator's own mute is never cleared. `FIXD_BlackoutAudioTests` (7), including the workspace's Blackout driving it as the app wires it. No before-test (the hook did not exist).

## Seeing it run (headless, simulated, `--hardware-test --simulated --quick --output`; built app, scratch folders)

Clean run, `summary.txt`, first 40 lines:

```
SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware.
Device tested: Simulated SDI Duo 2 card (4 connectors, profiles) (SIMULATED, no real card)
The card's profile before the test: connectors 1 and 2: half duplex; connectors 3 and 4: half duplex. Layout: SDI 1: out/in; SDI 2: out/in; SDI 3: out/in; SDI 4: out/in
This report describes what was measured on this run. It is not a certification.
Started 2026-11-21T13:31:42Z UTC, finished 2026-11-21T13:32:02Z UTC. Length chosen: quick.
Totals: 7 passed, 0 failed, 2 skipped, 0 needs a person

STEPS AND OUTCOMES
1. Environment                    PASSED
2. Devices                        PASSED
3. Output run                     PASSED
4. Loopback                       PASSED
5. Fill and key loopback          PASSED
6. Mode sweep                     PASSED
7. Four outputs at once           PASSED
8. Unplug and replug              SKIPPED
9. Human checks                   SKIPPED

THE DRIVER AND THE CARD
  - Blackmagic driver: not installed
  - Framework can be loaded (entitlement check): unknown: no driver was found
  - Key route reported by the device (connectors 1 and 2): fill on SDI 2, key on SDI 1
  - Key route reported by the device (connectors 3 and 4): fill on SDI 4, key on SDI 3

DETAILS

1. Environment: PASSED
  Recorded the machine, the displays and the driver state. No user name, file path under the home folder, or serial number is recorded.
  Pass criteria: Information only. It passes when the operating system version can be read.
  - WORSHIPFLOW: 0.0.1 (build 1)
  - macOS: 27.2 (26B123)
  - Mac model: Mac16,10
  - Chip: Apple M4
  - Memory: 16 GB
  - Processor cores: 10
  (7 more measurements are in report.json)

2. Devices: PASSED
  Found 1 device: Simulated SDI Duo 2 card (4 connectors, profiles).
  Pass criteria: At least one connected device is reported. Everything the device says about itself is recorded below.
```

`--inject-fault swapped-connectors`: headline `SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware....`; failing steps: 4. Loopback                       FAILED; 5. Fill and key loopback          FAILED; 7. Four outputs at once           FAILED; 8. Unplug and replug              SKIPPED; 9. Human checks                   SKIPPED. Step 7 says the cable from SDI 1 carried the picture sent on SDI 2 and the cable from SDI 2 the picture sent on SDI 1; step 4 has no signal on SDI 3 and step 5 reads reversed (the swapped outputs also swap the pair's two pictures).

`--inject-fault profile-not-restored`: headline `SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware. THE CARD'S PROFILE WAS NOT RESTORED after the fill and key step (it failed), so step 6 and the steps after it ran in the keying profile.`; steps with "Run in the keying profile": 6 (PASSED, connectors chosen from the keying layout), 7 SKIPPED ("only SDI 2, 3, 4 can send output"), 8 and 9 SKIPPED (not selected).

`--inject-fault crossed-cables`: headline `SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware....`; failing step: 5 Fill and key loopback FAILED: "fill and key are reversed compared with what the device reports (with the cables as instructed ...). The second run, after the tester confirmed the cables, gave the same answer as the first." with "First run: ..." measurements and the finding "Two cables swapped would look the same."

The full text of each is in `AI/reports/fixd-evidence/summaries/`.

## Files

Created: `Sources/OutputEngine/HardwareTest/HardwareTestLayout.swift`, `HardwareTestSimulation.swift`, `HardwareTestUnfinished.swift`; 12 `FIXD_*` test files; `AI/reports/fixd-evidence/`; this report.
Changed: `Sources/OutputEngine/HardwareTest/` (Models, Support, Runner, Steps, VideoSteps, Summary, Bundle, Controller, Launch); `Sources/OperatorCore/` (KeyRouting, MediaModel, WorkspaceModel, +Transport, +Playlists, +Library, +Editing, +Countdowns); `App/Sources/` (AppModel, HardwareTestSupport, HardwareTestView); `docs/hardware-test-guide.md`, `docs/features/HWTEST-001-hardware-test-kit.md`, `docs/hands-on-checklist.md`; the two existing photo fixtures named above. Nothing under `Sources/DeckLinkC`, `DeckLinkSDI`, `SDIEngine` or the other agent's `OutputEngine` files was touched. `Sources/Domain` was not changed. Nothing committed.

## Not verified

- No real card: the profile switch and restore, the Duo 2 layout, the identity loop on a real card, and every step's behaviour on hardware.
- AppKit and SwiftUI glue that no test covers: the key monitor gate in `AppModel.installSystemHooks` (the decision is tested, not that the window title or identifier matches the real SwiftUI window), the alert and notice in `startScreens`, `HardwareTestView` (unfinished banner, Save panel, partial icon, new prompts shown as the default two buttons), `AppHardwareTest.realProvider` (profile capture and restore through the bridge), `AppModel.showChanged` passing Blackout to the media model, and the Desktop folder under the real app. The app was built and run headless only; the Hardware Test window was never opened.
- Photo re-encoding was tested with JPEG; HEIC or very large photos were not.
- The suite was run once in full at the end; the earlier runs of my tests were in a scratch copy without the other agents' unfinished targets (design-token tests read repo-relative files and fail only there).
