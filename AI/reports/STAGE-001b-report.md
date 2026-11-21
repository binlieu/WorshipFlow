# STAGE-001b report: stage layout editor, timers and clocks in the workspace

## Built
OperatorCore (new): `StageModel.swift` (layouts, timers, per-screen choice, clock style, scenes, queued writes, operator-readable errors), `StageEditing.swift` (`needsPerSecondRefresh`, new-element defaults, frame/font clamping, sample scene, `ClockStyle`, `NewStageElement`).
OperatorCore (changed): `PublishedScenes` takes optional `stageScenes` (stage screens use them; audience/broadcast untouched); `WorkspaceModel` gains `liveNotes` (live slide's speaker notes, snapshot kept for when another song is open).
App (new): `StageEditorSheet.swift` (layout list, 16:9 canvas drawn by the compositor, draggable/resizable boxes, inspector, add/delete), `TimersPanel.swift` (timers with live values, add countdown / elapsed / to a time, start/pause/reset/rename/delete, 12/24 hour and seconds).
App (changed): `AppModel` (stage model, snapshot builder, ticker that exists only while an enabled stage screen's layout has a clock or timer, skips republish when the snapshot is equal, `liveRevision` so the one-second tick does not redraw slide thumbnails), `ControlPanels` (stage layout picker + Edit layouts), `ContentView` (toolbar button, sheet, panel), `WorkspaceUIState`, `Thumbnails` (live previews read `liveRevision`).
Tests (new): `StageEditingTests`, `StageModelTests`, `StagePublishingTests` (38 tests).
`xcodegen generate` (run by check.sh) regenerated `WORSHIPFLOW.xcodeproj`.

## Decisions
- Choice per stage screen and clock style live in app-state keys `stage.layoutChoices` and `stage.clockStyle`. No store method was missing.
- Built-in layout is read-only: edits set an error that names Duplicate; the sheet shows "Duplicate to edit".
- Deleting a timer leaves its elements in layouts; they draw nothing until pointed at another timer. Deleting a layout returns its screens to the built-in layout.
- Stage message is nil (not wired). Clock default is 12 hour, no seconds.
- Ticker first fires on the next whole second; countdown values are shown with the same 1 s granularity, so a timer started mid-second can lag up to 1 s.
- Live notes are read for the open presentation (follow edits) or from a snapshot taken when it went live.

## Commands
- `swift test --package-path Packages/WorshipFlowKit --filter OperatorCoreTests`: 110 tests in 13 suites passed (72 before).
- `./scripts/check.sh`: exit 0. Package step: 401 tests in 61 suites passed (includes the other agent's tests). Domain boundary, xcodegen and Debug app build ok.
- An earlier test run failed once because the other agent modified a file mid-build; retried, passed.

## Run in the app (Debug, temporary `--library` in scratchpad, window outputs not opened, background accessibility control)
Exercised: Stage layouts toolbar button opens the sheet; built-in layout read-only with Duplicate to edit; Duplicate created "Standard copy"; selecting elements shows inspector; font size stepper changed 56 to 60; Add Message; Add Timer (canvas showed the running countdown value); Done. Timers panel: Add timer form, 5:00 countdown added, Start, live ticking (4:29, 4:22, 4:19, 4:17 seen), Pause held 4:12; Seconds checkbox changed the "Now" text to include seconds. Stage layout picker shows the chosen layout. Quit; relaunch restored the layout choice, the layout, and the running timer (value continued from wall clock); the stage live preview showed timer top-left and clock top-right. DB rows (layout, running timer) checked with sqlite3.
Not exercised: dragging and resizing on the canvas (background control cannot drag), choosing a layout in the screens-panel popup (popups are refused in the background; I inserted the `stage.layoutChoices` row into the temporary library with sqlite3 between two launches, which then loaded correctly), typing in the name and numeric frame fields, colour picker, alignment, second-language toggle, delete layout/element/timer, rename timer, elapsed and to-a-time timers, 24 hour toggle, the overrun warning colour on screen (covered by a model test), opening real stage screens, real speaker notes on a live slide (covered by a model test), keyboard.
Screenshots: `AI/reports/STAGE-001b-layout-editor.png`, `AI/reports/STAGE-001b-timers.png`.
Nothing was created under `~/Library/Application Support/WORSHIPFLOW` (it did not exist before or after). The app was quit; the temporary library stays in the scratchpad.

## Not verified
Drag/resize gestures, full-screen or multi-display stage output, per-second republish cost with real outputs, 24-hour and elapsed paths in the UI, accessibility labels beyond what automation used.
