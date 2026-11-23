# REVIEW-5: fifth independent review

Range: `8590d5a..fb41ae2` (code only; `9c57387` after it is a docs commit). It holds SYS-015 (migration v15), FIX-V, FIX-U, UI-007c, UI-007d, UI-007e, UI-007f, UI-008, OUT-002b, OUT-002c, OUT-002d and OUT-002e. Model: Sonnet. Three reviewers in parallel, each with its own part and its own report file; the coordinator merges them into `AI/reports/REVIEW-5.md`.

The reviewer did not write this code and must not trust the reports in `AI/reports/`: a finding counts only when the code was read. The earlier review `AI/reports/REVIEW-4.md` shows the form and depth expected.

## Parts

**Part A, the live output path (OUT-002b, c, d, e).** Files under `Packages/WorshipFlowKit/Sources/OutputEngine`, `RenderEngine` (`ImageWarmer`, `Compositor`, text and image caches), `MediaEngine/LoopingVideoSource.swift`, the soak code in `App/Sources`, and their tests. Look hardest at:
- `MetalOutput` under `CAMetalDisplayLink`: which thread the callback runs on, the link's lifetime (start, stop, invalidate, retain cycles between link, delegate, layer and output), what happens when the window closes, the screen is unplugged, the output is retired (`OutputCoordinator` retiring list from FIX-V M2), the app sleeps and wakes, or the window moves to a display with another refresh rate; whether a drawable can be held or presented twice; `preferredFrameLatency`; whether the two-frames-on-GPU guard still works when the link hands the drawable in.
- `ScenePreparationGate` and `BackgroundScenePreparer`: data races (what is touched from the render thread, the preparing queue and the publisher), ordering (can a newer scene be overtaken by an older one finishing later; can Blackout or Clear ever wait or be skipped; can the gate hold for ever if preparation never completes or throws), bounds on queues and caches, cancellation, and what happens with several outputs sharing caches.
- `FrameEventLog` and `TickTimeline`: anything on the per-frame path that allocates, locks for long or can grow without bound; index arithmetic in the rings; the classification rule against its own text.
- Whether SDI output, the SDI scheduler and Fill/Key behave exactly as before (they were meant to be untouched: confirm from the diff).
- Swift 6 concurrency: every `@unchecked Sendable`, `nonisolated(unsafe)`, unstructured `Task`, and lock, in the changed files: is each justified by the code around it?

**Part B, data and media (SYS-015, UI-007c, UI-007d).** The v15 migration and the backup before it, the repositories and package (export, import, validation) for the new fields, `Domain` types (`SlideObject`, `MediaTransport`, `MediaLayers`), `OperatorCore` marks and markers (`MediaMarkerModel`, `MediaMarkerFeed`, `MediaModel+Marks`), `MediaEngine/UI007c_ObjectVideoPlayers`, and the app views for Layers, video objects, marks and Cues markers. Look hardest at:
- Migration safety: a v14 library with real rows (nulls, legacy values, a large library), a failed or interrupted migration, the backup (when it is taken, what if it fails, does it ever overwrite or delete), opening a newer library in this build and this library in an older build, foreign keys and defaults, the data dictionary agreeing with the schema.
- Package import of hostile or damaged input for the new fields (out-of-range marks, mark in after mark out, negative times, NaN, huge marker lists, a video object pointing outside the package).
- Marks and markers: playback honouring in and out at loop points and when seeking; a marker action running once per crossing (not twice on a loop, on a seek across it, on pause and resume, or on two outputs); marker actions going through the command path with the same rules as an operator command; nothing ticking while idle.
- Video objects: player lifetime and count (bounded, released when the slide leaves Live), Edit showing a poster only, editing never changing Live, hidden and locked honoured everywhere a scene is built (Preview, Live, thumbnails, stage, broadcast).

**Part C, the operator interface and the fixes (FIX-V, FIX-U, UI-007e, UI-007f, UI-008).** Look hardest at:
- Every REVIEW-4 finding (M1 to M5, L1 to L9, and its "tests that do not test" list): read the fix and say fixed, partly fixed or still open, with the line.
- Per-screen Look (UI-007f): which Look a screen shows when the show's Look changes, when a Look is deleted, when a screen is removed and added; can the wrong Look reach a screen; can speaker notes or a stage layout reach an audience or broadcast screen through any new path; signal chain and key note editing (validation, persistence).
- Stage Section and Next section (UI-007e): stage screens only, the right section when the deck has a custom section order, an empty or missing name.
- FIX-U's three split views and UI-008's layout changes: any behaviour change, lost accessibility label, keyboard path or state that no longer updates; anything that now ticks while idle.
- The two merge resolutions in `App/Sources/AppModel.swift` (thumbnail scene) and `App/Sources/SlideObjectsEditor.swift` (preview scene by role): are they right for every role?
- Editing never changes Live; red only for on air; no destructive action without confirmation.

## For every part

- Read the code through git at `fb41ae2` (`git diff 8590d5a..fb41ae2 -- <paths>`, `git show`, `git grep`) and the working tree, which is the same. Read around the diff: a finding is often in the unchanged caller.
- Tests: for each new test file in your part, say whether it would fail if the behaviour it names were broken. List tests that assert nothing real, that test a copy of the logic, or that the brief required and are missing.
- Each finding: severity (high: wrong output on air, data loss, crash, leak of notes to the wrong screen; medium: wrong behaviour an operator would meet; low: the rest), where (file and line), the scenario in plain words, and confidence ("confirmed": path read end to end; "plausible": a timing, platform or input condition not established). No style remarks. Do not pad: "none found" is a valid result.
- End with: areas checked and found sound; what cannot be judged without running the app or without hardware, as a short hands-on script.

## Rules

- Read-only. Do not build, run tests, launch the app or run a soak. Do not edit any file except your own report: `AI/reports/REVIEW-5-part-A.md`, `-part-B.md` or `-part-C.md`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's library or touch `/Applications/WorshipFlow.app`.
- The repository is public: no personal strings (user name, home path, computer name, addresses) in the report.
- Plain language in the report: short sentences, no invented labels; name things as the code names them.
