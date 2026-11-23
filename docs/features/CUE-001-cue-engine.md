# CUE-001: show-control rules (actions, macros, slide actions, schedule, playback markers, MIDI mapping)

Catalogue: AUTO-01 slide actions, AUTO-02 macros, AUTO-03 and AUTO-04 MIDI mapping, AUTO-08 playback markers, AUTO-12 calendar scheduling. Phase 3. This slice is the rules half only: no interface, no CoreMIDI, no persistence, no timers of its own.

Verification level: Implemented; Unit Tested. Not Simulated in the app, not Hardware Verified: no MIDI device, no real clock, no sleep and wake and no running app took part.

Code: `Packages/WorshipFlowKit/Sources/CueEngine` (Foundation and `Domain` only). Tests: `Tests/CueEngineTests`.

## Actions (`CueAction`)

An action is one thing the show can do. Kinds: transport (next, previous, go to slide, clear, clear all, blackout on, off or toggle, stop), select a Look, prop on or off, show a message (id and field values) or hide it, timer start, pause or reset, media (play a clip over the slide, set or clear the background, stop the clip), audio (play or stop a sound), send a MIDI message, run a macro, wait.

Stored form: `CueActionList` is `{"version": 1, "actions": [ ... ]}`. Each action is a flat object with a `kind` such as `transport.next`, `look.select`, `media.setBackground`, `midi.out`, `macro.run`, `wait`. The kinds and fields are fixed by the golden test in `CueActionTests`. An action this version cannot read (a newer kind, a missing or wrong field) becomes `.unknown(raw)`; it is skipped when run, reported ("Unknown action "x" was skipped"), and written back exactly as it was, so saving with an older build loses nothing. A missing `version` counts as 1. Only text that is not JSON at all, or has no `actions` array, throws.

The transport command type is called `CueTransport` (the operator layer already has a `TransportCommand`), and blackout modes `CueBlackout`.

## Macros (`Macro`, `MacroLibrary`)

A macro is a name and ordered steps; steps can run other macros. `save` refuses a blank name, a cycle (message names it: "Macro cycle: A → B → C → A", starting at the macro being saved), and a chain nested more than 8 levels deep ("Macro “M1” would nest 9 levels deep; the limit is 8"; a macro that calls none is 1 level). A failed save changes nothing. A macro may call an id that does not exist; that is reported and skipped when it runs, because macros are saved in any order. Data read from storage can be damaged, so `MacroLibrary(unvalidated:)` plus `issues()` exist, and everything that walks macros (depth, first transport, the executor) is safe against cycles.

## Slide actions (`SlideActionSet`, `SlideLiveEvent`)

Actions are attached to a slide id. They fire when that slide **goes live**: the trigger command; next or previous when the live slide changed (and next taking slide 1 live from stopped); the same slide triggered again fires again. They never fire for load, select, restore, quick edit, clear, clear all or stop, nor for a next or previous that changed nothing (end of the deck). `SlideLiveEvent.detect(command:before:after:)` decides this from a `ShowCommand` and the `ShowState` before and after; the app maps the event's deck index to a slide id (`ShowDeck` has no slide ids).

