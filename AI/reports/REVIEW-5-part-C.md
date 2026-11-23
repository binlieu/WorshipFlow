# Independent review, fifth pass, Part C: operator interface and fixes

Range: `8590d5a..fb41ae2`. Scope: FIX-V, FIX-U, UI-007e, UI-007f, UI-008 and the status of every REVIEW-4 finding. Read-only: code read through git and the working tree; nothing was built, run or launched. Reports in `AI/reports/` were not trusted. Line numbers are as of `fb41ae2`.

Confidence words: "confirmed" means the path was read end to end. "Plausible" means the path exists but a timing, platform or input condition was not established.

Count: 0 high, 2 medium, 5 low.

## High

None found.

## Medium

### M1. Removing a mirror leaves the key note and the signal chain on the wrong destination
- Where: `Packages/WorshipFlowKit/Sources/OperatorCore/ScreenEditing.swift:135-141` (`removingMirror`, unchanged in this range) against `Domain/OutputRouting.swift` (`connectedKeyNote`, `signalChain(mirror:)`, indexed by `mirror + 1`). Called from `App/Sources/ScreensDetail.swift:286` and `ControlPanels.swift:238`.
- `removingMirror` removes the entry at `index + 1` from `connectedTo` so the typed notes stay aligned. SYS-015 added two more arrays with the same indexing (`connectedToKey`, `signalChains`); `removingMirror` does not touch them.
- Scenario: a screen has two mirrors, and the operator typed a signal chain "Foyer extender" for mirror 1 and "Hall converter" for mirror 2. They remove mirror 1. Mirror 2 is now the only mirror (index 0), and the map and the Screens notes show it with "Foyer extender", a box typed for the mirror that is gone. The key note moves the same way. These lines are marked "typed by you" and are the operator's record of what hardware sits on each path, so a wrong one is a wrong statement about the equipment.
- Related, smaller: switching a destination from Fill and Key to plain leaves its key note stored but hidden; it comes back if keying is turned on again.
- Confidence: confirmed by reading. No test covers it (`UI007f_SignalChainTests`, `SYS015_FieldsTests` test the getters and setters only).

