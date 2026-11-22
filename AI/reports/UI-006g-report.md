# UI-006g report: Cues mode features the design draws and the app lacked

Feature IDs UI-006g, CU-21 (keyboard trigger), CU-22 (dry run), plus the slide-actions-per-presentation known issue of UI-005g. Brief `AI/specs/UI-006-mode-features.md`. Levels: **Implemented** and **Unit Tested** for the model and store logic; the views are **Implemented** and were compiled (Debug and Release) but, with the screen locked, only exercised through the debug capture, not by hand. Nothing is Simulated, Hardware Verified or Live-Service Verified (none touches hardware).

## Ranked list (operator value over size)

| # | Candidate | Operator gain | Needs | Size | Decision |
|---|---|---|---|---|---|
| 1 | CU-21 Keyboard trigger (F1 to F12 runs a macro) | Run a macro from the keyboard without MIDI; the design's "Trigger: F1" | settings store key `cue.macro.keys`, a gate for the key monitor | small | Built |
| 2 | CU-22 Test in Preview | Know what a macro will do before pressing Run | a read of the executor's plan | small | Built as a **dry run** (see below) |
| 3 | Slide actions listed per presentation | See every presentation that has slide actions, open one from the list | one read query | small | Built |
| 4 | CU-33 Playback markers | Cue a macro at a time inside a clip | new stored markers per clip, a player-position feed to `MarkerTracker`, a run path | large, needs a migration | Not built |
| 5 | CU-29 "Stage layout" action | Switch the stage layout from a macro | a new `CueAction` case, a stage port | medium, touches the shared `CueAction` and `CueTarget` types and Stage mode (another agent) | Not built |
| 6 | CU-28 Loop and dissolve in "Start background" | the design's "teal.mov, loop, 1.0 s dissolve" | optional fields in the action JSON plus the output's background path (Media agent's files) | medium | Not built |
| 7 | "CC 7: Media audio level" | a fader on a MIDI knob | a new MIDI command and an audio-level port (Media's files) | medium | Not built |
| 8 | "Learn..." in the MIDI map header | one click to learn a pad | learning needs a chosen command first; the Manage page does it | small, no gain over today | Not built |
| 9 | "Start background" and richer detail wording | wording only | existing tests pin the current wording and may not be edited | tiny | Not built |

## Built

### CU-21 Keyboard trigger
A macro can be given one function key, F1 to F12. The bar's Trigger field is now a menu (No key, F1 to F12, a check mark on the current one; a key another macro holds is listed "F2 - takes it from Sermon mode" and moving it is the whole effect). The field reads the design's "Trigger: F1 . MIDI Note C2" (the key in bold).
- Rules (all in `CueKeyGate` and `CueKeyTriggers`, tested): one key per macro and one macro per key; a bare function key only (no Command, Control, Option or Shift); never a held key (no second run); never while a text field, the search field or a sheet has focus; the key monitor's existing guard (the Hardware Test window and test sessions never drive the show with keys) still comes first. The key goes through `CueModel.submit(.runMacro, from: .key)`, the one command path, so it appears in Activity as "key macro Name", is serialised with every other source and is undone by nothing special. A key with no macro is left to the app.
- The keys are not used by any other key of the show (a test compares with `ShowShortcuts.all`).
- Persisted in the library's app state under `cue.macro.keys` (JSON, versioned); no schema change. A deleted macro's key is dropped on the next reload.
- Where: `Packages/WorshipFlowKit/Sources/OperatorCore/UI006g_CueKeys.swift`; `App/Sources/CuesTrigger.swift`, `App/Sources/CuesKeyTrigger.swift`.
- Tests: `UI006g_KeyTriggerTests.swift` (key codes, labels, no clash, one-key-one-macro, move, clear, prune, stored shape and an unknown key dropped, bar text, the gate in every case, a bound key running its macro through the command path and logging "key", a key with no macro, deleting the macro frees the key, restart keeps the keys). Level: Unit Tested (model); Implemented (monitor hook and menu, not pressed on a real keyboard here).

### CU-22 Dry run (in place of "Test in Preview")
The design's "Test in Preview" cannot be built as drawn: a macro's steps act on the Look, props, timers, the live show and the sound, and Preview has no second copy of any of them, so a run "to Preview" would either change Live or invent a result. What can be told truthfully is built instead and is labelled for what it is: a **Dry run** button in the place of the design's button (same 126.9 pt slot). It opens a popover that lists what Run would do, in the order Run would deliver (a step that moves the show first, then the Look, props and messages, media, sound, timers, MIDI), grouped "Right away" and "After 2 s" at each wait, with each step named as the action list names it, the AUD/STG/BRD tags that step can change, steps that point at something gone marked, and what the engine would skip (a missing or looping macro, an unknown action). It says in words that nothing is sent to any screen; it queues nothing, logs nothing, starts no timer and changes no state.
- It reads the executor's own plan (`CueExecutor.dryRun`, a read of `makePlan`), so it cannot drift from a run; a test runs the same list and compares the counts.
- Where: `Packages/WorshipFlowKit/Sources/CueEngine/UI006g_DryRun.swift`, `.../OperatorCore/UI006g_CueDryRunText.swift`, `App/Sources/CuesDryRun.swift`.
- Tests: `UI006g_DryRunTests.swift` (delivery order, waits split and add up, macro expansion and a missing macro, slide-run skips a transport step, nothing delivered or queued, same plan as a real run) and `UI006g_DryRunTextTests.swift` (order, groups, numbering, screens, broken count, empty macro, missing macro, headline wording). Level: Unit Tested (logic); Implemented (popover).
- If the owner wants a true Preview-only run later, it needs a Preview-side model of Looks, props and timers; that is a separate feature.

### Slide actions, one row per presentation
The left column listed one row (the open presentation); it now lists every presentation that has slide actions with how many of its slides have them (a new read-only query, `CueStore.presentationsWithSlideActions`), sorted by title. The open presentation is always listed and counted live (an edit shows at once). Choosing another presentation's row opens it in **Preview only** (`WorkspaceModel.openPresentation`, never Live) and shows its slide-actions editor.
- Where: `Packages/WorshipFlowKit/Sources/CueStore/UI006g_SlideActionPresentations.swift`; `App/Sources/CuesMode.swift` (sidebar).
- Tests: `UI006g_SlideActionPresentationsTests.swift` (none, counts by title ignoring case, clearing the last action drops the row, deleting the presentation drops the row). Level: Unit Tested (query); Implemented (rows).

## Not built, and why
CU-33 Playback markers (needs stored markers and a clip-position feed: a migration and Media's files), CU-29 Stage layout action and CU-28 loop and dissolve and the CC 7 level (each needs a new case or field in the shared `CueAction`, `CueTarget` or MIDI command types and a port into Stage or Media, which other agents own at the same time), "Learn..." (no gain over the Manage page), and the wording changes (existing tests pin it). Their rooms are unchanged (the 142 pt reserved for markers stays).

## Needs a migration (for the coordinator's one migration brief)
- **Playback markers (CU-33)**: table `cuePlaybackMarker` (`id` TEXT primary key, `assetID` TEXT not null references the media asset, `time` REAL not null, `definition` TEXT not null (versioned JSON `{version, actions}` as the other cue rows), `sortOrder` INTEGER, `createdAt`, `updatedAt`), index on `assetID`. `PlaybackMarker` and `MarkerTracker` exist in CueEngine and are tested; what is missing is the table, the store methods and the clip-position feed.
- Nothing else here needs one (the function keys use the app-state store).

## Shared-file lines
- `App/Sources/AppModel.swift`: one line (commented, UI-006g) in the key monitor, before `KeyRouting.decision`: `if self.handleCueKeyTrigger(...) { return true }`.
- `Packages/WorshipFlowKit/Sources/CueEngine/CueExecutor.swift`: `Plan` and `makePlan` lose `private` (module-internal) so `dryRun` reads the same plan; nothing else changes and no public signature changes.
- `Packages/WorshipFlowKit/Sources/OperatorCore/CueModel.swift`: two additive stored properties (`slideActionPresentations`, `keyTriggers`, both `internal(set)`) and two lines in `reload()` (read the presentations, prune the keys).
- `Packages/WorshipFlowKit/Sources/OperatorCore/CueModel+Settings.swift`: one line in `start()` (`await loadKeyTriggers()`).
- `scripts/design-map-cues.json`: the trigger no longer skips its left edge; `main.test` mapped; the two "left out" ignores for the trigger key and the test button removed.
- `App/Sources/CuesDesignCapture.swift` gives the capture macro the F1 key.

## Change log (for docs/17-change-log.md)
UI-006g: Cues mode: a macro can be run from a function key (F1 to F12) chosen in the bar's Trigger menu (CU-21); a Dry run popover lists what Run would do, in delivery order with the waits and the problems, without touching any screen (CU-22; "Test in Preview" is not built); the left column lists every presentation that has slide actions and opens one in Preview (new read-only `CueStore.presentationsWithSlideActions`). The keys are kept in the app state as `cue.macro.keys`.

## Known issues (for docs/16-known-issues.md, unnumbered)
- Cues: "Test in Preview" is a Dry run (a list); a run that shows its effect in Preview needs a Preview model of Looks, props and timers.
- Cues: a function key works only in the operator window and only when no text field, search field or sheet has focus; on a Mac laptop the key needs fn unless "Use F1, F2, etc. keys as standard function keys" is on. Not tried on a real keyboard.
- Cues: Playback markers (CU-33), "Stage layout" (CU-29), loop and dissolve (CU-28), the CC 7 level and "Learn..." remain open.
- Cues: choosing another presentation's slide-actions row replaces what is open in Preview.

## Hands-on checklist (for docs/hands-on-checklist.md)
- Cues: choose F1 for a macro in the Trigger menu; with focus on the slide grid press F1: the macro runs and Activity says "key macro ...". Focus the search field or a text box and press F1: nothing runs. Hold F1: it runs once.
- Give F1 to a second macro: the first loses it (the menu said so). Delete a macro: its key is free. Quit and reopen: the keys are back.
- Cues: Dry run on a macro with a Wait: groups "Right away" and "After n s" in the order Run uses; Run afterwards does the same. Nothing changes on any screen while the popover is open; Escape closes it; VoiceOver reads each step.
- Cues: a second presentation with slide actions appears in the left column; clicking it opens it in Preview (Live unchanged) and shows its slides.

## Rectangle table
See "Checks": the capture needs a window and the screen was locked, so the table was not re-measured. The mapped controls whose size or place could change are the Trigger field (now a menu, same text style and `wfRect`), the new Dry run button (126.9 pt slot, the design's `btn[4]`) and the sidebar's Slide actions rows (26 pt `CuesListRow`, as before).

## Checks
Filled in below by the last run.
The full `scripts/check.sh` was run as its steps (the machine was at load average 20 to 30, and a single command may not run past 10 minutes), each in the foreground, with `WF_DERIVED_DATA` set to a scratch folder:
- Package tests: `swift test --package-path Packages/WorshipFlowKit`: **3069 tests in 488 suites; 3 issues, all in `MIDIRouterTests`** (`aHeldPadFiresOnceUntilReleased`, `aMissedNotificationIsCoveredByPolling`: timing under load). Re-run alone: `MIDIRouterTests` 17 tests passed. No other test failed. New tests: 6 + 6 + 5 + 13 (UI006g_ suites), about 30 tests in all.
- Domain boundary grep: nothing found (clean).
- `xcodegen generate`, Debug build of the app: exit 0, no errors. Release build (compile only, arm64): exit 0, no errors. The Release binary holds no `UI_SNAPSHOT_(DIR|FIXQ)` strings.
- Not run: `scripts/cues-capture.sh` and `scripts/compare-rects.py` (the capture needs the app's window; the screen was locked), so the rectangle table was not re-measured. `Vendor/DeckLinkSDK/`, `Bibles/`, `TestData/` and `TestMedia/` are absent in a worktree, so tests that need them (if any are skipped by design) did not exercise them. `WORSHIPFLOW.xcodeproj/project.pbxproj` was regenerated by the build and is not committed.

## Not verified
The popover, the trigger menu and the sidebar rows were compiled but not looked at or measured (no capture, no hand test); the function key was not pressed on a real keyboard or with the Mac's "fn" setting; the Dry run was not compared against a real Run in the app (only in the engine tests); opening another presentation from the slide-actions row was not exercised in the app; light and dark appearance of the new views was not seen; VoiceOver reading of the new controls was not tried.