Transport actions are not allowed in slide actions, nor in a macro (at any depth) that a slide runs. `SlideActionSet.set` rejects them with a message ("A slide action cannot move the show: “Next slide” is not allowed here …", or the macro's name). `problems(library:)` re-checks stored slides after a macro was edited. As a last line of defence the executor also skips transport coming from a slide run.

## Executor (`CueExecutor`, `CueTarget`, `CueClock`)

The app implements `CueTarget` (`beginBatch`, `perform` which may throw, `endBatch`) on the main actor and gives the executor a clock. The executor has no timers: `run` delivers the first stage at once and remembers later stages; the app calls `tick()` at `nextDueTime`.

- **Order within a stage**, whatever the written order: transport, Look, props and messages, media, audio, timers, MIDI out. Actions of the same kind keep their written order. `wait` splits the list into stages in written order. Macros are expanded in place first, so their waits split the trigger's list too.
- **One batch per stage**: `beginBatch`, every action, `endBatch`, so the app can publish one snapshot. A stage with no actions delivers nothing.
- **Stage times** are fixed when the run starts (start plus the waits up to that stage), so a late tick does not push later stages back. A tick after a long sleep delivers every due stage, oldest first, each as its own batch.
- **Failures** never stop the rest. They come back in the `CueReport` as operator text ("Play sound failed: Audio device missing"). Unknown actions, invalid MIDI messages, missing macros, macro cycles and over-deep macros, invalid waits (negative, infinite, not a number: treated as 0) and transport from a slide are skipped and reported the same way.
- **Cancelling**: a slide run first cancels the pending stages of earlier slide runs. A stop action cancels every other run's pending stages (its own later stages stay). `stop()` cancels everything, for when the show stops some other way. Blackout, Clear and every other move cancel nothing. Button, MIDI, schedule and marker runs are not cancelled by a new slide.
- **Re-entrancy**: a `run` made while a batch is being delivered is queued, returns a report with `wasQueued`, and is delivered after the current batch in arrival order; its results appear in the outer call's report.

## Schedule (`ScheduledEvent`, `ScheduleEngine`)

An event is a one-off instant, or a weekly time (weekdays, hour, minute, a named time zone); it has an enabled flag and either actions or a macro id. `due(after:upTo:calendar:)` looks at the window (after, upTo] and returns the events to run, oldest first, and a list of skipped occurrences with plain-text reasons.

- **Sleep or app closed**: an occurrence late by **less than** the grace period (default 300 s) fires once on wake. A later one is skipped and reported ("“Sunday service” (2026-03-08 10:30) was missed by 10 min and was not run."), never fired late in a burst. If a long grace period puts several occurrences of one event in range, only the newest fires and the rest are reported as superseded.
- **Daylight saving**: the wall-clock time is resolved from the zone's offset, not by Foundation's gap rules. A weekly 10:30 is 10:30 local before and after a change. A time inside the spring-forward gap fires at the first valid minute after it (New York 02:30 on 8 March 2026 fires at 03:00; Lord Howe 02:15 fires at 02:30). A time that occurs twice fires once, at its first occurrence. The weekday is the weekday in the event's zone.
- **No double fire**: the engine keeps, per event, the last occurrence fired or reported (`lastHandled`) and the latest check (`lastCheckedAt`); both are `Codable`. Repeated, overlapping and adjacent windows never repeat an occurrence. `poll(now:calendar:)` checks from `lastCheckedAt`, so a relaunch after the app was closed catches up (the first poll only sets the baseline).
- **New and re-enabled events** start at "now" (`activeFrom`, `setEnabled`), so a time earlier today does not fire when an event is created. Disabled events produce nothing, not even skip reports. Invalid events (no weekday, bad hour or zone, no actions, blank name) never fire and are listed by `problems()`.

## Playback markers (`PlaybackMarker`, `MarkerTracker`)

The app calls `start(at:)` when a clip starts, `advance(to:)` for each position the player reports, `pause(at:)` when it stops, and `seek(to:)` when the operator jumps. A marker is reached half a frame early (59.94 fps by default), so it fires on the frame nearest its time and, with one report per frame, within one frame of it. A step of any size forward counts as playing, so a jump must go through `seek`. A seek forward fires nothing and leaves the markers it jumped over quiet; a seek back arms the markers after the new position; landing on a marker counts as being past it. Pausing exactly on a marker fires it once; resuming does not fire it again. A looping clip with a known duration fires every marker on every pass, including markers the last report of the pass did not reach (a drop of at least half the duration is a wrap). A step back of less than a frame is jitter and ignored; a bigger one without a loop is treated as a seek back. Markers beyond the duration never fire. `replaceMarkers` swaps the list during playback without re-firing the ones that already fired.

## MIDI (`MIDIMessage`, `MIDIParser`, `MIDIBindingSet`)

- **Messages**: note on, note off, control change, program change; channel 1 to 16, data 0 to 127. Out-of-range values report `isValid == false` and never become bytes. `encode(_:runningStatus:)` can leave out repeated status bytes.
- **Parsing** (`MIDIParser`, fed byte by byte or packet by packet): running status is kept between calls and cancelled by system messages; a note on with velocity 0 is a note off; real-time bytes anywhere are ignored without disturbing a message in progress; system exclusive is skipped; aftertouch, pitch bend and system common messages are consumed whole and give nothing; stray data bytes and half messages cut short by a new status are dropped and counted in `ignoredByteCount`. It never traps and never returns an invalid message (all 65,536 two-byte inputs and a long random stream are tested).
- **Bindings**: `MIDIPattern` (kind note on, control change or program change; channel and number or "any"; optional value range) maps to a `MIDICommand` (a `CueTransport` or a macro id). `MIDIBindingSet.command(for:)` uses the first matching binding in list order. A note-off never matches. `MIDILearner` turns the next usable message (not a release, not velocity 0) into a pattern with exact channel and number and any value. `conflicts()` lists each pair of bindings one message could trigger; `conflicts(with:)` is for the learn screen.
- **Held pads** (`MIDICommandFilter`): a note-on fires once; repeats are held back until the note-off (or velocity 0), and if the note-off is lost the pad works again after 5 s of silence. A control change fires when its value enters the binding's range, not on every value; leaving the range re-arms it, and so does 0.3 s without a message (for controllers that send the same value on each press and nothing on release). A program change fires every time. The rule applies to macros as well as transport.

## Decisions where the brief left room

1. `CueTransport` and `CueBlackout` instead of `TransportCommand`: `OperatorCore` already exports that name.
2. Transport actions rank first in a stage (the brief's order does not place them).
3. `CueAction.unknown` carries the raw JSON, not a string, so it round-trips.
4. `CueExecutor` is `@MainActor` and has no timers; `tick()` and `nextDueTime` drive waits. The target is begin / perform / end with a throwing `perform`, so the executor itself guarantees "one failure never stops the rest".
5. "A new slide trigger cancels the previous trigger's waits" means earlier slide-origin runs only; Stop cancels every other run. Blackout and Clear cancel nothing.
6. Stages after a wait are timed from the start of the run, not from when the previous stage ran.
7. Macro depth counts macro levels (a macro calling none is depth 1; limit 8).
8. A macro with a transport step may be saved anywhere; the rule is applied where a slide uses it (at save and again at run).
9. `SlideLiveEvent` identifies a slide by (presentation id, deck index) because `ShowDeck` has no slide ids; "Clear lifts" has no separate command in `ShowState` today, so every lift is a trigger, next or previous and is judged as one.
10. Schedule occurrences have minute resolution; the window is (after, upTo]; grace is "less than" the period; an event's `activeFrom` and `setEnabled` stop old times firing on creation.
11. Fall-back time that occurs twice fires at the first occurrence; a time in a gap fires at the instant the gap ends.
12. Marker tolerance is half a frame early, nothing late; `seek` is explicit; a backward step is jitter below one frame and a seek above it.
13. The held-pad rule also covers macros, and control changes use range entry plus a 0.3 s repeat window, notes use release plus a 5 s stale limit.
14. Applying the rules to CoreMIDI is left to the interface slice: the parser takes classic MIDI 1.0 bytes, not Universal MIDI Packets.

## Known limits

- Nothing here talks to hardware, CoreMIDI, the app or a real clock. `SystemCueClock` uses `CLOCK_MONOTONIC`, which should keep counting during sleep; that was not verified by sleeping a Mac.
- The schedule tests rely on the installed time zone data for 2026; a Mac with older data could disagree about a rule change.
- Event and binding stored forms other than `CueActionList`, `MacroLibrary` and `SlideActionSet` use Swift's default `Codable` shapes and have no version field yet.

## UI-007d additions (playback markers)

- `CommandSource.marker` and `OperatorCommand.markerReached`: a marker's actions run through the one command path and show in Activity with source "marker".
- Marker observer rule: runs only while a clip with markers plays live (50 ms interval); never from the preview; never when seeking over a marker.
- No-transport rule: transport actions (for example "Next slide") are refused as a marker's action, with the reason shown.
