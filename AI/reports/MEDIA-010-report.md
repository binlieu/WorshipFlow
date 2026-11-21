# MEDIA-010 report: live media control

Model: Sonnet. Feature spec: `docs/features/MEDIA-010-live-media-control.md`. Known issues KI-100 to KI-103.

## Items

| # | Item | Result |
|---|---|---|
| 1 | Bin choice is a live override | Done |
| 2 | Four live clears | Done |
| 3 | Background video can be unmuted | Done |
| 4 | Bin selection shows a player in the sidebar | Done (picture of the video pane not seen, KI-102) |
| 5 | Hot folders | Done |
| 6 | Drop a video or picture on a slide | Done at model level; the drag gestures were not tried (KI-103) |

### What a media-bin click did before
- Media mode bin: a single click only selected the tile (and showed two buttons); a double click ran the dock action for the layer choice.
- Show dock: a single click ran it at once.
- Either way the action was `MediaModel.setBackground` or `playForeground`, which set the one global layer. It was not written to a presentation, but every slide thumbnail drew it (`thumbnailScene` used the layers), it was remembered across launches, and it only showed live on a screen whose theme is a motion background. So it looked as if it was applied to the current slides, and Preview thumbnails changed.
- After: thumbnails and Preview never draw the override (`LiveMedia.preview`); the Show inspector shows "Live background override" with a Drop button. It stays across Next, a new playlist item and Stop until replaced or dropped. It is still remembered across launches (existing behaviour, kept so the earlier tests hold).
- Select versus send live: in the Media mode bin a single click selects (sidebar player), a double click or "Send to live ..." sends live (`MediaBinInteraction`). The Show dock keeps single click = send (UI-003's design); this is a decision, not in the brief.
- Item 6 versus 1: a drop on a slide edits the presentation; a bin choice does not.

## Order of work and the failing output
All tests were written first. They were compiled in a scratch copy of the package (the other agent's `ProgramPackageTests` were red at the time, which hid my errors in the shared tree), file by file. No test failed at runtime before the implementation: every one failed to compile for a symbol the item introduces (permitted by the brief). Per item (counts of compile errors, logs `red-round1..3` in the session scratchpad):
- 1: `MEDIA010_LiveOverrideTests`: no `LiveMedia`, `MediaBinInteraction`, `SlideContent.background`, `hasLiveBackgroundOverride`, `dropBackgroundOverride`, `onBackgroundChosen`.
- 2: `MEDIA010_LiveClearTests`: `CueTransport` has no member `clearBackground`, `clearForeground`, `clearMusic` (14 + 10 + 7 + 3 + 3 + 2 errors); `ShowState.isBackgroundCleared`, `ShowShortcuts`, `ClearControl.layerMenu` missing.
- 3: `MEDIA010_BackgroundSoundTests`: no `isBackgroundMuted`, `setBackgroundMuted`, `backgroundHeardMuted`, `onBackgroundAudioChange`; `MEDIA010_RegistryBackgroundAudioTests`: "`MediaRegistry` has no member `setBackgroundAudio`". The bug itself was read, not run: `applySlot` opened a background with `muted: slot == .background || silent`, and the existing test `foregroundAudioIsAppliedToASourceOpenedLater` asserts the background is always muted.
- 4: `MEDIA010_BinPlayerTests`: no `MediaPreviewModel`, `PreviewControls`, `PreviewSendActions`, `PreviewPlayback`.
- 5: `MEDIA010_HotFolderTests`: no `FolderListing`, `FolderWatch`, `HotFolderModel`, `setHotAssets`, `playFolder`.
- 6: `MEDIA010_SlideBackgroundTests` (no `SlideEditorModel.setBackground`, `SlideBackgroundDrop`, `SlideContent.background`) and `MEDIA010_SchemaTests` (no `HotFolder`, `mediaFolders`, `saveMediaFolder`, `removeMediaFolder`).

One test file changed after the first run, by me, because of something found later: `MEDIA010_SchemaTests` was first written for migration v11 and was rewritten when an existing test (see deviations) ruled the migration out; `MEDIA010_LiveClearTests` lost an unreachable assertion on an internal property and gained a `stopForeground` line (a clip over the words hides them by design). Existing tests were not edited.

## Checks
- `./scripts/check.sh`: exit 0, "Test run with 2336 tests in 355 suites passed" (run twice; the second after the docs). 82 of them are `MEDIA010_*` (registry 3, background sound 6, bin player 8, hot folders 22, clears 16, override 7, slide background 14, store 6). The other agent's tests were green by then; earlier in the session its target did not compile and I ran my targets in a scratch copy without it.
- Debug app build: part of the check.

## Pictures (`AI/reports/`, from the debug hook, temporary library, `--silent-audio`, window outputs, a throw-away bundle id)
- `MEDIA-010-bin-player.png`: Media mode, the video Sunrise selected, the sidebar player with play or pause, scrubber, time, Loop and Mute, and the two send buttons. The video pane is black (the hook draws the layer tree; KI-102).
- `MEDIA-010-clear-menu.png`: Show with a live override: the inspector's "Live background override: Sunrise" row with Drop, and the Clear menu entries drawn by a debug overlay (not the real popup).
- `MEDIA-010-hot-folder.png`: Media mode with a folder source "hot" (3 items: two videos and a picture), its header with Play folder, Stop folder and Stop following, and the folder playing on the background.
- `MEDIA-010-slide-background.png`: Show; slide 2 has the small film mark; the live slide and the live screen unchanged.
- `MEDIA-010-show-override.png`: Show with the override on.
The Audio panel shows the Mac's speaker model name (not the computer's name). No user name, home path or e-mail was found in the pictures or the code.

## Exercised in the running app (hook log, `media010:` lines)
Selected a video: the player held it, playing, position 0.4 s, muted, no live background. Sent it live: override on, stored slides equal to before. Unmuted the background: heard-muted false. Clear background: cleared, words still live. Next: cleared lifted. A folder with two videos and a picture: all three listed, none held back, Play folder started the first by name. Slide 2 given its own background: set, live deck unchanged.

## Not verified
Mouse and drag: the double click, the drop of a tile or a Finder file on a thumbnail, the folder open panel, the real Clear menu popup, Control-Option-B, F, M through the real keys, VoiceOver. The video picture in the player and in a slide thumbnail. A file growing in a real folder; the real directory watcher (only the fake was tested; the app timer rescans every ten seconds, and every two seconds while a file is held back). A real unplugged or renamed folder at launch. Sound actually heard (silent audio). Frame gap between folder clips. Hardware.

## Deviations from the brief
1. **No migration v11.** `LIB004c_ScripturePlaylistItemTests.noNewMigrationWasNeeded` asserts exactly ten migrations and may not be edited, so the slide background and the hot folders are JSON in `appState` (KI-100, data dictionary). The brief's "migration if needed" test with `prefix(n)` became a test that no migration is added.
2. **Where a background shows.** An existing test says a bin background does not show on a picture theme. So the override follows the old rule (motion or colour theme, not picture, not transparent); a slide's own background also shows on a picture theme (KI-101). The brief did not ask for this split.
3. **Show dock single click still sends live** (the brief's select-versus-send rule applied to the Media mode bin only).
4. Clear background keeps the override (it hides, it does not drop it); the Drop button is the separate drop.
5. Cue editor kinds for the clears are named `clearLiveBackground`, `clearLiveForeground`, `clearMusic` because `clearBackground` already means "drop the override" there. `CueMediaPort` and `CueTransportPort` gained methods with default bodies so earlier fakes compile.
6. Undo of a slide's own background works while that slide is selected (the editor's undo is per selected slide).
7. A slide thumbnail shows a mark, not the background's picture.
8. Files outside my list that I changed: `CueSupport.swift`, `CuesMode.swift`, `WorshipFlowApp.swift` (menu items), `Persistence/LibraryStore+Content.swift`, `+Structure.swift` (shared with the other agent; one edit of mine was overwritten by it and redone; I checked both of my hunks are in place at the end), `docs/16`, `17`, `19`, `hands-on-checklist.md` (appended after the other agent's lines). `xcodegen generate` (run by check.sh) rewrote `WORSHIPFLOW.xcodeproj` for my new files.

## Files created
`App/Sources/BinPlayerPanel.swift`, `BinPlayerSupport.swift`, `HotFolderSupport.swift`, `UISnapshotMedia010.swift`; `Packages/WorshipFlowKit/Sources/OperatorCore/HotFolderModel.swift`, `LiveMedia.swift`, `MediaPreviewModel.swift`; `Sources/Persistence/LibraryStore+MEDIA010.swift`; `Sources/Domain/MediaFolder.swift`; tests `MEDIA010_*` (8 files); `docs/features/MEDIA-010-live-media-control.md`; `AI/reports/MEDIA-010-report.md` and the five pictures.

## Files changed
`App/Sources/`: AppModel, CentrePane, CueSupport, CuesMode, MediaBinPanel, MediaDockView, ModeViews, ShowInspector, Thumbnails, TransportBar, UISnapshotRun, WorkspaceUIState, WorshipFlowApp. `Packages/WorshipFlowKit/Sources/`: CueEngine/CueAction; Domain/MediaLayers, SceneComposer, ShowState, SlideContent; MediaEngine/MediaRegistry; OperatorCore/CueEditing, CuePortConformances, CuePorts, HeaderChrome, LivePublication, MediaModel, ShowCueTarget, SlideEditorModel, WorkspaceModel+Transport; Persistence/LibraryStore+Content, LibraryStore+Structure (Records and Schema were edited for the dropped migration and put back exactly; git shows no change). `WORSHIPFLOW.xcodeproj/project.pbxproj` (generated). Docs as above.
