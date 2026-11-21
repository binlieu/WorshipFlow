# Independent review, second pass — findings

Date: 2026-11-21. Reviewer: Sonnet subagent, read-only, nothing built or run. SDK signatures were checked against `Sources/DeckLinkC/sdk/DeckLinkAPI.h`. Duo 2 layout facts are the repository's reading of the SDK manual, not checked against hardware.

| # | Severity | Finding | Where | Confidence | Owner |
|---|---|---|---|---|---|
| S1 | Critical | The hardware test may switch the card to the full-duplex profile in step 5 and never switch back. In that profile connector 1 cannot output, so steps 6 to 9 report false failures ("1080p59.94 is not supported for output"). | `HardwareTest/HardwareTestSteps.swift`, `HardwareTestVideoSteps.swift`; `DeckLinkSDI/DeckLinkConnectorLayout.swift`, `DeckLinkDevice.swift` | Code path confirmed; layout unverified on hardware | FIX-D |
| S2 | High | Clicking a countdown in the playlist, then a slide of the song still shown, then Go Live, starts the countdown, not the slide. The live position is then recorded against the countdown, so Next steps from the wrong place. | `OperatorCore/WorkspaceModel+Playlists.swift`, `+Transport.swift` | Confirmed | FIX-D |
| S3 | Medium | Skipping the replug prompt makes the unplug step report PASSED without measuring replug. | `HardwareTestVideoSteps.swift` | Confirmed | FIX-D |
| S4 | Medium | "Four outputs at once" passes on completion counts alone; nothing checks that each connector carries its own picture, so a wrong sub-device-to-connector table for connectors 2 or 4 goes unnoticed. | `HardwareTestSteps.swift`, `HardwareTestVideoSteps.swift` | Confirmed | FIX-D |
| S5 | Medium | The bundle can leak personal data: the attached photo's original path or file name is logged, photos are copied with their metadata (location), and the card's persistent id is written. | `HardwareTestRunner.swift`, `HardwareTestBundle.swift` | Log and copy confirmed | FIX-D |
| S6 | Medium | If the app crashes on first contact with the card, the partial results sit in a temporary folder the tester is never told about. | `HardwareTestController.swift`; `docs/hardware-test-guide.md` | Confirmed | FIX-D |
| S7 | Medium | With crossed cables, the fill and key finding states as measured fact that the route is reversed and the app's assumption is wrong. | `HardwareTestVideoSteps.swift` | Confirmed | FIX-D |
| S8 | Medium | `StopScheduledPlayback` and `DisableVideoOutput` can be called from inside SDK callback threads (a schedule failure in the completion callback; device removal). If the SDK waits for callbacks to return, this hangs. | `SDIEngine/SDIOutputSession.swift`; `DeckLinkSDI/DeckLinkOutputPort.swift`, `DeckLinkDeviceProvider.swift`; `DeckLinkBridge.mm` | Sequence confirmed; SDK behaviour unknown | FIX-C |
| S9 | Medium | Each completion callback renders, waits for the GPU, reads back and copies about 8 MB on the SDK's thread. Four outputs on shared callback threads could exceed the frame period. | `OutputEngine/SDIOutput.swift`; `SDIOutputSession.swift` | Plausible | FIX-C |
| S10 | Medium | The input format-change restart ignores failures of pause, enable, flush and start, and still reports the new mode. | `DeckLinkBridge.mm` | Confirmed against the header | FIX-C |
| S11 | Medium | `keyer->SetLevel` result ignored; the device's minimum preroll is read but unused (hard-coded 3). | `DeckLinkBridge.mm`; `OutputEngine/SDIOutput.swift` | Confirmed | FIX-C |
| S12 | Medium | After device removal during capture, `close()` leaves the callback installed and a reference cycle. | `DeckLinkBridge.mm` | Confirmed | FIX-C |
| S13 | Medium | `ProfileActivated` rebuilds device info (enumerating profiles) inside the SDK's profile callback. | `DeckLinkBridge.mm` | Plausible | FIX-C |
| S14 | Medium | A diagnostic export with no video step still gets the headline "REAL DEVICE TESTED … numbers were measured on this card". | `HardwareTestSummary.swift`, `DiagnosticBundle.swift` | Confirmed | FIX-D |
| S15 | Medium | The key monitor stays active with the Hardware Test window: Space, Return, arrows and B are swallowed and drive the hidden show, and could start screens on the card under test. | `App/Sources/AppModel.swift`, `WorshipFlowApp.swift` | Keys confirmed; screens start plausible | FIX-D |
| S16 | Medium | On a display or device change, a running output whose planned destination changed is stopped with no fault, resume or message. A profile change could trigger it by flipping the fill and key source. | `OutputEngine/OutputCoordinator.swift`; `DeckLinkConnectorLayout.swift` | Stop path confirmed; trigger plausible | FIX-C |

## Spot-check of the first review's fixes

R1 (key repeat), R2 (tall text), R3 (failed save) and R9 (clip failure reporting) are in place by reading. Not run by the reviewer. What `reportUnavailable` does to the layer was not traced.

## Reviewed and found sound

Bridge reference counting, callback lifetime, method signatures against the 16.0 header, the enable/preroll/start/stop/disable order, keyer order, BGRA packing and stride; the stop-during-enable race in `SDIOutput`; Blackout in state and composer (nothing reaches audience or broadcast while blacked out; only the documented triggers lift it); migration v8; scripture import as one transaction on the single pool; the import tool (password only in the child's environment, redacted errors, read-only statements, hex-encoded values and keys); cue executor re-entrancy and the schedule's no-double-fire rule; the debug snapshot hook is excluded from Release.

Noted, not a defect: a playing foreground clip keeps its sound during Blackout.

## Not reached

`SimulatedSDIDevice`, `TestPattern`, `FillKeySplitter`, `SDIInput`; `HardwareTestZip`, `LibraryGuard`; `ScriptureStore+Read`; tolerance of pre-v6 and pre-v7 files; SwiftUI detail of the mode views; the signal map drawing; whether the cue engine's Blackout on and off can be honoured by a toggle-only show command.

## Coordinator decisions

- **S1:** the kit records the profile it found, restores it after the fill and key step (asking is not needed for restoring), and chooses connectors for every later step from the device's current layout. If restoring fails, the report says so in its headline and later steps are marked "run in the keying profile".
- **S4:** every output carries a pattern with its connector number encoded; the kit loops back each of the four outputs in turn (the tester moves cables when asked: 1→3 and 2→4, then 3→1 and 4→2), and "four outputs at once" is only PASSED for connectors whose identity was seen.
- **S5:** the card's persistent id is replaced by a short hash; photos are re-encoded without metadata under neutral names; the log never contains a path the tester chose.
- **S6:** partial results are written to a visible folder on the Desktop as the run goes and removed after a successful save; on the next launch the Hardware Test window offers to save an unfinished run's report.
- **S9:** SDI outputs render ahead on their own thread into a small bounded queue; the completion callback only takes a finished frame and schedules it.
- **Blackout and clip sound:** Blackout also mutes foreground clip audio while it is on and restores it when it lifts.
