# Brief: CUE-002a — storage for macros, slide actions, the schedule and MIDI bindings

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/16-known-issues.md` (KI-057, KI-058), `AI/reports/CUE-001-report.md`, `docs/features/CUE-001-cue-engine.md`, all of `Sources/CueEngine`, `Sources/Persistence` (how `LibraryStore`, the migrator and the `@_spi(ScriptureStore)` accessors in `ScriptureTables.swift` work), and `Sources/ScriptureStore` as the pattern to follow.

Catalogue: AUTO-01 slide actions, AUTO-02 macros, AUTO-03 and AUTO-04 MIDI mapping, AUTO-12 scheduling (storage half). Phase 3. No interface and no app wiring in this slice.

## Rules

Test first for every decision: failing test, recorded output, then implement. One `DatabasePool` per library file (ADR-0004 decision 2): `CueStore` goes through `LibraryStore`, never its own connection. Never edit earlier migrations.

## What to build

1. **Stored shapes get versions** (KI-057): `ScheduleEngine` state, `ScheduledEvent`, `MIDIBindingSet`, `Macro` and `SlideActionSet` must each encode with a version field and decode older or newer unknown fields tolerantly, like `CueAction` already does. Make that change in `Sources/CueEngine` (you own it this round), source-compatibly, with round-trip and forward-compatibility tests.
2. **Migration** (the next free number after the latest in `Sources/Persistence/Schema.swift`): tables `cueMacro` (id, name, definition JSON, sortOrder, timestamps), `cueSlideActions` (slideID primary key referencing `slide` with cascade delete, definition JSON, timestamps), `cueScheduledEvent` (id, name, enabled, definition JSON, timestamps), `cueScheduleState` (a single row: the engine's fired-occurrence state JSON and `lastCheckedAt`), `cueMIDIBinding` (id, definition JSON, sortOrder). Expose the minimal SPI accessor from `Persistence` (`@_spi(CueStore)`, same pattern as the scripture one). A migration test that rows written at the previous version survive, using `prefix(n)`.
3. **`CueStore`** (new target; replace the placeholder): async, `Sendable` API.
   - Macros: list in order, save (upsert; validation through `MacroLibrary` so a cycle or depth violation is rejected with the engine's message and nothing is written), rename, reorder, delete (a macro still referenced by another macro, a slide's actions, a scheduled event or a MIDI binding cannot be deleted silently: return the list of referrers; delete with `force` removes the references and reports what changed).
   - Slide actions: get and set for a slide id (validation: no transport actions, including through nested macros, per the engine rule); they are removed when the slide is deleted (cascade) and **preserved across reflow** for slides whose words are unchanged (read how `replaceContent` carries notes and objects over and hook into the same matching, in `Persistence`, with a test).
   - Scheduled events: list, save, enable or disable (using the engine's rule that old occurrences do not fire when an event is switched on), delete; load and save the engine state atomically with `lastCheckedAt`.
   - MIDI bindings: list, save, delete, with the engine's conflict detection run at save and conflicts returned to the caller.
   - A `CueLibrary` façade the app will use later: load everything into the `CueEngine` types (`MacroLibrary`, `ScheduleEngine`, `MIDIBindingSet`, slide actions lookup) in one read, and report anything that could not be decoded (unknown versions, unknown action kinds) without failing the whole load.
4. **Docs**: `docs/features/CUE-002a-cue-store.md`; add the new tables to `docs/19-data-dictionary.md`.

## Do not modify

Coordinator-owned tests. `Package.swift` (targets are declared), `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, earlier migrations. Two other agents are working right now: one in `Sources/DeckLinkC`, `Sources/DeckLinkSDI`, `Sources/SDIEngine` and parts of `Sources/OutputEngine`; one in `Sources/OutputEngine/HardwareTest`, `App/`, `Sources/OperatorCore`, `Sources/Domain`. Touch none of that. You own `Sources/CueStore`, `Sources/CueEngine`, `Tests/CueStoreTests`, new files in `Tests/CueEngineTests` and `Tests/PersistenceTests`, source-compatible additions to `Sources/Persistence`, and the two docs. `swift test` compiles every target; if a run fails solely because of the other agents' unfinished files, build your own targets, run your tests in a uniquely named scratch copy outside the repository (`wf-cue002a-<random>`; never reuse a directory or script you find), and retry the real run before finishing.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool. Do not download anything.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'CueStoreTests|CueEngineTests|PersistenceTests|SettingsStoreTests|ScriptureStoreTests'` passes in the real package (or you state exactly why it could not and give the scratch result). Paste the summary line.
2. `AI/reports/CUE-002a-report.md` records files, decisions, commands run with exit status, and everything not verified.
