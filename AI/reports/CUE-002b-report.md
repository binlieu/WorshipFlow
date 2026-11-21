# CUE-002b report: cues, MIDI and remote control wired into the app

Features: AUTO-01, AUTO-02, AUTO-03, AUTO-04, AUTO-10, AUTO-12, AUTO-13. Verification: Implemented; Unit Tested; Simulated (fakes) and run once in the real app through the debug hook (loopback, the app's own virtual MIDI port). Not Hardware Verified (no MIDI device), not Live-Service Verified (no phone).

## Items

1. Done. `CueModel` and one serial command path (`CommandSource`, `OperatorCommand`). `ShowCueTarget` drives the models through small ports (`CueTransportPort`, `CueLookPort`, `CueStagePort`, `CueMediaPort`, `CueMIDIOutPort`); each model conforms to its own.
2. Done. Slide actions run when a slide goes live (hook in `WorkspaceModel.apply`, front of the queue so they run right after the command that caused them). The app ticker drives `tick()` with an injected clock. The re-flow sheet lists actions that will be dropped (`LibraryStore.slideActionLosses`, same matching as `replaceContent`).
3. Done. Poll once a second and on wake; state saved (at once when something fired or was skipped, else every 30 s, and on quit); missed events become notices; nothing fires while the Hardware Test runs (the occurrence is consumed, not postponed).
4. Done. MIDI off by default; devices by stable id; virtual ports toggle; Learn; conflicts shown; lost device shows as offline and reconnects.
5. Done. Remote control off by default; port; pairing code with countdown; addresses; paired devices with Revoke and Revoke all; tokens as salted hashes through `LibraryTokenStore` (migration **v10**, table `remoteToken`); plain-HTTP sentence next to the switch; `stateDidChange()` called from show changes and a 1 s fingerprint check.
6. Done. Cues mode (macros: create, rename, reorder in the model, delete with the referrer warning, step editor with a picker per kind; slide actions; schedule; MIDI; remote; MIDI map, keyboard and activity on the right). Cues tab in Show: macro buttons and the next scheduled event. The "arrives in a later version" notes are gone.
7. Not done, on purpose: playback markers. The media controller has nowhere cheap to host them. Stream Deck and other "later" rows of the design are not drawn (no dead controls). Recorded as KI-087.

## Control table changes

Every transport control (Previous, Go Live, Next, Clear, Clear all, Blackout, Stop; keys; menu; slide double click and Go Live in the slide menu) now goes through `AppModel` into the command path. New controls: Cues mode (all of the above), Cues tab buttons, re-flow warning list. No control removed.

## Tests

Test-first: for items 1 to 4 and 6 the tests were written and seen failing (they did not compile: missing types or members) before the code. For the token table (migration v10) and the token store the tests and code were written together; I did not see those red first.

New files (89 tests): `CUE002b_Fakes`, `_TargetTests`, `_CommandPathTests`, `_PortsTests`, `_SlideActionsTests`, `_ScheduleTests`, `_ScheduleDraftTests`, `_MIDITests`, `_RemoteTests` (real loopback sockets, always stopped), `_EditingTests` in OperatorCoreTests; `CUE002b_SlideActionLossTests` in CueStoreTests; `CUE002b_RemoteTokenTests` in PersistenceTests.

Commands run (all exit 0 unless stated):
- `WF_DERIVED_DATA=<scratch> ./scripts/check.sh`: exit 0; `Test run with 2099 tests in 323 suites passed after 61.849 seconds`.
- `swift test --package-path Packages/WorshipFlowKit` twice more: `2099 tests in 323 suites passed` both times (61.991 s, 62.553 s). Three consecutive passes in all.
- Baseline before my changes: 2010 tests passed.

## Seen in the running app

`UI_SNAPSHOT_CUES=1` with `UI_SNAPSHOT_DIR`, a temporary `--library`, `--silent-audio`, `--remote-loopback-only --remote-port 0`, a copy of the app under a throw-away bundle id, window outputs only. From `ui-snapshots.log`:
- Macro of three steps run (the action behind the Cues tab button, not a mouse click): Look Sermon to Worship, stage message shown, timer running.
- Slide action: selecting slide 4 left the Look alone; going live with it changed the Look to Sermon.
- Scheduled event four seconds ahead ran once ("schedule event Doors open" in the activity list).
- MIDI: note D4 sent from a second CoreMIDI client to the app's virtual port ("WF cue run In") advanced the slide (index 3 to 4); the activity list shows `midi Next slide`.
- Remote: server on an ephemeral loopback port; pair returned 200 with the on-screen code; `next` returned 200 and advanced the slide 3 to 4; then the server was switched off and the port refused connections. MIDI was switched off and the client disposed.
- Afterwards no WORSHIPFLOW process and no listening socket of mine.

Pictures (in this folder): `CUE-002b-cues.png` (Cues mode on the macro), `CUE-002b-show-cues-tab.png` (Show with the Cues tab), plus `-cues-remote.png`, `-cues-midi.png`, `-cues-slide-actions.png`, `-cues-schedule.png`. None shows the Mac's name. The signal-map host name now reads "This Mac" in a snapshot run (KI-085).

## Deviations and limits

- Tab and macro buttons were driven by calling the button's action from the hook, not by a mouse click (KI-086 stays open for clicks).
- Remote and MIDI are brought back at launch only if the operator had turned them on.
- A macro's Next across a playlist item runs its other steps first (KI-087). Goto slide needs the open song to be the live one.
- The "WorshipFlow In/Out" caption in the MIDI section shows the default port names; the run used other names.
- Not verified: sleep and wake on a real Mac, a physical MIDI device, a phone, the control page in a browser, mouse use of the new views, the re-flow warning in the sheet (tested at model and store level only), light theme of the new views, VoiceOver.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` was regenerated by xcodegen (new files). `Package.swift` and `project.yml` changed only as the brief allows. Added a `fetchGroups` visibility change (private to internal) in `LibraryStore+Structure.swift`.
- Owner's library folder: modification times recorded at the start and at the end are identical (folder 1795265545, `Library.sqlite` 1795268503, `-shm` 1795276381, `-wal` 1795276482). I never opened it.
