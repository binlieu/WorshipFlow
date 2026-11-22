# Independent review: FIX-N (58cc234), secondary FIX-M (1e5db03)

Read-only review, by reading code through git only. No build, no tests, no app run. Line numbers are approximate (as of 58cc234, via `git show`).

## High

None found that stops Space, Return, B, Escape or the clear keys from reaching the show.

## Medium

### M1. "Apply to all slides" is not undone by Undo on the slide it was applied from
- Files: `OperatorCore/SlideEditorModel.swift` `lyricApplyTargets` (skips `target.id != source`), `applyLyricFrameToAllSlides`, `undo()` / `stepGroup`.
- Scenario: in Edit, on slide A, set the lyric box position (this is a step on A's history), choose "Apply to all slides", confirm. Press Undo straight away, with A still selected. The group step was recorded only on the target slides (every slide except A), so A's own top step is its earlier position edit. Undo reverts A's position and leaves every other slide moved. The slides now disagree, and the alert's promise "One undo step puts them back" is false for the first Undo.
- The new tests hide this: `FIXN_EditInteractionTests.applyToAllIsOneUndoStepThatRestoresEverySlide` and the rewritten `FIXK_LyricBoxTests` case call `selectSlide(2)` before `undo()`, so they always undo from a target.
- Confidence: confirmed by reading.
- Fix direction: give the source slide a group marker too (for example a zero-change group step), or have undo look up the most recent group across all slides.

### M2. Group undo is silently partial when another slide was edited after the apply
- Same file, `stepGroup`: `guard h.undo.last?.group == group ... else { continue }`.
- Scenario: apply to all, edit slide C's text boxes or position (a new step on top of C), select slide B, Undo. B and the other untouched slides revert, C does not, and nothing says so. Redo has the mirror problem.
- A slide deleted or re-flowed in between is skipped the same way, which is acceptable. A slide that was re-flowed keeps its id but its content may differ, and `restoreContent` writes back only objects, background and frames, which is right.
- Confidence: confirmed by reading that the skip is silent. Whether this matters in practice is a judgement.
- Live is never changed: `restoreContent` goes through `workspace.editSlide`, and `apply(.restore)` is preview-only. That part is sound.

### M3. A drag or nudge cut short by a layout change commits to the wrong layout id
- File: `App/Sources/StageCanvasView.swift`, `.onChange(of: layout.id) { endEverything() }`, `refreshHandlers`, `pressEnded`.
- Scenario: a nudge run is open (the key-up was missed, for example Cmd-Tab mid-hold, or the 0.6 s quiet timer has not fired) or a drag is in flight, and the layout switches. By the time `onChange` runs, `body` has re-run. `nudges.onCommit` was re-made in `refreshHandlers` with the NEW `layoutID`, and `pressEnded` uses `self.layout.id`, which is also new. The commit then targets the new layout with an element id from the old one. The write is lost, and `registerUndo` still pushes a no-op undo step onto the undo manager. The "cut short, so write it once with what it showed" promise is not met for this trigger.
- The window-resign trigger is fine because the layout id has not changed then.
- Confidence: plausible (from reading; not exercised). Likelihood is low.
- Fix direction: capture the layout id in the run or drag at press time, not at commit time.

### M4. Drag restarts after an interruption and applies its offset twice
- Files: `StageCanvasView.swift` (`pressEnded` / `pointerState.press()`), `SlideObjectsEditor.swift` (`.onChange(of: editor.interactionEpoch) { dragStart = nil; pressed = false }`).
- Scenario: a drag is cut short by `didResignKeyNotification`. That notification is observed with no `object:`, so ANY window resigning key triggers it, not only the operator window. The drag is committed and `pressed` is cleared. SwiftUI's gesture may still be delivering `onChanged`. `press()` then returns true again, `pressBegan` re-hits at `value.startLocation` and re-begins from the now-moved stored frame, but the translation is still measured from the original press point. The box jumps by the offset a second time on the next move, and the end commit records it. Edit mode has the same shape: `interactionEpoch` is bumped, `pressed = false`, then the next `onChanged` re-presses.
- Confidence: plausible. It depends on whether SwiftUI keeps delivering events after the resign; cannot judge without the app.
- Fix direction: scope the notification to the canvas's own window, and after an interrupt ignore events until the gesture's `onEnded`.

### M5. Arrow keys can go dead in Stage with a stale selection
- Files: `StageCanvasView.swift` (`takesArrows = editable && selection != nil`), `KeyRouting.swift` `.canvas` case, `StageKeyView.keyDown`.
- Scenario: `selection` names a box that is not in the current layout (the layout was switched and selection was not cleared). The router sees `canvasHasSelection == true` and returns `.passThrough` for arrows. `nudge()` returns false (the element is not found), so `StageKeyView.keyDown` falls to `super`. The arrows then do nothing: they neither nudge nor move the slide selection. Space, Return, B and Escape are unaffected.
- Confidence: plausible. It depends on whether selection is cleared on layout change elsewhere.
- Fix direction: `takesArrows` should also require that the selected id exists in `layout.elements`.

## Low

### L1. Nudge quiet period shorter than the OS key-repeat delay
- `StageNudgeSession` `quietPeriod = 0.6`; Edit's `nudgeQuietPeriod` is 1.0. macOS "Delay Until Repeat" can be set longer than 0.6 s. A held arrow then commits after the first nudge, and the repeat starts a second run: two undo steps, two writes. Confirmed by reading; depends on the user's setting.

### L2. Radio buttons lose their arrows
- `KeyRouting.decision` `.nudgeCanvas` branch applies for `.button`, and AppKit radio buttons map to `.button`. After a canvas click, Tab to a radio group and arrows nudge the box instead of changing the choice. `canvasLastClicked` is cleared only by a mouse press, not by Tab. Plausible; narrow.

### L3. Stale `gridHasFocus` would hide the canvas
- `ControlFocusTracker.current(gridHasFocus:)` returns nil while `ui.gridHasFocus` is true. If that flag is still true after a switch to Stage (not checked where it is reset), `StageKeyView` focus would read as `.none` and arrows would move the slide selection instead of nudging. Cannot judge without running the app.

### L4. FIX-M: pending typed draft and the dropped `flushDrafts()`
- `WorkspaceModel+Editing.moveSlide` no longer calls `flushDrafts()`. The optimistic path keeps the draft text in memory, so the normal case is fine. If any later `reloadOpen()` runs while a draft is still pending (the visible order differs from `confirmed` at idle, or another operation reloads), the slide list is re-read from the store and shows the old text until the draft save lands. Not data loss, since `pendingDrafts` still saves; the display reverts briefly. Plausible.

### L5. FIX-M: tracker is not reset when the open presentation or playlist changes
- `ReorderTracker.begin` keeps `confirmed` while `pending > 0`. If the user switches presentation (or playlist) while a write is queued and drops in the new one, `confirmed` holds the other list's ids. A later failure then calls `restoring(items, toOrder:)` with ids that are not in the list: nothing is restored, and the visible order stays wrong after a failed write. Also `succeeded` finds no id and the idle check forces a `reloadOpen`, which is harmless. Plausible; rare.

### L6. MIDI burst test: the 600 s ceiling
- The test change is a ceiling raise plus extra assertions (`droppedMessages == 0`, `receivedCount == 2000`); the order and count assertions are not weakened. The report's measurement (17 s for 2000 messages when the main actor is busy, 0.02 s idle) suggests the consumer is serviced about once per main-actor turn. In the app, drag-drop stalls of 20 to 40 ms (KI-180) would delay MIDI-driven commands by the same amount per message in a burst. The test change does not hide a defect in the router's ordering, but it does remove the only automatic signal for that latency. Plausible; judging real impact needs a run with MIDI hardware under UI load.

## Checked and found sound

- `KeyRouting.decision`: `.canvas` returns passThrough only for arrows with a selection, and otherwise falls to the grid decision, so Space, Return, B, Escape and Shift-Escape reach the show. `.canvas` is not `isControl`. Cmd/Ctrl/Option and open sheets still pass through first.
- A text field focused anywhere still wins (`textInput` is decided before `focusedControl`), so typing does not leak to the show. In-canvas object text editing in Edit uses a field editor (`NSText`), so it is covered.
- `StageKeyView` focus lifecycle: becomes and resigns first responder both report; `viewWillMove(toWindow: nil)` clears it; `onDisappear` also clears `stageTakesArrows`, `stageArrow` and `stageArrowReleased`. After a mode change away from Stage no stale `.canvas` entry remains in the tracker.
- Alert for apply-to-all is attached to `WorkspaceView`, so it exists in every mode. It is an attached sheet, which the monitor already treats as `sheetOpen`; Return and Escape then act on the alert. Button actions capture `box` at body time, so clearing the binding does not race the action.
- `canvasLastClicked`: a local `leftMouseDown` monitor runs before view gestures, so reset-then-set order is right. Monitors are never removed, the same pattern as the existing key monitor.
- `StageNudgeSession`: `flush` is idempotent (run is set to nil before `onCommit`), so no double commit; a zero-net run writes nothing; `Task` inherits main-actor isolation and `[weak self]` is used; the idle timer is cancelled on every nudge and on flush. `keyUp` is handled both in the monitor and in the view, which is harmless because of idempotence.
- `StagePointerSession.finish` clears `pressed` and `drag`, and returns nil when nothing moved.
- Text-frame validation: every decode path goes through `SlideTextFrames.init(from:)` (the store column decode, `SlideContent` decode, program-package slide entry); `SceneComposer` additionally uses `.validated` for in-memory values. `usable` rejects non-finite, non-positive size and frames wholly outside the canvas; anything else is clamped with the same rule the editor writes with, so frames the editor ever stored are unchanged. NaN or infinity cannot arrive through JSON anyway. Only genuinely corrupt frames are dropped, and a dropped frame means "use the theme's frame", not a crash.
- `ShowStateTag`: derived from `isBlackedOut` / `isCleared`, which both require a live deck, so nothing shows while stopped; blackout wins over clear; style is `Badge.warning` (amber token), not the red live style; placed in the toolbar that is drawn in every mode.
- Lyric cache: key is slide id, primary text, secondary text and `appearanceRevision`. The revision is bumped on look, profile, media-layer, theme and presentation-theme changes (`onAppearanceChange` from both workspace and settings), and the slide's own frames do not feed the theme frames, so no stale result was found.
- Apply-to-all and Live: neither the write nor the group undo or redo touch live state.
- FIX-M: write order is serialised through `slideMoveTail` / `playlistMoveTail`; stale writes behind a failure are skipped and counted; epoch handling and `confirmed` updates are consistent for quick successive drops and for failure then a new drop.

## Not judged without running the app

- Whether SwiftUI keeps delivering `DragGesture` changes after a resign-key (M4), and what `firstResponder` is after an alert sheet closes.
- Whether Stage clears `selection` on layout change (M5) and where `gridHasFocus` is reset (L3).
- Real key-repeat timing versus the 0.6 s / 1.0 s quiet periods (L1).
- Whether the hit-by-position lookup in `lyricThemeFrames` (words layers found as the first N layers, props removed by counting an empty-slide scene) holds for every theme with props or a plate; it replaces a text comparison, so a theme whose composer adds text layers before the words would shift it.
- Main-actor starvation impact on MIDI in the live app (L6).
