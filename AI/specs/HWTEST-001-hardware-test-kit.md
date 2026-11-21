# Brief: HWTEST-001 — hardware test kit and log bundle

Read first: `CLAUDE.md` (verification levels; evidence over claims), `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md`, `docs/MASTER-SPEC.md` section 8.2 (unverified facts UNV-01 to UNV-09), `AI/reports/HW-001-report.md`, `AI/reports/HW-002-report.md`, all of `Sources/SDIEngine`, `Sources/OutputEngine/SDIOutput.swift`, `SDIEnvironment.swift`, `Sources/OperatorCore`, `App/Sources`.

## Purpose

The owner has no DeckLink card. A friend has a DeckLink Duo 2. The friend will be sent a build, run a guided test, and send back one file. From that file alone the coordinator must be able to tell what works on real hardware and what does not. The kit must therefore be usable by someone who has never seen this app, record everything objectively, and never claim success it did not measure.

It is built and tested here against the simulated card. A separate slice (HW-003, in progress in `Sources/DeckLinkC` and `Sources/DeckLinkSDI` — do not touch those) provides the real device provider; the kit must take its devices through the `SDIEngine` protocols so the real provider plugs in without changes to the kit.

## What to build

**`SDIEngine`** (source-compatible additions, test-first):
- An input side for the protocols: `SDIInputPort` (enable capture on a connector, optional mode or auto-detect, a callback delivering `SDIFrame` plus a hardware timestamp or frame number, a "no signal" state, disable) and `SDIDevice.openInput(connector:)`. Keep it minimal and close to what a capture card offers.
- Simulator support: `SimulatedSDIDevice.connect(output:toInput:)` models a BNC cable so an input receives what the output displays, one frame later; an unconnected input reports no signal. Fault injection for tests: drop every Nth frame, swap fill and key, shift by one pixel, wrong mode.
- `TestPattern`: generators for deterministic frames at a given size — colour bars; a frame-counter pattern that encodes the frame index in a block of pixels robustly (large blocks, so it survives YUV conversion and slight level shifts); an alpha ramp and an alpha "window" pattern for keying (opaque box, 50 % box, transparent surround); a single-pixel-wide grid for position checks. Plus decoders: read the frame index back from a captured frame; compare two frames with a tolerance and report max and mean channel error and the first differing pixel.

