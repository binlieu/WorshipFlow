# Brief: FIX-B — review fixes in the operator core, app, domain and storage

Read first: `CLAUDE.md`, `AGENTS.md`, `AI/reports/REVIEW-phase1-findings.md` (findings marked FIX-B: R1, R3, R4 menus and quit, R6, R8, R11, R12, R13, R14 `Thumbnails` part, R15, R17, and the coordinator decisions at the end), then the code they name.

## Rules for this slice

- **Test first, every finding.** For each one: write a test that fails because of the defect, run it, record the failing output, then fix, then record the pass. Put decisions in `OperatorCore` or `Domain` so they can be tested; where a finding is in AppKit glue that cannot be unit tested, extract the decision into a pure function and test that, and say plainly what remains untested.
- If, after reading the code, you conclude a finding is wrong, do not "fix" it: say why with evidence.
- Another agent is changing `Sources/RenderEngine`, `Sources/OutputEngine` and `Sources/MediaEngine` at the same time, source-compatibly. Use those modules only through today's API. You own `App/Sources`, `Sources/OperatorCore`, `Sources/Domain`, `Sources/Persistence` (no new migration should be needed; if one is, name it `v6` and never edit earlier ones) and new test files in their test targets. Do not edit coordinator-owned tests; if a fix genuinely contradicts one, stop and report.

## What "fixed" means

- **R1:** a repeated key event never triggers a transport command. `KeyRouting.decision` takes an `isRepeat` input and returns "ignore" for transport keys when it is true; the monitor passes `event.isARepeat`. Also make transport commands serial: a second Next arriving while one is still being processed is queued or dropped, never interleaved. Tests for both.
- **R3:** a failed draft write is retried (rescheduled with back-off, and attempted again by `flush()`), the operator sees a persistent "not saved" indicator with the reason until it succeeds, and `pendingDrafts` is never cleared without a successful write — closing or deleting the presentation first attempts the write, and if the row is gone the draft is dropped knowingly, not by blanket clearing. Tests with an injected failing store or writer.
- **R4:** closing the operator window does not quit while screens are open (it asks, or is refused with a message); Quit asks for confirmation while screens are open and flushes everything first; Command-W and Command-H cannot take the outputs down. The decision ("may the app quit now, and what must it ask?") is a tested pure function.
- **R6:** no file-system call on the main thread on a timer. Image availability is checked off the main actor, only for images in use, and results are delivered back.
- **R8:** add `ShowCommand.clearAll` (or an equivalent model command) per the coordinator decision: Clear keeps its meaning; Clear all also stops the foreground clip. Shift-Escape and a button. Update `docs/features/OUT-002-screens-and-live-control.md` to state both rules. Existing coordinator tests for Clear must pass unchanged.
- **R11:** before a reflow is saved, the model reports which section orders and playlist items would lose sections or become empty, and the sheet shows it; an empty playlist item is shown as empty in the playlist and Next stops on it with a message rather than skipping silently. Tests.
- **R12:** `SettingsModel` and `MediaModel` get `flush()`; quit and resign-active await all four models; failed settings writes are retried like R3.
- **R13:** per the coordinator decision: the live presentation's theme is captured at trigger time; `setTheme` on the live presentation changes preview at once and live from the next trigger. Test. Record KI-027 as unchanged.
- **R14:** periodic `CVMetalTextureCacheFlush` in `PreviewRenderer`.
- **R15:** typing does not republish live scenes when nothing live changed, and thumbnails recompute only for the edited slide, debounced. Add a test that an edit to a non-live slide produces no live scene publication, and measure before and after on a 200-slide deck if you can.
- **R17:** Close screens stops the foreground clip and its audio. Test at model level.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not request full computer control. If you launch the app to look at something, use a temporary `--library`, keep it under a minute, never cover a display, play no sound, and leave nothing behind in the home folder.

## Done means

1. `./scripts/check.sh` exits 0 (or you state exactly which step failed solely because of the other agent's unfinished work, with the filtered run of your own targets passing).
2. `AI/reports/FIX-B-report.md` has one section per finding: the failing test and its pre-fix output, the fix, the passing output, and what is still unverified.