### M2. Edit's Broadcast and Stage previews ignore the screen's own Look
- Where: `App/Sources/EditCanvasChrome.swift:44` (calls `EditPreviewScene.scene(... look: currentLook ...)` with no per-screen Looks); `Packages/WorshipFlowKit/Sources/OperatorCore/UI006c_EditFeatures.swift:127-137` (the function has no `screenLooks` parameter and builds `PublishedScenes` without one).
- The audience preview goes through `thumbnailScene`, which was changed to pass `screenLooks: screenLookOverrides` (`AppModel.swift:543-545`), so the audience canvas is right. The other two roles in Edit are composed with the show's Look only.
- Scenario: the broadcast screen has its own Look "Lower third" while the show's Look is "Worship". In Edit the operator presses Broadcast to check a slide. The canvas draws it with Worship's theme and layers for that screen, not the Look the broadcast output will use. The caption says it is the screen's scene. For a stage screen the same gap changes which props sit on the preview.
- This is the same kind of mistake as REVIEW-4 M1 (a preview that is not the screen's real scene), now for the new per-screen Look. The M1 test (`FIXV_EditStagePreviewTests`) compares preview and real scene with no Look at all (`look: nil`), so it cannot see this.
- Confidence: confirmed by reading.

## Low

### L1. Edit's Stage preview leaves out the section names, so a Section element draws nothing there
- Where: `OperatorCore/UI006c_EditFeatures.swift:158-170` (`previewState` builds `ShowDeck(presentationID:slides:)` with no `sectionNames`), called by the stage branch added for FIX-V M1.
- The live deck is built with `sectionNames` (`WorkspaceModel.swift:349-350`). The preview deck is not. A stage layout that has the new Section or Next section element therefore shows neither in Edit's Stage preview, while the real stage screen does.
- The M1 test hides this: `FIXV_EditStagePreviewTests.real(...)` (line 25) builds its own deck without `sectionNames`, so preview and "real" agree in the test and differ in the app.
- Confidence: confirmed by reading.

### L2. A marker is deleted with one click and no confirmation
- Where: `App/Sources/MediaMarksPopover.swift:168` (`markers.delete(marker.id)` from a trash icon).
- Deleting a marker also deletes the list of cue actions stored on it, and there is no undo. The project rule is that no destructive action goes without confirmation. The button carries `role: .destructive`, but the custom button style does not draw it red, so the colour rule is kept; the confirmation rule is not.
- Confidence: confirmed by reading.

### L3. A typed note can be lost when the screen selection changes while its field is still focused
- Where: `App/Sources/ScreensNotes.swift:153-175` (`CommitField` commits on Return or when focus is lost), with `ScreensDetail.swift:40` giving the whole notes block `.id(profile.id)`.
- The older "Connected to" field writes on every keystroke. The new key note and chain label keep a draft and write only on Return or focus loss. On macOS a click on a plain SwiftUI row does not always take focus out of a text field. If the operator types a note and clicks another screen in the list, the notes block is replaced by one with a new id, and the draft may be dropped with no focus-lost event.
- Confidence: plausible (depends on whether the focus change fires before the view is removed). Hands-on item 3 below settles it.

### L4. Look controls still say a Look applies to every screen, and nothing in Show says a screen keeps its own
- Where: `App/Sources/ControlPanels.swift:501` and `:520` ("Switching Look changes every screen at once"); `ShowInspector.swift:118` and `:131` (the Look buttons); `ControlPanels.swift:514` (Delete, no confirmation).
- After UI-007f a screen with its own Look does not change when the show's Look changes (by design, `ScreenLooks.overrides`). The only place that says so is Screens (the list row and the notes block). The Look panel text is now wrong, and in Show the operator picks a Look and one audience screen silently stays on another. Deleting a Look (also unconfirmed, as before) now sends every screen that chose it back to the show's Look at once, which can be on air.
- Confidence: confirmed by reading. The behaviour is as designed; the words and the missing hint are the defect.

### L5. One stalled volume can block every later offline check
- Where: `OperatorCore/MediaModel+Offline.swift:15-16` (`offlineRunning`).
- The FIX-V L8 fix allows only one check at a time and never cancels it. If that check is stuck reading a hung network volume, `offlineRunning` stays true, so every later request, including the one after a different disk is plugged in, only sets `offlineAgain` and never runs. The offline marks then stay as they were until the app restarts. This is the cost of the L8 fix, which removed the pile-up of threads.
- Confidence: plausible (needs a volume that hangs rather than fails).

## REVIEW-4 findings: status

- M1 (Edit Stage preview not the stage screen's layout): partly fixed. `EditPreviewScene.scene(... stage:, deck:, index:, notes:)` passes the stage screen's own scene (`UI006c_EditFeatures.swift:127-156`, `EditCanvasChrome.swift:40-52`); layout, Hide, Auto-fit, next line and notes (stage role only) now match. Two gaps remain: section names (L1 above) and the screen's own Look (M2 above). Notes reach only the stage role; the audience and broadcast previews are given none (confirmed by `stageScene` being built only for `role == .stage`).
- M2 (`retiring` never emptied on display paths): fixed. `retire(_:)` (`OutputCoordinator.swift:435-440`) keeps only a target that is still tearing down; a window or display stops at once and is never held; an SDI target leaves the list when its own teardown ends (`SDIOutput.swift:354-366`, `TeardownCounter`). The waiting stop and the SDI start still drain it. `FIXV_RetiredOutputTests` uses fake targets, so a real `MetalOutput` being freed (display link, window) is a Part A and hands-on matter.
- M3 (`removeSection`/`moveSection` by row position): fixed. Entries are found again by section and occurrence after the awaits, edits run one after another (`editSectionOrder`, `sectionEditTail`), the order is read from the library after the draft flush, a missing entry changes nothing and says so (`WorkspaceModel+SectionOrders.swift:30-105`; `SectionOrderSheet.swift:123-153`). `renameSectionOrder` and `addSection` use the same path. One quirk: a second click on "the second Chorus" after the first Chorus was removed does nothing and says so, which is safe. The tests do race two calls (`async let`) and would fail on the old code.
- M4 (Remove screen not blocked on air, thin confirmation): fixed. `ScreenListEditing.removalBlock` refuses a screen whose output is running, hidden or faulted, and the only enabled screen of a role while screens are open (`UI006f_ScreenListEditing.swift:26-37`, `AppModel.swift:840-858`); the confirmation names the Looks and stage layout that go with it; `forgetScreen` prunes the stage layout choice (`StageModel.swift:210-211`, called through `onProfileRemoved`). Residual: the block reads `readouts`, which are polled, so a screen opened a moment ago may not be listed yet (the only-of-its-role rule covers the common case). `AppModel.activeOutputIDs` and a running coordinator are still untested.
- M5 (macro key bypasses focus rules): fixed. The key goes through `KeyRouting.decision` (`.runMacro`), only in Show and Cues, only in the operator window, not with a sheet or modal, a modifier, Shift or a repeat, not in a text or search field (`KeyRouting.swift:170-216`, `AppModel.swift:686-692`). A focused button no longer blocks it, which the code states on purpose. Tests cover the pure function for every mode and focus; the `AppModel` arguments (`isOperatorWindow`, `modalUp`, `mode`) are not tested.
- L1 (Identify screens not dismissed on Open screens): still open. `ScreensIdentify.swift` is unchanged in the range.
- L2 (hot-folder items in a collection): fixed. `binIDs` refuses them with a message (`MediaModel+Collections.swift`), tested.
- L3 (collections and macro keys overwritten after unreadable text): fixed for both. The damaged text is kept under a `.unreadable` key and the operator is told; the first prune is redone after the keys load; tested. The old "two `setKey` calls reorder" worry is not shown by the code (each awaits its write) and a test now covers it.
- L4 (screen-keyed values never pruned): fixed for the stage layout choice. A removed screen's Look entries are handled as before.
- L5 (`slideActionPresentations` read once): fixed in the sense that Cues reads it again each time it appears (`CuesMode.swift:31`). It still does not follow changes made while Cues stays open. Cosmetic.
- L6 (newer stage layouts lossy in an older build): fixed in effect. A v15 library is refused by an older build (`unknownMigration`, `LibraryStore.swift:103`), and opening any library in this build moves it to v15. Not fixed by design for those keys.
- L7 (hide guard on the element the stage needs): still open. `UI006e_StageModelExtras.swift` is unchanged.
- L8 (offline check blocks threads): partly fixed. One check at a time, and activation checks only after a change or 60 seconds (`MediaOffline.shouldCheckOnActivation`). The cost is L5 above.
- L9 (red confirmation buttons): partly fixed. The three named sites (Remove screen, Delete collection, Delete element) no longer use `role: .destructive`. Many other dialogs still do (for example `CentrePane.swift:172`, `MediaBinPanel.swift:83`, `LibrarySidebar.swift:80`, `ThemeEditorSheet.swift:51`, `StageEditorView.swift:60`, `SectionOrderSheet.swift:44`, `CuesEditors.swift:29`, `:202`, `CuesControlInputs.swift:216`, `ScriptureTranslationsView.swift:56`). Cosmetic, as in REVIEW-4.
- REVIEW-4 note on `Delete collection` line: the first FIX-V commit (`5c80e68`) left the action inside a line comment; `df075aa` repaired it, and the line at `MediaMode.swift:124` is correct in the final tree.

## Tests

For each new test file in this part:

- `FIXV_MacroKeyRoutingTests`: real. Would fail if M5 regressed in `KeyRouting`. Does not test `AppModel`'s call (window, modal, mode arguments).
- `FIXV_RemoveScreenTests`: real for the rules, the model and `forgetScreen`. Missing: removal against a running coordinator, and `activeOutputIDs` (REVIEW-4 listed this as untested; it still is).
- `FIXV_SectionOrderTests`: real. Two `async let` calls reproduce the review's case, and a repeated section is covered.
- `FIXV_RetiredOutputTests`: real for the coordinator's list with fake targets. The weak-reference loop proves nothing is held; it does not prove a real `MetalOutput` is freed.
- `FIXV_EditStagePreviewTests`: real for layout, Hide, Auto-fit, next line, notes and the draft slide. It uses `look: nil`, and its `real(...)` builds a deck without section names (M2, L1).
- `FIXV_LowFindingsTests`: real; the one-at-a-time offline test blocks a real read and counts. Not covered: a check that never returns (L5).
- `FIXU_ViewSourceTests`: reads source text. It fails if someone moves a read back into `WorkspaceView`, `ShowInspector` or `TransportBar`, and passes if a new read is added under another name. It cannot see how often a body runs; the report says the real numbers came from a script. Same limits as the REVIEW-4 source-text tests, which are unchanged.
- `UI007e_StageSectionTests`: real for the composer (live section, no section, stopped, cleared, next only on change, hidden, never on audience or broadcast, round trip). Missing: a deck with a custom section order through `WorkspaceModel` (`SYS015_EditorTests` only checks names against the slides' own groups), and the two elements in Edit's preview.
- `UI007f_ScreenLookTests`: real for resolution, composition, deletion fall-back, persistence and image paths. One assertion is weak: `aStageScreenOnlyTakesTheLookForItsProps` (line 210) passes if the scenes are merely unequal (`<` or `!=`) and does not go through `stageScenes`. Missing: removing a screen that has a chosen Look, and the Edit previews (M2).
- `UI007f_SignalChainTests` and `UI007f_SignalMapNotesTests`: real for the pure editing and the map tiles. Missing: mirror removal (M1).
- `UI007f_ScenesDigestTests`: a recorded digest of the scenes with no per-screen Look; a real guard that nothing moved for libraries that do not use the feature.
- Not tested at all: the Screens notes view, the draft behaviour of `CommitField` (L3), the toolbar and transport split views at run time.

## Areas checked and found sound

- FIX-U's three split views (`ToolbarStateTag`, `ShowSlimRow`, `TransportText`): the same content, labels (`Show state`, `Edit live slide...`, `Drop the live background override`), help texts, `accessibilityElement(.combine)` on the text block and keyboard paths were carried over. `fixedSize` keeps the badge width. No timer, `TimelineView` or polling was added; each view reads only what it shows. The popover on "Edit live slide" and the Drop button still work from the moved view.
- UI-008: the changes are one button style (Add screen keeps its label, help and disabled rule), tag-only `wfRect` calls, prefixed rectangle ids for the nested action list, the Auto-fit label size and field width, and a fixed hex field width inside a fixed 299 pt inspector. No behaviour change found.
- Per-screen Look (UI-007f): `ScreenLooks.overrides` skips a screen whose own Look is the show's, so changing the show's Look never moves a screen that kept its own; a deleted Look clears the choice in memory and in the stored profiles in the same call; a removed screen takes its choice with it; a new screen starts following the show's Look; `editScreenLook` edits the Look the screen uses; every composer except Edit's previews takes the overrides (`makeSnapshot`, `thumbnailScene`, the soak snapshot, layer chips, theme lookups, image usage, program export's Looks in use). A note or chain edit does not change the output signature, so it never restarts an output (`OutputCoordinator.signatures`). The choice does not re-plan outputs; it republishes through `onAppearanceChange` like `selectLook`.
- Notes and layouts to the wrong screen: stage scenes are put into `PublishedScenes` only for stage-role profiles; the Edit preview takes notes only for the stage role; the new Look path gives a stage screen only props. No new path puts notes or a stage layout on an audience or broadcast screen.
- Signal chain and key note editing: label trimmed and cut to 120 characters (also when read from storage, through the initialiser), chain cut to 12, a mirror that does not exist takes nothing, empty tails are dropped, stored only when non-empty (a library using none stores what it stored before). The map shows the key tile's own note and falls back to the fill's, and shows at most three typed boxes with "+N more".
- Stage Section and Next section (UI-007e): drawn by `StageComposer` only; the audience and broadcast composers never read the names. The right section is used with a custom section order, because the names come from the slides of the arranged list (`WorkspaceModel.previewDeck`); an empty, blank or missing name draws nothing; next section draws only when its name differs from the live one (by design). Neither element ticks, so nothing is added to the stage's one-second refresh.
- The two merge resolutions: `thumbnailScene` passes the overrides and then `stillScene` (poster for each video object); `SlideCanvas` uses `thumbnailScene` for the audience role (already still) and `stillScene(editPreviewScene(...))` for the others, so each role goes through `stillScene` exactly once and a video object is never played in Edit. For Broadcast with a transparent theme, objects are left out by the composer as before. The only gap is M2/L1, which is about what the preview composes, not about the merge.
- Editing never changes Live: Remove screen, Select Look for a screen and marker edits write only settings or library rows; nothing in this part writes to `ShowState`. Red is not used for anything but on air in new code (the Blackout and Cleared word is amber, as before).

## What cannot be judged without running the app: a hands-on script

1. Macro key. Give a macro "Select Look" the key F5 (hold Fn if needed). In Show with the grid focused, press F5: the Look changes once. Click a button so it has focus and press F5: it still runs. Switch to Edit, select an object, press F5: nothing runs. Open Settings and press F5: nothing runs. Press F5 in a text field: nothing runs.
2. Per-screen Look. In Screens give the lobby audience screen its own Look. In Show pick another Look: the lobby stays, the main screen changes, and the list row says "Look: ...". Delete the lobby's Look in the Look panel: the lobby follows the show's Look at once (L4). Remove the lobby screen: the dialog names its Looks.
3. Notes. Type a key note, then click another screen in the list without pressing Return: reopen the first screen and check the note is there (L3). Add a chain to a mirror, remove the first of two mirrors, and read the map (M1).
4. Edit previews. Give the broadcast screen its own Look, then in Edit press Broadcast and compare with the real broadcast window (M2). Add a Section element to a stage layout and press Stage in Edit (L1).
5. Remove screen. With one audience window running, press Remove screen: it must refuse. Close screens, remove it: its output is gone and the stage layout choice with it. Open screens and press Remove on a screen that has just been opened: check the refusal appears at once.
6. Section order. In a song with three sections, remove the second and, at once, the third row: the right two are left. Drag a section: it lands before the one it was dropped on.
7. Stage Section. Give the stage window a layout with Section and Next section; Go Live through a song with a custom order and a repeated chorus: the section name follows the arranged order, and Next section appears only when the name changes.
8. Display memory. With display or window outputs only, open and close the screens twenty times; compare memory in Activity Monitor (FIX-V M2 with a real output).
9. Offline check. With a network volume that hangs, plug in a USB disk with a bin file: check the offline marks update (L5).
10. Transport bar and Show inspector. Press Next, Clear and Blackout with the app idle in between: the words and the badge update, the buttons do not flicker, and the CPU stays quiet when idle.
