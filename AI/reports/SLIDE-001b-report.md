# SLIDE-001b report: slide editor for objects, reflow fixes, small fixes

Levels claimed: Implemented; Unit Tested (model, rules, store). Exercised in the running app: only the paths listed below.

## Commands
- `./scripts/check.sh`: exit 0. `Test run with 550 tests in 83 suites passed` (483 before; 67 new). Coordinator-owned tests unchanged.
- Debug app built with `xcodebuild ... -derivedDataPath /private/tmp/claude-501/wf-dd`, run with `--library` in a temporary folder (since deleted). Four short runs, each under two minutes; quit with an Apple Event quit. Nothing was created under `~/Library/Application Support/WORSHIPFLOW` (it did not exist before or after). `~/Library/Preferences/org.worshipflow.app.plist` already existed (KI-039) and was left.

## Part 1: slide editor
Built:
- `Domain/FreeSpace.swift`: places a new box in free space (nearest free spot to the preferred one, else least overlap).
- `OperatorCore/SlideEditing.swift`: new-object templates, value limits. `OperatorCore/SlideEditorModel.swift`: add text box / rectangle / ellipse / rounded rectangle / image (image through an injected chooser), select, move and resize (from-start, through the `SlideObject` helpers), text, font, size, colour, outline, shadow, alignment, fill, stroke, corner radius, image fit/fill, opacity, four stacking moves, duplicate (offset), delete, undo and redo (snapshots of the object list per slide, 100 steps, a drag or a run of the same edit is one step). Saves through `WorkspaceModel.editSlide` (debounced save, preview deck updated, live untouched; tested for an object edit).
- Stage layout elements are now also placed in free space (`StageModel.addElement`).
- `KeyRouting`: `.deleteKey` and decision `.deleteSelectedObject` (never while typing, in a sheet, or with Command held).
- App: `SlideObjectsEditor.swift` (canvas drawn by the compositor with the slide's resolved theme, selection outline, corner resize handle, drag to move, double-click text box to type, inspector, undo/redo/duplicate/delete buttons), a Words/Objects switch in `CentrePane.swift`, Insert menu (menu bar and a button), Edit > Undo/Redo and Insert > Duplicate Object (Command-D), Delete key in the key monitor, `AppModel` wiring. Insert buttons also sit in the inspector, because the menu and pop-up cannot be reached in the background.
- Two data-loss bugs fixed on the way: the words editor and the quick-edit popover rebuilt `SlideContent` without objects, which would have dropped them. `quickEditLiveSlide` now saves only the words into the stored slide (test added).
- New objects keep clear of the slide's own words where there is room (`reservedFrames`, supplied by the app from the audience scene).

## Part 2: reflow
- KI-019: `Domain/ReflowCarryOver.swift` (`Reflow.carryOver`): a new slide takes notes and objects from the first unused old slide with the same folded first-language words in the same section. `LibraryStore.replaceContent` now carries them; `LibraryStore.reflowLosses(of:with:)` and `WorkspaceModel.reflowLosses` list notes/objects that would be discarded; the re-flow sheet shows that list (orange box) before the button, whose label then says "discard these".
- KI-020: `Reflow.sections` numbers a later block with the same label but different words ("Chorus 2", "Chorus 3"); identical words (compared without case, accents, punctuation) share the section. A taken numbered name is skipped. Round trip through `Reflow.text` is stable (tested).
- `ReflowTests`, `ArrangementTests`, `SongStructureStoreTests` pass unchanged.

## Part 3: small fixes
- KI-028: the background picker in the theme editor is `fixedSize()` instead of `maxWidth: 480`; seen in the running app, "Background video" is complete.
- My own new undo/redo/duplicate/delete buttons clipped their titles in the first run; they are icon-only now (help text and accessibility labels keep the names).
- Slide grid min height lowered from 200 to 140 so the taller objects editor fits at small window heights. No other truncated labels were seen in the screenshots I took (main window, import sheet, re-flow sheet, theme editor); the stage editor, section order sheet, timers and media panels were not looked at.

## Screenshots
- `AI/reports/SLIDE-001b-editor.png`: operator window, Objects mode on slide 1 of "Amazing Grace". The slide canvas shows the two lyric lines, a red square below them and a small gold "Text" text box at the bottom left, the text box outlined in blue with a square resize handle; the inspector on the right shows Text box settings (text, font, size, colour swatches with gold selected, alignment menus, outline, shadow); under the canvas are insert, undo, redo (enabled), duplicate and delete icons. The grid thumbnail above shows the same objects.
- `AI/reports/SLIDE-001b-live.png`: after Go Live, the Audience live preview in the right column shows the same two lines, the red square and the gold "Text". The slide thumbnail has the red LIVE outline. The Stage preview shows the stage layout (no objects, as designed).

## Exercised in the running app (through accessibility, background only)
Import of a song through the import sheet (typing into the sheet's fields worked); Objects mode switch; add rectangle; fill colour red through a swatch button; add text box; text colour gold; select object; duplicate (offset copy appeared); undo of the duplicate (copy gone, redo enabled); delete; Go Live with the object on the audience preview; a delete in the editor while live changed the preview and thumbnail but not the live audience picture; relaunch with the same library (objects had been saved); Themes sheet (new theme, KI-028); re-flow sheet opens and shows the new text.

## Not exercised, not verified
- Dragging to move and resizing by the corner handle, double-click text editing on the canvas, typing in the inspector text and number fields (typing into those fields is not possible in the background), the colour panel, the font field, steppers, sliders (opacity, corners), shadow controls, stacking buttons (only built), the Image insert and the open panel, image objects at all.
- Keyboard: Delete key, Command-Z, Shift-Command-Z, Command-D. The menu-bar items (Insert, Edit > Undo) were disabled while the app was in the background, so even the menu path was not run. Only the model and the pure key rule are tested (same position as KI-026/KI-029).
- The output windows themselves were not looked at; only the operator window's Audience preview was. No second display, no hardware.
- A re-flow with real speaker notes: the loss list was tested in the store and model, but never seen in the sheet with an actual loss (typing notes was not reachable). The "arrow" of the Replace button label was not seen either.
- Quick-edit popover with objects in the running app; the Words editor after the fix in the running app (typing into it was not reachable).
- Free-space placement on the stage layout editor was tested in the model only.
- Window sizes: the window was about 1456x840; the minimum 1100x640 was not tried.
- The text box on canvas can be dragged under another object; hit-testing follows the stacking order, no marquee or multi-select (not asked).
- Undo does not cover edits made in the Words editor or speaker notes (by design: it restores object lists only).
- Undone history is lost when the presentation changes, and an app kill (not quit) within two seconds of an edit loses the edit (debounced save; quit and focus loss flush).

## Deviations from the brief
- The editor is inline under the slide grid (Words/Objects switch), not a separate sheet.
- Insert is offered as a menu-bar menu, a pop-up button and plain buttons in the inspector.
- Image paths are stored as plain paths (the app is not sandboxed); no security-scoped bookmark for image objects, so a moved file shows nothing (the inspector warns when unreadable).
- `xcodegen generate` (part of check.sh) regenerates `WORSHIPFLOW.xcodeproj`; I did not touch git state.

## Files
Created: `Sources/Domain/FreeSpace.swift`, `Sources/Domain/ReflowCarryOver.swift`, `Sources/OperatorCore/SlideEditing.swift`, `Sources/OperatorCore/SlideEditorModel.swift`, `App/Sources/SlideObjectsEditor.swift`, tests `Tests/DomainTests/FreeSpaceTests.swift`, `Tests/DomainTests/ReflowCarryOverTests.swift`, `Tests/OperatorCoreTests/SlideEditorModelTests.swift`, `Tests/OperatorCoreTests/StageFreeSpaceTests.swift`, `Tests/PersistenceTests/ReflowCarryStoreTests.swift`, the two PNGs and this report (all under `/Volumes/Storage/chilt/worshipflow/`, package files under `Packages/WorshipFlowKit/`).
Changed: `Domain/Reflow.swift`, `Persistence/LibraryStore+Structure.swift`, `OperatorCore/KeyRouting.swift`, `StageModel.swift`, `WorkspaceModel+Editing.swift`, `WorkspaceModel+Library.swift`; tests appended to `KeyRoutingTests.swift` and `WorkspaceModelExtraTests.swift` (not coordinator-owned); app: `AppModel.swift`, `CentrePane.swift`, `ImportSheet.swift`, `ThemeEditorSheet.swift`, `TransportBar.swift`, `WorkspaceUIState.swift`, `WorshipFlowApp.swift`; regenerated `WORSHIPFLOW.xcodeproj`.
Docs (`docs/16-known-issues.md`, data dictionary, change log) were not updated.
