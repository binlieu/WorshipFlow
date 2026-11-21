# Brief: CUE-002b — wire cues, MIDI and the remote control into the app; give the Cues mode and Cues tab real content

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0007-ui-design-adoption.md`, `docs/UI/README.md` (sections on Cues and on the Show mode's Cues tab) and the pictures `docs/UI/screens/06-cues.png` and `01-operator-show.png` (look at them), `docs/16-known-issues.md` (KI-057, KI-058, KI-075, KI-080, KI-086), the reports `AI/reports/CUE-001-report.md`, `CUE-002a-report.md`, `CUE-003-report.md`, `CUE-004-report.md`, `UI-003-report.md`, the feature docs `docs/features/CUE-00*.md`, all of `Sources/CueEngine`, `Sources/CueStore`, `Sources/MIDIIO`, `Sources/RemoteControl`, `Sources/OperatorCore`, `App/Sources`.

Catalogue: AUTO-01 slide actions, AUTO-02 macros, AUTO-03 and AUTO-04 MIDI, AUTO-08 playback markers (wiring only if cheap), AUTO-10 remote API, AUTO-12 scheduling, AUTO-13 web control. Phase 3.

## Rules

Test first for every decision; views stay thin (decisions in `OperatorCore`); no dead controls; red only for "on screen now"; nothing that works today may be lost; transport bar and keys work in every mode; never load anything from `docs/UI/mockups`. `Package.swift` may be edited **only** to add `CueEngine`, `CueStore`, `MIDIIO` and `RemoteControl` as dependencies of `OperatorCore` and its tests, and `project.yml` only to link those products into the app.

## What to build

1. **`CueModel`** in `OperatorCore` (`@MainActor @Observable`), loaded from `CueStore` through the existing `LibraryStore`: macros, slide actions for the open presentation, scheduled events, MIDI bindings. It owns one `CueExecutor` whose `CueTarget` is implemented against the existing models (`WorkspaceModel` transport including Clear all and Blackout, `SettingsModel` Looks and props, `StageModel` timers and stage message, `MediaModel` background, foreground and audio cue, MIDI out through `MIDIRouter`). Every command, whatever its source (button, key, slide action, macro, schedule, MIDI, remote), goes through one serial command path so two sources can never interleave (ARCH-15). Tests with fakes for each sub-model.
2. **Slide actions** fire when a slide goes live (the engine's rules: not on preview, not on quick edit). The executor's `tick()` is driven by an injected clock from the app's existing ticker. Reflow shows the warning that slide actions on changed slides will be dropped (KI-075), using the store's carry-over result.
3. **Schedule**: the app polls `ScheduleEngine` once a second with the wall clock and on wake from sleep, saves the engine state through `CueStore`, and shows missed-and-skipped events as a notice in the operator window. A scheduled action never fires while the Hardware Test window is running a test.
4. **MIDI**: a setting to enable MIDI (off by default), chosen input and output devices by stable id, the virtual ports toggle, a bindings list with "learn", conflicts shown. Incoming commands use the one command path. A lost device is shown as offline and reconnects when it returns.
5. **Remote control**: a setting to enable the server (off by default; NFR-09), the port, the current pairing code shown large with its countdown, the address to open on a phone, the list of paired devices with last-used time and Revoke, Revoke all. `RemoteControlTarget` implemented against the one command path and a `RemoteState` built from the models; `stateDidChange()` called when the show, timers or playlist change. Tokens stored as salted hashes through a `TokenStore` backed by the library (a new migration, the next free number; `prefix(n)` in tests). The doc's plain-HTTP warning is shown next to the enable switch in one sentence.
6. **Interface**: the **Cues mode** (match `06-cues.png` as far as features exist): macros (create, rename, reorder, delete with the referrer warning, edit steps with a picker per action kind), slide actions for the selected slide, scheduled events, MIDI bindings, and the Remote control settings. The **Cues tab** in Show: macro buttons that run on click, and the next scheduled event. Remove the "arrives in a later version" notes.
7. Playback markers: only if the media controller can host them cheaply; otherwise leave them and say so.

## Do not modify

Coordinator-owned tests. `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, earlier migrations, vendor files.

## Seeing it run

Debug `--ui-snapshots` hook (reads `UI_SNAPSHOT_DIR`; see KI-083) with a temporary `--library`, `--silent-audio`: a macro with three steps run from the Cues tab, a slide action changing the Look when its slide goes live, a MIDI note arriving on the virtual port advancing the slide, and one remote-control request over the loopback interface advancing the slide with the server enabled on an ephemeral port then disabled again. Save `AI/reports/CUE-002b-cues.png` and `CUE-002b-show-cues-tab.png`; look at them and describe them. **Before saving any picture of the Screens mode or anything showing the Mac's name, make the hook use a neutral computer name (KI-085).**

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. **The owner's real library is at `~/Library/Application Support/WORSHIPFLOW/`: never launch the app without a temporary `--library`; never touch that folder; the owner may have their own copy of the app running, which you must not quit or disturb.** The remote server may listen only on the loopback interface during your runs and must be stopped afterwards. Keep runs under two minutes, never cover a display, play no sound, do not request full computer control, leave nothing in the home folder. Do not commit or change git state in any way. Do not consult any advisor tool. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0 and the full suite passed three times in a row. Paste the summary line.
2. The pictures exist with your descriptions.
3. `docs/hands-on-checklist.md` gains a Cues section. `AI/reports/CUE-002b-report.md`: what was built, the control table changes, paths exercised in the running app, commands run with exit status, and everything not verified (no physical MIDI device; no phone).
