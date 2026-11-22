# FIX-P report: fixes from the independent review of FIX-N and FIX-M

Feature IDs FIX-N, FIX-M, UI-005e. Brief `AI/specs/FIX-P-fix-n-review.md`, review `AI/reports/REVIEW-FIX-N.md`. Level: **Implemented, Unit Tested**; items 3 to 5 also exercised in the running debug build through the window (synthetic events, see "Not verified"). Not Hardware Verified, not Live-Service Verified.

## Per item

| Item | Reproduced? | Failing output before the fix | Change |
|---|---|---|---|
| 1 M1 undo from the source slide | Yes | `undoOnTheSlideTheApplyCameFromUndoesTheApplyOnEverySlide`: after Undo on the source, frames `[nil, 0.1/0.1, 0.1/0.1]` instead of `[0.1/0.1, nil, nil]` ("the first Undo from the source slide puts every slide back"); `undoFromTheSourceWorksWhenTheSourceHasNoEarlierStep` failed the same way | `applyLyricFrameToAllSlides` records a group step on the source (nothing changes on it) when at least one slide changed; `groupMembers` remembers who took part |
| 2 M2 silent partial undo | Yes | `aSlideEditedAfterTheApplyIsKeptAndTheUndoSaysSo`: `lastMessage` was nil, expected "Position restored on 2 of 3 slides; 1 was edited since."; the same for the redo and the multi-slide case | `stepGroup` counts restored versus expected slides (deleted slides are not counted), sets one plain message, never overwrites a later edit; a later clean step clears it. The message had no view: `ContentView` now shows `slideEditor.lastMessage` in the usual dismissable bar |
| 3 M3 wrong layout / empty undo step | Yes (the empty step); the wrong-layout write by reading | `aCommitForAnElementThatIsNotInTheLayoutWritesNothingAndRegistersNoUndoStep`: `undo.canUndo` was true. The new-API tests did not compile before (`extra argument 'layoutID'`, `no member 'interrupt'`) | `Commit.layoutID` captured at the press (`begin(_, layoutID:)`) and at the first nudge of a run; the view writes to that layout; `StageCanvasEditing.commit` refuses an element that is not in the layout (no write, no undo step). A nudge on another layout ends the earlier run first |
| 4 M4 drag restarts after the resign | Reproduced in the app that events keep arriving; the double move by reading and by test | New `PressGuard` and `interrupt()` tests did not compile before. In the app (real mouse events through the window): after the canvas's own window resigned, 5 further drag events reached the gesture and were ignored (box stayed at -50, 25 pt; the old code re-pressed on the first of them and measured the rest from the original press) | `PressGuard`: events of an interrupted press are ignored until the gesture's own end; a press at another start location is a new press, so a gesture whose end never came cannot swallow the next click. Used by `StagePointerSession` and by the Edit object box, lyric box and handles. The Stage resign observer only reacts to its own window (checked: another window resigning let the drag go on, -100, 50 at release) |
| 5 M5 stale selection | Not run in the app (no UI path to a stale selection from the hook); unit level | `takesArrows` / `validSelection` tests did not compile before | `StageCanvasEditing.takesArrows` requires the selection to be in the layout; the canvas clears a stale selection on a layout or element-list change |
| 6 L1 quiet period | By reading and by the system value | n/a (new pure function) | `NudgeTiming.quietPeriod(keyRepeatDelay:floor:)` = max(floor, delay + 0.25 s), fed by `NSEvent.keyRepeatDelay` for Stage (floor 0.6) and Edit (floor 1.0) |
| 6 L2 radio group | Yes by reading (`canvasLastClicked` cleared only by a mouse press) | n/a | `KeyRouting.clearsCanvasClick(keyCode: 48)`; the key monitor clears the flag on Tab |
| 6 L3 `gridHasFocus` | **No**: in the app the flag was true in Show, false after the mode changed to Stage, false after a box click; router focus `canvas`, Right arrow moved the box (0.7400 -> 0.7412) and the slide selection stayed | n/a | Code left alone (a first attempt in `ControlFocusTracker` and its test were removed) |
| 6 L4 draft after a drop | **No**: `typedTextWaitingToBeSavedSurvivesTheReloadAfterADrop` passed before any change (`loadContent` overlays `pendingDrafts`). A narrow race (a draft write ending between the store read and the overlay) cannot be forced without a hook | n/a | Left alone; the test stays as a guard |
| 6 L5 tracker scope | Yes | `aFailedDropInAnotherPresentationRestoresThatPresentationsOrder`: slides `["B6","B1",...]` after the failed drop, expected `["B1",...,"B6"]`; the playlist version failed the same way | `slideMoves` / `playlistMoves` are dictionaries of `ReorderTracker`, one per presentation or playlist, dropped when idle |
| 7 MIDI latency | measured | n/a | below |
| 8 KI-188 control | measured | n/a | below |

