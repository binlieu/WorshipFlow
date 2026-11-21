# Brief: CUE-001 — show-control rules: actions, macros, slide actions, schedule, playback markers, MIDI mapping

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/MASTER-SPEC.md` section 3.4 (AUTO-01 to AUTO-14) and NFR-09, `docs/adr/0007-ui-design-adoption.md` (the four distinct actions: Clear, Clear all, Blackout, Stop), `Sources/Domain/ShowState.swift`, `ShowTimer.swift`, `MediaLayers.swift`, `Look.swift`.

Catalogue (rules half only; interface and device I/O come later): AUTO-01 slide actions, AUTO-02 macros, AUTO-03 and AUTO-04 MIDI mapping, AUTO-08 playback markers, AUTO-12 calendar scheduling. Phase 3.

## Scope

A new pure-Swift target `Sources/CueEngine` (Foundation and `Domain` only; no AppKit, CoreMIDI, AVFoundation). Delete both placeholders. No app, no persistence, no device I/O in this slice. Test first for every rule: write the failing test, record its output, then implement.

## What to build

1. **`CueAction`** (`Codable`, `Sendable`, `Equatable`, stable JSON with a version field so stored cues survive later additions; unknown action kinds decode to `.unknown(raw)` and are skipped with a report, never a crash):
   transport (next, previous, go to slide index, clear, clear all, blackout on or off or toggle, stop); Look (select by id); prop on or off by id; message show (id plus field values) or hide; timer start, pause, reset by id; media (play in foreground by asset id, set background, stop foreground); audio cue play or stop by asset id; MIDI out (a `MIDIMessage`); run macro by id; wait (seconds).
2. **`Macro`** (`id`, `name`, ordered steps) and a **`MacroLibrary`** with validation at save: a macro may call other macros; cycles are rejected with a message naming the cycle; depth limit 8; a missing macro id is reported at run time and skipped.
3. **`SlideActionSet`**: actions attached to a slide id, fired when that slide goes live (not on preview, not on quick edit, not when Clear lifts; fired again if the same slide is re-triggered). Transport actions are **not allowed** in slide actions or in macros run from slide actions (a slide must not be able to advance itself into a loop); validation rejects them with a clear message.
4. **`CueExecutor`**: runs a list of actions against a `CueTarget` protocol (the app will implement it; tests use a recording fake) with an injected clock.
   - Defined order within one trigger, regardless of the order written: Look, then props and messages, then media, then audio, then timers, then MIDI out; `wait` splits the list into stages that keep their written order.
   - One failing action never stops the rest; failures are collected into a result with operator-readable text.
   - A new slide trigger or Stop cancels pending waited stages from the previous trigger; Blackout and Clear do not.
   - Every action the same trigger produces is delivered in one batch per stage so the app can publish one snapshot (NFR-04).
   - Re-entrancy: actions arriving while a batch runs are queued, not interleaved.
5. **Schedule (AUTO-12)**: `ScheduledEvent` (one-off at a date, or weekly on chosen weekdays at a wall-clock time in a named time zone; enabled flag; actions or a macro id). `ScheduleEngine.due(after:upTo:calendar:)` returns events to fire between two instants in order.
   - After the Mac sleeps or the app was closed, an event missed by less than a grace period (default five minutes) fires once on wake; older ones are skipped and reported, never fired late in a burst.
   - Daylight-saving changes: a weekly 10:30 event fires at 10:30 local time before and after the change; a time that does not exist on the spring-forward day fires at the next valid minute; a time that occurs twice on the fall-back day fires once.
   - Never fires the same occurrence twice across repeated calls with overlapping windows (the engine keeps the last fired occurrence per event; make that state `Codable`).
6. **Playback markers (AUTO-08)**: `PlaybackMarker` (time in the clip, actions). `MarkerTracker` is fed transport positions and returns markers to fire: fires when normal playback crosses a marker (within one frame at 59.94); a seek forward does not fire the markers jumped over; a seek backward re-arms markers after the new position; a looping clip fires on every pass; pausing exactly on a marker fires it once.
7. **MIDI mapping (AUTO-03, AUTO-04)**: `MIDIMessage` (note on, note off, control change, program change; channel 1 to 16) with encode to and decode from raw bytes including running status and note-on with velocity zero as note-off; malformed bytes are ignored safely. `MIDIBinding` (a message pattern with optional value range → a command: any transport command or a macro id), `MIDIBindingSet.command(for:)`, a "learn" helper that turns the next received message into a pattern, conflict detection (two bindings for one message), and a rule that note-off and repeated control values do not re-trigger a transport command (a held pad must advance once: same spirit as the key-repeat fix).
8. **Docs**: `docs/features/CUE-001-cue-engine.md` describing each rule above in plain language with the decisions you made where the brief left room.

## Do not modify

Anything outside `Sources/CueEngine`, `Tests/CueEngineTests` and the one feature doc: another agent is working in the SDI engine, output engine, operator core and app. Do not edit `Package.swift`. `swift test` compiles every target; if a run fails solely because of the other agent's unfinished files, build with `swift build --package-path Packages/WorshipFlowKit --target CueEngine` and run your tests in a uniquely named scratch copy of the package outside the repository (`wf-cue001-<random>`), then retry the real run before finishing.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not download anything.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter CueEngineTests` passes in the real package (or you state exactly why it could not run there and give the scratch result). Paste the summary line.
2. `AI/reports/CUE-001-report.md` records files, decisions, commands run with exit status, and everything not verified.
