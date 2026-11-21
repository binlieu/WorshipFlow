# Brief: FIX-D — second-review fixes in the hardware test kit, the app and the operator core

Read first: `CLAUDE.md`, `AGENTS.md`, `AI/reports/REVIEW-2-findings.md` (findings marked FIX-D: S1, S2, S3, S4, S5, S6, S7, S14, S15, and the coordinator decisions), `AI/reports/HWTEST-001-report.md`, `AI/reports/HW-004-report.md`, `docs/hardware-test-guide.md`, then the code they name.

The hardware test kit will be run by a non-expert on a Mac with a real card, and its report is the only evidence the developers receive. Its first duty is never to say something untrue.

## Rules

- Test first for every finding: failing test, recorded output, fix, pass. Decisions live in `OutputEngine/HardwareTest`, `OperatorCore` or `Domain` so they can be tested with the simulator and fakes; where a fix is in AppKit glue, extract the decision into a pure function and test that, and say what remains untested.
- If, after reading the code, you conclude a finding is wrong, do not "fix" it: say why with evidence.
- Another agent is fixing the bridge, the SDI engine and the SDI output at the same time: do not touch `Sources/DeckLinkC`, `Sources/DeckLinkSDI`, `Sources/SDIEngine`, or in `Sources/OutputEngine` the files `SDIOutput.swift`, `OutputCoordinator.swift`, `OutputPlanner.swift`, `SDIEnvironment.swift`. Use their existing public API only. You own `Sources/OutputEngine/HardwareTest/`, `App/Sources`, `Sources/OperatorCore`, `Sources/Domain`, new test files in their test targets, and `docs/hardware-test-guide.md`, `docs/features/HWTEST-001-hardware-test-kit.md`, `docs/hands-on-checklist.md`.

## What "fixed" means

- **S1:** the kit records the device's profile and connector layout before any step, restores the profile after the fill and key step without asking (restoring is always wanted), verifies the restore, and picks the connectors for every step from the device's **current** layout, never from fixed numbers. If a restore fails or cannot be verified, the report's headline says so and the later steps are labelled as run in the keying profile, with their expectations adjusted to that layout so no false "not supported" is reported. Simulator support for profiles with different connector capabilities is needed to test this: add it to the kit's own test doubles (not to `SDIEngine`), covering "profile changes both pairs" and "profile changes one pair".
- **S2:** Go Live always acts on what the operator last chose. Selecting a slide after selecting a countdown (or any non-presentation item) makes the slide the target; the live source is recorded against the item the slide belongs to. Tests for the sequences in the finding, and for Next and Previous after each.
- **S3:** a step is PASSED only if everything it claims was measured. Skipping the replug prompt yields a result that says unplug was measured and replug was not (`needsHuman` or a split result), never PASSED. Audit every step for the same pattern and list what you checked.
- **S4:** per the coordinator decision: each output's pattern encodes its connector number; the kit loops back all four outputs in turn with clear cable prompts (and a skip); "Four outputs at once" is PASSED only for connectors whose identity was seen on an input, and says "ran, identity not checked" for the rest. Simulator fault to test it: two connectors swapped.
- **S5:** per the coordinator decision: a short hash in place of the card's persistent id; photos re-encoded without metadata, under neutral names; the engine log never contains a path or file name the tester chose; display and device names are kept (they are needed) but checked against the redaction list. A test that builds a bundle with a photo carrying location metadata and a path on another volume, and asserts neither survives.
- **S6:** per the coordinator decision: partial results are written as the run goes to a visible folder on the Desktop (named with the date and "WORSHIPFLOW-hardware-test-unfinished"), removed after a successful save; if one exists at launch, the Hardware Test window offers "A previous test did not finish. Save its report…", which zips it with a first line saying the run did not finish and which step it stopped in. The guide explains this in two sentences.
- **S7:** the fill and key finding is worded as an observation that depends on the cabling ("with the cables as instructed, fill arrived on …"); if the result is the reverse of the reported route, the kit asks the tester to confirm the cables are as shown and repeats the step once before reporting; the report keeps both runs.
- **S14:** the headline depends on what ran: a diagnostic export with no video step says "DEVICE INFORMATION ONLY: no video test was run".
- **S15:** while the Hardware Test window is the key window, or the app was started with `--hardware-test`, the transport key monitor is not active and the show cannot be triggered by keys; the kit's refusal to run while screens are open is also enforced during a run (screens cannot be opened while a test runs, with a message). Decision function tested.
- **Blackout and clip sound** (coordinator decision): Blackout mutes foreground clip audio while on and restores the previous level when it lifts; tested at model level.
- Update `docs/hardware-test-guide.md` for the new cable steps (S4), the unfinished-run folder (S6) and anything else that changed; keep it one page and plain.

## Seeing it run

Headless runs with the simulator: a clean quick run, and runs with injected faults for swapped connectors, a profile that is not restored, and crossed cables. Include each `summary.txt` in the report. If you launch the app: temporary `--library`, `--silent-audio`, under a minute, never cover a display, write bundles only to your scratch directory (override the Desktop location with a launch argument for tests so nothing is left on the real Desktop), leave nothing in the home folder.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not request full computer control. Do not download or install anything. Use your own uniquely named scratch directory.

## Done means

1. `./scripts/check.sh` exits 0 (or you state exactly which step failed solely because of the other agent's unfinished work, with the filtered run of your own targets passing).
2. `AI/reports/FIX-D-report.md` has one section per finding: the failing test and its pre-fix output, the fix, the passing output, what is still unverified; and the four summaries.
