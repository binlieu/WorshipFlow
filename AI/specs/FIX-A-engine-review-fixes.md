# Brief: FIX-A — review fixes in the render, output and media engines

Read first: `CLAUDE.md`, `AGENTS.md`, `AI/reports/REVIEW-phase1-findings.md` (findings marked FIX-A: R2, R4 `canHide` part, R5, R7, R9 reporting part, R10, R14 `MediaFrames` part, R16, R18), then the code they name.

## Rules for this slice

- **Test first, every finding.** For each one: write a test that fails because of the defect, run it, record the failing output, then fix, then record the pass. Where a finding cannot be unit tested (R5's window behaviour, R16's timing), extract the decision into a pure function and test that, and say plainly what remains untested.
- If, after reading the code, you conclude a finding is wrong, do not "fix" it: say why with evidence.
- Keep every existing public API source-compatible; another agent is changing `App/`, `Sources/OperatorCore`, `Sources/Domain` and `Sources/Persistence` at the same time and calls today's API. You own `Sources/RenderEngine`, `Sources/OutputEngine`, `Sources/MediaEngine` and new test files in their test targets. Do not edit coordinator-owned tests.

## What "fixed" means

- **R2:** no text, shape or image layer can abort a frame. An unrenderable layer is skipped and reported (a per-output list of render problems the operator can see, de-duplicated, cleared when the problem goes away); text taller than the limit is rendered clipped to the limit, never thrown. The rest of the scene always presents. Test: a scene with one impossible layer and one normal layer renders the normal layer.
- **R5:** on a screen-parameters change, an output re-checks that its window still exactly covers its target display and re-sets the frame if not; if the display's size changed, the drawable follows; if the window ended up on a different display than its target, it is moved back or the screen is faulted, never left. Pure decision function tested; the handler calls it.
- **R4 (`canHide`):** output windows are excluded from Hide (`canHide = false`), do not hide on deactivate, and are not closable by Command-W.
- **R7:** no file-system call on a render thread. Modification-date checks move to the background loader; a failed reload keeps the previous texture and reports the problem.
- **R9 (reporting):** `VideoPlayerSource` observes item failure and playback stall that the watchdog cannot recover, and `MediaRegistry` exposes, per asset id, whether it is delivering frames, with a callback or pollable state the app can read from the main actor. Add tests with a deliberately broken file.
- **R10:** a way to pre-decode the images a scene needs before it is presented: for example `Compositor.prepare(scene:)` or an output-level "warm" call that the app can invoke for the preview scene, plus sharing decoded images between screens (one decode per file, not per screen). Test that after warming, the first frame includes the image.
- **R14:** periodic `CVMetalTextureCacheFlush` in `MediaFrameResolver`.
- **R16:** shader compilation happens once and is shared (or is done ahead of time off the main thread), so opening N outputs does not compile N times on the main thread. Show before and after timing for opening four outputs offscreen if you can measure it.
- **R18:** do not hold the lock across AVFoundation calls; copy what is needed under the lock, call outside it.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not open windows for more than a few seconds, never cover a display, never switch display modes, play no sound.

## Done means

1. `./scripts/check.sh` exits 0 (or you state exactly which step failed solely because of the other agent's unfinished work, with the filtered run of your own targets passing).
2. `AI/reports/FIX-A-report.md` has one section per finding: the failing test and its pre-fix output, the fix, the passing output, and what is still unverified.
