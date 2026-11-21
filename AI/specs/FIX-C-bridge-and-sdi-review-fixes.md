# Brief: FIX-C — second-review fixes in the DeckLink bridge, SDI engine and SDI outputs

Read first: `CLAUDE.md`, `AGENTS.md`, `AI/reports/REVIEW-2-findings.md` (findings marked FIX-C: S8, S9, S10, S11, S12, S13, S16, and the coordinator decisions), `AI/reports/HW-003-report.md`, `AI/reports/HW-004-report.md`, then the code they name and the SDK header `Sources/DeckLinkC/sdk/DeckLinkAPI.h` for every call you touch.

This Mac has no DeckLink card and no driver. Nothing becomes Hardware Verified. The bridge code cannot be run here, so correctness comes from matching the header exactly and from tests through a seam.

## Rules

- Test first for every finding that can be tested: failing test, recorded output, fix, pass. For the Objective-C++ bridge, where no fake SDK exists, add the smallest seam that buys a real test (for example extracting the decision "what to do after each failed step of the restart sequence" into a pure function, or a tiny fake `IDeckLinkInput`/`IDeckLinkOutput` used only by tests) and say plainly what remains untested.
- If, after reading the code and the header, you conclude a finding is wrong, do not "fix" it: say why with evidence.
- Another agent is fixing the hardware test kit, the app and the operator core at the same time: do not touch `Sources/OutputEngine/HardwareTest/`, `App/`, `Sources/OperatorCore` or their tests. You own `Sources/DeckLinkC` (never the vendor files in `sdk/`), `Sources/DeckLinkSDI`, `Sources/SDIEngine`, and in `Sources/OutputEngine` only `SDIOutput.swift`, `OutputCoordinator.swift`, `OutputPlanner.swift`, `SDIEnvironment.swift` and new files; plus new test files in `DeckLinkSDITests`, `SDIEngineTests`, `OutputEngineTests`. Keep every public API source-compatible for the other agent.

## What "fixed" means

- **S8:** no SDK stop, disable or close call is ever made from inside an SDK callback thread. A failure or removal detected in a callback marks the session and hops to the output's own serial queue to finish. Test with the simulator calling back on its callback thread: a schedule failure inside a completion, and an unplug, both finish off the callback thread and never deadlock (use a watchdog in the test).
- **S9:** `SDIOutput` renders ahead on its own thread into a bounded queue (two or three frames) at the device's pace; the completion callback only dequeues a finished frame and schedules it, repeating the last frame and counting a repeat when the queue is empty. No GPU wait, readback or large copy on the callback thread. Buffers are reused. Keep the existing statistics and health semantics. Tests: the callback path does no rendering (inject a renderer that records its calling thread); a slow renderer causes repeats, not late frames; a 600-frame run still has zero late and zero dropped; four outputs share nothing mutable. Re-run the four-output benchmark and report before and after.
- **S10:** every `HRESULT` in the input format-change restart is checked; on failure the input reports through its failure handler with a specific reason, does not report the new mode, and ends in a clean stopped state. If the detected format cannot be captured as BGRA directly, enable in a format the header says is supported and convert, or fail with a clear reason.
- **S11:** `SetLevel` failure is reported (keying is not considered enabled); the scheduler preroll is `max(3, device minimum)` with the device value passed through from the bridge.
- **S12:** `close()` always removes the callback and breaks the cycle, whether or not the input was running, including after removal.
- **S13:** nothing is enumerated or rebuilt inside the profile callback; it records the event and does the refresh on a queue afterwards.
- **S16:** a running output whose planned assignment changes is never stopped silently: it is faulted with an operator-readable reason, or restarted on the new assignment if that is what the operator's configuration now means, and the change is reported. The fill and key source must not flip because a device momentarily has no members during a profile change: hold the last known model and layout across the change. Tests with the simulator and fake displays.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps in the live path, no exceptions crossing the Objective-C boundary, bounded queues. Do not commit or change git state. Do not consult any advisor tool. Do not download or install anything. Do not request full computer control. Use your own uniquely named scratch directory.

## Done means

1. `./scripts/check.sh` exits 0 (or you state exactly which step failed solely because of the other agent's unfinished work, with the filtered run of your own targets passing).
2. `AI/reports/FIX-C-report.md` has one section per finding: the failing test and its pre-fix output (or why no test was possible), the fix, the passing output, what is still unverified; plus the benchmark numbers before and after S9.
