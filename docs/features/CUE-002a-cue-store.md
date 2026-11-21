# CUE-002a: storage for macros, slide actions, the schedule and MIDI bindings

Catalogue: AUTO-01 slide actions, AUTO-02 macros, AUTO-03 and AUTO-04 MIDI mapping, AUTO-12 scheduling (storage half). Phase 3. No interface, no app wiring, no timers and no CoreMIDI in this slice.

Verification level: Implemented; Unit Tested (in-memory and temporary-file libraries). Not Simulated in the app, not Hardware Verified, not Live-Service Verified: nothing here has run inside the app, with a real clock, or with a MIDI device.

Code: `Sources/CueStore` (new), `Sources/CueEngine` (versioned shapes), `Sources/Persistence` (migration `v9`, `CueTables.swift`, the reflow hook in `LibraryStore+Structure.swift`). Tests: `Tests/CueStoreTests`, `Tests/CueEngineTests/CUE002a_StoredShapeTests.swift`, `Tests/PersistenceTests/CUE002a_CueSchemaTests.swift`. Tables: `docs/19-data-dictionary.md`, "Schema v9".

## How it is wired

`CueStore(library:now:)` takes the church's `LibraryStore` and reaches the tables through `@_spi(CueStore)` accessors (`cueRead`, `cueWrite`), the same pattern as `ScriptureStore`: one `DatabasePool` per library file, never a second connection. Each operation is one transaction; a validated save reads, checks and writes inside it, so nothing can change in between and a refusal writes nothing. The injected clock is used only to restart events "from now".

## Versions (KI-057)

`Macro`, `ScheduledEvent`, `MIDIBinding`, `MIDIBindingSet`, `SlideActionSet`, `MacroLibrary`, `ScheduleEngine` and the new `ScheduleEngineState` write `"version": 1` (`currentVersion`) and read a missing version as 1, unknown extra keys by ignoring them, and optional fields that older data lacks (`activeFrom`, `isEnabled`, a binding set's list) by default. An action kind this version does not know stays `.unknown` and is written back unchanged. `ScheduleEngine` is now `{version, events, state: {...}}`; the state alone (`ScheduleEngine.state`, `ScheduleEngine(events:state:)`) is what the store keeps in one row. `SlideActionSet(unvalidated:)` and `CueStorage.version(in:)` were added; nothing was removed or renamed.

A row from a **newer** version loads as far as it is understood and is reported, but **saving over it is refused** (`storedByNewerVersion`), because re-encoding it at this version would silently drop fields this build cannot see. The same goes for a row that cannot be decoded (`unreadable`).

## API (`CueStore`)

- **Macros**: `macros()`, `saveMacro` (upsert; the engine's `MacroLibrary.save` decides, so a blank name, a cycle or nesting over 8 is refused with the engine's message; an edit that would put a transport command into a macro that a slide runs is refused too), `renameMacro`, `reorderMacros` (the named ids go first, the rest follow), `references(toMacro:)`, `deleteMacro(id:force:)`.
- **Delete rules**: while another macro, a slide's actions, a scheduled event or a MIDI binding runs the macro, `deleteMacro` deletes nothing and returns `blockedBy`. With `force` it rewrites the referrers in the same transaction and reports `changes`: steps and slide actions that run it are dropped (a slide left with none loses its row); an event whose macro it was has nothing left and is switched off, as is an event whose last action it was (`disabled: true`); a MIDI binding that runs it is deleted. Rows that cannot be read are never rewritten; if their text mentions the macro's id they block a plain delete and are listed in `leftUnreadable` after a forced one.
- **Slide actions**: `slideActions(for:)`, `setSlideActions(_:for:)` (no transport actions, also through nested macros; no unknown macro ids; an empty list removes the row; the slide must exist). They go with the slide, and a reflow keeps them for slides whose words did not change (see the data dictionary).
- **Scheduled events**: `scheduledEvents()`, `saveScheduledEvent` (refuses what the engine's `validationIssues` refuse and unknown macros; a new event, an event switched on, and an event whose time changed restart from now), `setScheduledEvent(id:enabled:)` (the engine's `setEnabled`), `deleteScheduledEvent` (also drops its place in the remembered state), `scheduleState()`, `saveScheduleState(_:)` (one row, one statement, the `lastCheckedAt` column written with it).
- **MIDI**: `midiBindings()`, `saveMIDIBinding` (refuses a pattern no message can match and unknown macros; saves overlapping bindings and **returns** the bindings it overlaps), `deleteMIDIBinding`, `reorderMIDIBindings`.
- **Façade**: `loadLibrary()` returns `CueLibrary { macros, slideActions, schedule, midi, issues }` from one read snapshot. `issues` lists unreadable rows (skipped), newer-version rows (loaded, kept), unknown actions, macro cycles or over-deep nesting found in stored data, and slide actions that now break the transport rule. It repairs nothing.

A library file older than `v9` makes every call throw `libraryNeedsUpdate` instead of failing in SQL.

## Decisions the brief left open

- A binding, event or slide action may not name a macro that is not stored (the engine allows it inside a macro, so macros can be saved in any order; elsewhere it would be a reference nothing could ever fix, and delete blocks on references).
- Events that cannot work are refused at save rather than stored as drafts.
- No `sortOrder` on events (the brief's column list has none): list order is insertion order.
- A forced delete switches an event off rather than deleting it, and deletes a MIDI binding (it has no off switch).
- Timestamps inside JSON are `Date`'s default (seconds since 2001); the `lastCheckedAt` column and the other timestamp columns use GRDB's text form.

## Not verified / known limits

- Never run in the app, with the real clock, a sleep and wake, or a MIDI device.
- `reflowLosses` (the "this will discard notes" preview) does not mention slide actions, because `ReflowLoss` lives in `Domain`; a reflow drops the actions of slides it cannot match silently.
- Two processes opening the same file are not exercised.
- Macro validation sees only readable macros; a cycle through a row that cannot be read is not visible until that row is fixed.