Existing tests touched: **none**. New tests: `FIXP_GroupUndoTests` (10), `FIXP_ReorderScopeTests` (3), `FIXP_CanvasTests` (11), `FIXP_CanvasSourceTests` (3).

## MIDI latency (item 7)

Debug build, this Mac, the app's own virtual MIDI port, message timestamp (stamped by the sender thread just before `MIDISend`) to the moment its command had been handed to the app (`MIDIRouter.debugLatencyProbe`, debug only). Load: 200-slide grid scrolled by a 60 Hz timer, `loop-1080p5994.mov` playing as the background, a Next per message.

| Case | Messages ran | Median | 95th | Worst | Over 50 ms |
|---|---|---|---|---|---|
| Idle (3 runs) | 100 each | 0.8 to 1.8 ms | 10.9 to 13.0 ms | 17.8 to 22.0 ms | 0 |
| Load, a message every 32 ms (3 runs) | 200 each | 2.5 / 9.8 / 9.7 ms | 78.9 / 29.6 / 33.5 ms | 182.9 / 49.6 / 65.6 ms | 11 / 0 / 1 |
| Load, a message every 7 ms (2 runs) | 109 and 105 of 200 had run after 3 s | 1.12 and 1.20 s | 2.2 s | 2.3 s | all |

At a realistic cadence the median is far under 50 ms and the worst (183 ms in the first run) under 200 ms. A faster stream backs up: one Next takes 25 to 30 ms on the main thread under this load (KI-187), so messages queue behind it. The router loses and reorders nothing. Recorded as **KI-189** (cause KI-187; no router redesign, as briefed). Not measured: real MIDI hardware, a Release build. (An earlier run of the fast burst ran at the end of the deck, where Next does nothing, and was discarded.)

## KI-188 control (item 8)

`FIXO_CONTROL=1 scripts/fixp-run.sh`: per mode, three rounds of: the same capture twice, two fresh builds of the mode, a capture against a fresh build; no command in between. 54 pairs, 2 differed: 22 px in the Show inspector's live monitor on the same capture twice, and 268 px in the Stage preview between a capture and a fresh build. Same rate and size as the 3 of 78 in FIX-O. **Noise** (live previews redraw on their own clock), not a stale view. KI-188 closed.

## Not verified / stopped short of

- Real-hardware drag after a real resign of the key window: the hook posts the notification and sends the mouse events through the window; whether SwiftUI delivers them after a genuine Command-Tab is established only for that synthetic path. The fix does not depend on the answer.
- M3 (layout switched mid-drag or mid-nudge) and M5 in the running app: unit and source tests only.
- Edit-mode `PressGuard` wiring (object box, lyric box, handles): built and unit-tested as a pure guard, not driven with a real mouse in this task.
- `NSEvent.keyRepeatDelay` was not changed in System Settings and re-measured.
- Debug-build numbers only. Hands-on checks are in `docs/hands-on-checklist.md` (FIX-P).

## Files

Sources: `Packages/WorshipFlowKit/Sources/OperatorCore/{PressGuard,StagePointerSession,StageNudgeSession,StageCanvasEditing,SlideEditorModel,KeyRouting,WorkspaceModel,WorkspaceModel+Editing,WorkspaceModel+Playlists}.swift`, `Sources/MIDIIO/MIDIRouter.swift` (debug probe); app: `App/Sources/{StageCanvasView,SlideObjectsEditor,AppModel,ContentView,UISnapshotFixP,UISnapshotFixOModes,UISnapshotRun}.swift`; `scripts/fixp-run.sh`; `WORSHIPFLOW.xcodeproj` regenerated. Docs: change log, known issues (KI-188 closed, KI-189), hands-on checklist.
