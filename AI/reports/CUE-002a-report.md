# CUE-002a report: storage for macros, slide actions, the schedule and MIDI bindings

Feature ID CUE-002a (AUTO-01, AUTO-02, AUTO-03, AUTO-04, AUTO-12 storage half). Verification: **Implemented, Unit Tested**. **Simulated, Hardware Verified, Live-Service Verified: Not Verified** (no app wiring, no real clock, no MIDI device).

## Files

Created: `Sources/CueStore/{CueStore,CueStoreTypes,CueStoreCoding,CueStore+Macros,CueStore+SlideActions,CueStore+Schedule,CueStore+MIDI,CueStore+Load}.swift`; `Sources/Persistence/CueTables.swift`; `Tests/CueStoreTests/{CueStoreFixtures,CueStoreMacroTests,CueStoreSlideActionTests,CueStoreScheduleTests,CueStoreMIDIAndLoadTests}.swift`; `Tests/CueEngineTests/CUE002a_StoredShapeTests.swift`; `Tests/PersistenceTests/CUE002a_CueSchemaTests.swift`; `docs/features/CUE-002a-cue-store.md`.
Changed: `Sources/CueEngine/{CueJSON,Macro,SlideActions,MIDIBinding,Schedule}.swift` (source-compatible additions), `Sources/Persistence/Schema.swift` (migration **v9** appended; earlier migrations untouched), `Sources/Persistence/LibraryStore+Structure.swift` (reflow hook), `docs/19-data-dictionary.md`.
Deleted: the two `Placeholder.swift` files (CueStore source and test).
Not touched: `Package.swift`, `project.yml`, git state, the other agents' areas, `docs/16-known-issues.md`, `docs/17-change-log.md`, `docs/14-*`, `docs/15-*` (coordinator: KI-057's "no storage / no version field" half is now done; change-log, status and handoff are not updated by me).

## Decisions (where the brief left room)

1. Per-row JSON is the engine type itself (`Macro`, `ScheduledEvent`, `MIDIBinding`), each with its own `version`; a slide's row holds the existing versioned `CueActionList`; the schedule state row holds the new `ScheduleEngineState` (grace period, last handled, last check). `ScheduleEngine` itself became `{version, events, state}`.
2. Reflow: `replaceContent` deletes and re-creates slides (new ids), so the cascade would erase actions. The hook takes the rows out first and re-inserts them against the new slide ids, in the same transaction. It reuses `Reflow.carryOver` for the matching by passing each old slide's position as its "notes" and reading it back, so there is no second copy of the rule. A mutation (hook removed) fails 9 expectations. `reflowLosses` does not list lost slide actions (`ReflowLoss` is in `Domain`, not mine).
3. A row from a newer version, or one that cannot be decoded, is never overwritten (save, rename, enable, state save all throw); `loadLibrary` still loads newer rows as far as understood and reports them.
4. Binding, event and slide-action references to a macro that does not exist are refused (macro-to-macro stays allowed, per the engine).
5. Editing a macro is refused if it would give a slide-run macro a transport command (the engine's `problems(library:)` before/after).
6. New, switched-on or retimed events restart from now (`activeFrom`), using an injected clock. Invalid events are refused at save.
7. A forced macro delete switches an event off (rather than deleting it) and deletes a MIDI binding; unreadable referrers are matched by id text, block a plain delete and are left alone by a forced one (`leftUnreadable`).
8. No `sortOrder` on events; list order is `rowid`. MIDI overlaps are saved and returned, not refused.
9. `lastHandled` is pruned on event delete and on load, not on `saveScheduleState` (state is stored as given).

## Commands run (exit status)

- Real package, requested filter: `swift test --package-path Packages/WorshipFlowKit --filter 'CueStoreTests|CueEngineTests|PersistenceTests|SettingsStoreTests|ScriptureStoreTests'` exit **1**, compile failure only in `Tests/DeckLinkSDITests/FIXC_BridgeSeamTests.swift` (the other agent's unfinished `DLBFake*`/`DLBTesting` bridge). Not retried successfully by the end.
- Scratch copy (rsync of the package, `.build` excluded, three other-agent test targets removed from the scratch `Package.swift` only: DeckLinkSDITests, OutputEngineTests, SDIEngineTests; under the session scratchpad `wf-cue002a-7Pmrgz`): same filter, exit **0**: `Test run with 447 tests in 59 suites passed after 10.649 seconds`.
- Scratch, full `swift test`: exit 1, `1295 tests in 199 suites ... 5 issues`; the 5 are `DesignTokenParityTests` and `UI002_AppearanceTests`, which read `docs/UI` and `App/` by a path relative to the scratch location (they find nothing outside the repository). None is a cue or persistence test.
- Test-first: the engine and persistence tests were run red first (compile errors for the missing API, recorded in this session). The CueStore tests were written before the target had any code and were first compiled together with the implementation, so I have no separate red run for them; a mutation run (reflow hook removed) showed the reflow tests fail for the right reason, then the hook was restored.

## Not verified

- The requested command in the real package (blocked by another agent's tests, see above).
- The full suite in the real package; app and Xcode builds; the `App/` target against the changed `CueEngine` (no app code uses these types today, by grep).
- Nothing ran in the app, on a real clock, across sleep or wake, or with MIDI; two processes on one file; a very large library (no performance test).
- Whether `CueStoreTests` importing `Domain` transitively (it is not in the target's declared dependencies) will keep working under every build system; it compiles and runs under SwiftPM.
- Date text inside JSON is seconds since 2001; not checked against a human-readable-export requirement.