**`OperatorCore`** — `HardwareTestRunner` (test-first; driven by an injected device provider and clock so every step runs against the simulator in unit tests):
Steps, each producing a structured result (`passed`, `failed`, `skipped`, `needsHuman`) with measurements and a plain-language summary:
1. **Environment:** app version and build, macOS version, Mac model identifier, chip, memory, displays and refresh rates, driver presence and API version, time zone-free timestamps. No user names, no file paths under the home folder, no serial numbers.
2. **Devices:** every device and everything it reports (model, connector count, keying support, profile or duplex state, supported modes per connector, whether it is simulated).
3. **Output run:** a chosen connector at 1080p59.94 showing colour bars and the frame counter for a chosen duration (30 seconds, 10 minutes, 60 minutes), sampling statistics every second: scheduled, completed, late, dropped, repeated, buffered, health. Pass means zero dropped and zero late; anything else is reported with the times they occurred.
4. **Loopback:** output on connector A, input on connector B (the tester connects a cable; the kit tells them which connectors). Measures: signal detected and its mode; frames received over the run; missing, repeated and out-of-order frame indices; delay in frames; pixel error against the sent pattern. Pass thresholds are stated in the result, not hidden.
5. **Fill and key loopback:** keyed output on the first pair, inputs on the other two connectors (two cables). Sends the alpha patterns. Reports which input received the fill and which the key (answering UNV-03), whether the key equals the alpha within tolerance, whether fill is premultiplied or straight as configured, and tries both alpha modes.
6. **Mode sweep:** for each known mode, whether the device says it supports it for output, with and without keying (answering UNV-02), without running video.
7. **Four outputs at once:** all four connectors as independent outputs for a chosen duration, statistics per connector, plus process memory and CPU load sampled every second (evidence for UNV-04).
8. **Unplug and replug** (optional, asked): the tester unplugs the device during an output run; the kit records what the engine reported and whether the app stayed responsive, then what happened on replug.
9. **Human checks** (optional, asked, each with a "skip"): if a monitor or switcher is connected, show a pattern and ask simple questions (Do you see colour bars filling the screen? Are the edges of the white box clean over your camera picture?), record yes, no or skipped, and offer to attach a photo file the tester chooses.
- The runner never stops at the first failure; it runs every step it can and marks dependents as skipped with the reason. Every step has a timeout. A crash in one step must not lose earlier results: write the bundle incrementally.
- `HardwareTestBundle`: a single `.zip` (or a folder zipped at the end) containing `report.json` (versioned schema, every step's structured result and raw samples), `summary.txt` (one page a person can read, starting with a table of steps and outcomes), the engine log for the run, and any attached photos. A function that loads a bundle and renders the summary, so the coordinator can read bundles later; test that a bundle round-trips.
- A clear statement at the top of every summary: which device was tested, whether it was simulated, and "This report describes what was measured on this run. It is not a certification."

**App**:
- A "Hardware Test" window (menu: Help or a Developer menu → "Hardware Test…", and a launch argument `--hardware-test` that opens straight into it) written for a first-time user: what you need (two short BNC cables for full results; one is enough for the basic loopback; none is enough for steps 1, 2, 3, 6, 7), a diagram in words of which connectors to join, a duration picker with "Quick (about 3 minutes)" as default and "Long (about 70 minutes)" as an option, a big Start button, live progress with the current step and a running log, and at the end "Save report…" plus "Show in Finder". The save panel defaults to the Desktop with a file name containing the date and "WORSHIPFLOW-hardware-test".
- If no real device is found: say so plainly, show the driver state and the message from the environment (for example that Blackmagic Desktop Video is not installed), still allow saving a report (it is useful evidence), and offer "Run against the simulated card" clearly labelled as a demonstration that produces a report marked SIMULATED in its file name and first line.
- A headless mode for the coordinator: `--hardware-test --simulated --quick --output <path>` runs without interaction and exits 0 when the bundle was written (regardless of step outcomes), non-zero only if the kit itself failed.
- The test must not disturb a running service: it refuses to start while screens are open, and says why.

**Docs**: `docs/hardware-test-guide.md` — one page for the tester: what to install (Blackmagic Desktop Video from Blackmagic's support site), how to open an app that macOS says is from an unidentified developer, what cables to connect, what to click, and what file to send back. Plain language, numbered steps, no jargon. Also `docs/features/HWTEST-001-hardware-test-kit.md` describing the steps and pass criteria.

## Do not modify

Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, existing migrations. `Sources/DeckLinkC`, `Sources/DeckLinkSDI`, `Tests/DeckLinkSDITests`: another agent is writing the real bridge there. Do not import `DeckLinkSDI` anywhere yet; the coordinator wires the real provider in afterwards. If the package fails to compile solely because of that agent's unfinished files, wait a few minutes and retry.

## Seeing it run

Run the headless mode against the simulator and include the generated `summary.txt` in your report. Launch the app once with `--hardware-test` and a temporary `--library`, save `AI/reports/HWTEST-001-window.png`, describe it, quit. Keep runs under two minutes (use the quick duration), never cover a display, never switch display modes, play no sound (`--silent-audio`), do not request full computer control, leave nothing behind in the home folder (write the test bundle to your scratch directory, not the Desktop).

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, nothing blocking the main thread. Test first for every decision. Do not commit or change git state. Do not consult any advisor tool. Do not download anything. Use your own uniquely named scratch directory.

## Done means

1. `./scripts/check.sh` exits 0 (or you state exactly which step failed solely because of the other agent's unfinished work, with your own targets passing). Paste the test summary line.
2. A simulated quick run produced a bundle; its `summary.txt` is in your report; a run with injected faults (swapped fill and key, dropped frames) produced a summary that reports those faults correctly — include that summary too.
3. The screenshot exists and you have described it.
4. `AI/reports/HWTEST-001-report.md` records what was built, commands run with exit status, and everything not verified — in particular that the kit has only ever seen a simulated card.
