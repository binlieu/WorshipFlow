# FIX-Y report: the remaining low findings outside the output path

Feature IDs: SLIDE, MEDIA, CUE-33, LIB-005, OUT (screens), STAGE. Model: Sonnet. No migration, no git state change, `docs/` not edited.
Verification levels: Implemented and Unit Tested for every item. Views were not exercised by hand (hands-on entries below). Nothing here is Simulated, Hardware Verified or Live-Service Verified.

All 12 items were real as described (each confirmed in the code first). Nothing was "not real" and nothing was left unfixed. One item (11) and parts of items 3, 8, 9 are view wiring that unit tests can only pin by source text.

## 1. REVIEW-5 L2: a video object ignored the clip's in and out marks: fixed
- Code did: `ObjectVideoRequest` had no marks and `ObjectVideoPlayers.apply` built `VideoPlayerSource(url:loops:duration:muted:)` without `markIn` or `markOut`.
- Failing test (old code): `FIXY_ObjectVideoMarksAndClearTests.aVideoObjectLoopsInsideTheMarksOfItsClip` (red first second shown although In = 1) and `aChangeOfMarksReopensTheClipAndEqualRequestsDoNot` (player's transport had no in mark).
- Change: `ObjectVideoRequest` carries `markIn` and `markOut` (part of its equality, so a changed mark reopens the clip at the next publish; equal requests keep the player). `apply` passes them to `VideoPlayerSource`, the same one used for layers. `App/Sources/EditObjectVideos.swift` fills them from the bin item. Test hook `markRange(for:)`.
- Not verified: a real slide on screens (hands-on 1). A mark changed while the object is on air takes effect at the next publish, not at once (the same "a clip that is on air keeps the marks it started with" rule the marks popover states for layers).

## 2. KI-280: Clear closed and restarted the video-object players: fixed
- Rule matched, per kind of Clear (the slide's own background keeps playing under Blackout, Clear words and Clear all, and is closed under Clear background and Stop):
  - Blackout: objects held (FIX-X, unchanged).
  - Clear (words): objects held, silenced, nothing opened or waited for. The slide's own background keeps playing under it.
  - Clear all: the same show state as Clear, so held. (It also stops the foreground clip, unrelated to objects.)
  - Clear background: NOT held, and no change needed. The slide layer stays on air, so the objects are still in the composed scene and their players are untouched. The background's own player closes under it; objects are not the background.
  - Stop: nothing is live, so nothing is held and every object player closes (unchanged). A slide leaving Live also closes its clips.
- Failing test (old code): `theHoldRuleMatchesWhereTheSlidesOwnBackgroundKeepsPlaying` (Clear and Clear all not held).
- Change: pure rule `ObjectVideoPlayers.holds(_ state: ShowState)` = `isBlackedOut || isCleared`; `apply(_:hidden:)` (the FIX-X `apply(_:blackedOut:)` now forwards to it, so the FIX-X tests are untouched); `syncObjectVideos` uses `holds(show)`, and keeps the file access under a hold.
- A clip with sound is silenced while held (so a cleared object is not heard), and heard again on un-clear. The decision for you: under Clear words the slide's own background keeps its sound while objects are silenced. That follows "nothing visible, nothing heard" for objects; say if you want objects' sound to follow the background's instead.
- Not verified: hands-on 2.

## 3. REVIEW-5 L4: focusing and leaving a time field rounded the stored time: fixed
- Code did: `MarkRow.commit` and `MarkerRow.commitTime` parsed the one-decimal text on focus loss and wrote it when it differed from the stored value by more than 0.5 ms (12.37 became 12.4).
- Failing test (old rule): `FIXY_TimeFieldEditTests.leavingAFieldThatShowsTheRoundedTimeChangesNothing` (old rule gave `.set(12.4)`).
- Change: pure `TimeFieldEdit.edit(text:stored:emptyClears:)` (OperatorCore/MediaTimeText.swift): text equal to what the field shows for the stored time is `.unchanged`; a new typed value is `.set`; empty clears a mark (not a marker); garbage goes back. Both rows use it.
- Not verified: the views (hands-on 3).

## 4. REVIEW-5 L7: package import accepted what the store and model refuse: fixed
- Rules (the store and the model's): no marks or markers on a picture or a sound (the model refuses marks on a sound, the store on a picture, markers are only for video); no equal in and out (the model refuses `in >= out`); a reversed pair was already refused by the reader (`validateMarks`, whole package, nothing written) and still is (test).
- Failing tests (old code): `FIXY_MarksImportTests` equal marks, picture, sound, duplicate id in the package, duplicate id with the library, existing clip, hostile duplicates (7 of 8 failed; the reversed-marks test passes on old code because it was already refused).
- Change (ProgramPackage/ProgramImporter.swift, writer): equal marks are not imported and the result says so; marks and markers on a picture or sound are not imported and the result says so (counts included); a marker whose id is already used (by another marker of the package or by the library) is KEPT under a new id (was `INSERT OR IGNORE`, silently dropped) and the result says so; a clip that maps to an existing bin item keeps its own marks and markers, and its warning now says the package's marks and N markers were not added. The result text is `ProgramImportResult.warnings` (one sentence per asset, names cut to 80 characters and stripped of control characters). The later "marker action points at the existing clip" rewrite now uses the marker's final id.
- Bounded: a package of the permitted 1,000 markers with one id and a 100,000-character name gives all 1,000 markers, distinct ids, and fewer than 50 warnings of under 2,000 characters.
- Not changed, by design: merging a package's marks into an existing bin item (the existing entry is kept as it is, and the result says so).

## 5. REVIEW-5 L8: marker actions decoded on every tick and view body: fixed
- Failing test (old code): `FIXY_MarkerModelTests.actionsAreDecodedOnceWhenTheListLoadsNotOnEveryLookOrTick` (360 decodes for 40 ticks and 120 body-style lookups).
- Change: `MediaMarkerModel` decodes each marker's text once, when its clip's list is read or replaced (`setList`), and keeps the decoded actions and the feed's `[PlaybackMarker]` per clip. `actions(of:)`, `actionsAreUnreadable`, the tick and `needsObserver` read the cache. Test hooks `decodes` and `readsStarted`.
- Not measured: the real cost at 1,000 markers (no profile was run).

## 6. REVIEW-5 L10: marker list stale after Add while the first load is in flight: fixed
- Code did: `load` returned at once when a read of that clip was in flight, so Add's reload could be dropped and the older read applied.
- Failing test (old code): `aReadAskedForWhileTheFirstReadIsInFlightIsNotDropped` (one read started, not two).
- Change: every `load` reads; the newest read for a clip wins (a ticket per clip: an older read that returns later does not apply). `syncAssets` still skips a clip whose first read is in flight, so bin changes do not pile up reads.
- Not verified: the real interleaving (the test proves the request is no longer dropped and uses a pause on the main actor, not a concurrent pool read).

## 7. REVIEW-5 L11: "stored only" text: fixed in the source; data-dictionary text below
- Comments corrected: `Domain/SlideObject.swift` (text fit, background fill, video object, lock), `Domain/OutputRouting.swift` (`screenLookID`), `Domain/MediaAsset.swift` (marks), `Persistence/LibraryStore+SYS015.swift` (lock). `Domain/MediaLayers.swift` had no stale sentence (it already says the marks are read from the bin item).
- Data dictionary text (for `docs/19-data-dictionary.md`; I did not edit `docs/`):
  - `isLocked`: "The editor refuses to move, resize, nudge, align, edit or delete a locked object (UI-007c). A locked object is still drawn."
  - video content case: "A video object plays inside its frame while its slide is on a screen (looped and muted unless the object says otherwise), between the clip's in and out marks (FIX-Y). The Edit canvas and thumbnails draw its poster."
  - `backgroundFill`: "A colour drawn as a box behind the words inside a text object (UI-007c)." `fit`: "`shrinkToFit` shrinks the text until it fits the box, never below the floor (UI-007c)."
  - `screenLookID`: "The Look this screen follows on its own. Nil follows the show's Look. A screen with its own Look composes with it; changing the show's Look does not move it (UI-007f). A deleted Look clears the choice."
  - `mediaAsset.markIn/markOut`: "Honoured wherever the clip plays: layers, preview, a slide's own background, and video objects (FIX-Y). Marks on a picture or sound, and equal marks, are not imported from a package."
- Package format version (a decision for you, not changed): the format stays 1. A package that holds a `video` object cannot be decoded by a build from before SYS-015: it says "Something in it is missing or has the wrong shape" (a decode failure of the object's content), not "newer format", and nothing is imported. Marks and markers in a package are ignored by such a build without a warning (unknown manifest keys). My recommendation: raise `ProgramFormat.version` to 2 when the exporter writes a video object, a mark or a marker, so an older build says "newer format" instead. That is one constant plus a version-aware export and a reader test; it was outside this brief.

## 8. REVIEW-5 L14: a typed key note or chain label lost when the screen selection changes: fixed
- Code did: `CommitField` committed on Return and on focus loss; when the notes block was replaced (`.id(profile.id)`) while the field had focus, no focus-lost event was guaranteed.
- Failing test (old code): `FIXY_NoteDraftTests.theFieldCommitsWhenItGoesAwayAsWellAsOnReturnAndWhenLeft` (source rule; the field had no `.onDisappear`).
- Change: pure `NoteDraft.pending(draft:value:written:)` decides what is left to write, so Return, focus loss and disappearance never write the same text twice; `CommitField` also commits `.onDisappear`. The commit closure belongs to the screen the field was made for, so the note is written to that screen.
- Not verified: whether the old problem happened at all (it was "plausible"), and the new path by hand (hands-on 4). The test is a source rule plus the pure decision; it does not drive the view.

## 9. REVIEW-5 L15: Look text and delete: fixed
- Failing tests (old code): `FIXY_LookNoticesTests` panel text and view source (panel still said "every screen at once", Delete called `deleteLook` directly, Show had no note).
- Change: `LookNotices` (OperatorCore): `panelText` (now: "... changes every screen that follows the show's Look; a screen with a Look of its own (chosen in Screens) keeps it."), `ownLookNotice` (Show: one line under the Look buttons, "Own Look, not changed here: Lobby (Sermon), +N more"; takes no space when no screen has one), `deletePrompt`. Delete Look now asks in FIX-V's style (an alert: Cancel is the default and Return, the deleting button "Delete Look" has no destructive role so it is not red), names the screens that chose it ("will follow the show's Look again, at once"), says when it is the show's Look ("the show switches to another Look, at once"), and "This cannot be undone." The Look panel is shown in Screens (`ScreensMode.swift`), the note in Show's inspector (`ShowInspector.swift`, a small private view `OwnLookNote`).
- Not verified: the alert's default button and the note's wrap in the 299 pt inspector (hands-on 5). No design capture was run: the note appears only when a screen has its own Look.

## 10. REVIEW-5 L16: one hung volume blocked every later offline check: fixed
- Failing tests (old code, with a safety release of the stuck read so the old code failed instead of hanging): `FIXY_OfflineStallTests` all 4 (the check waited for the hung volume; six checks made six reads).
- Change (OperatorCore/MediaModel+Offline.swift, MediaOffline.swift): files are read volume by volume (`MediaOffline.volume(of:)`: "/Volumes/<name>", else "/"), each volume in one blocking read on a plain dispatch thread (`OfflineRead`, not the cooperative pool) with a stated limit, `MediaOffline.volumeReadLimit` = 8 s. A volume that does not answer is abandoned for that round: its files keep the marks they had, the other volumes are marked as usual, and the round is not a finished check (`lastOfflineCheck = nil`), so the next activation checks again. A volume whose earlier read is still out is not read again (one read at a time per volume, so a hung disk holds one thread however often a check is asked for); when that read ends, one more check runs. The summary (which asks `fileExists` on the mount point) is raced the same way. The FIX-V "one check at a time, one more after it" test passes unchanged.
- Not shown to the operator: an abandoned volume is silent (its marks are just old). A line in the Media callout ("the disk X did not answer") would need view work; not done. Say if you want it.
- Not verified: a real hung network volume (hands-on 6). The tests use a blocking closure.

## 11. REVIEW-4 L1: Identify screens not dismissed: fixed
- Failing test (old code): `FIXY_IdentifyDismissTests.theAppTakesThemDownWhenTheScreensOpenAndWhenTheListChanges` (source rule).
- Change: pure `ScreenIdentify.shouldDismiss(screensOpen:before:after:)`; `AppModel.openScreensNow` calls `ScreensIdentifier.shared.dismiss()`, and the signal map view dismisses when `app.profiles` changes or `screensOn` turns on. Still one cancellable task, nothing ticks while idle. Changes made while another mode is showing are not seen (the screen list is only edited in Screens).
- Not verified: hands-on 7.

## 12. REVIEW-4 L7: hiding the stage element the layout needs: fixed, by refusal (the smaller choice)
- Chosen: a refusal with a reason, no dialog (smaller: no new view state; the layout editor already shows `lastError`). Rule `StageEditing.hideRefusal`: the last visible Current slide cannot be hidden when no visible Next slide or Notes element is left, with "Could not hide the Current slide: the stage screen would show nothing from the show. Keep it visible, or add a Next slide or Notes element first." Any other element, any layout without a Current slide (Speaker, Clock only), and showing an element again are never refused. The built-in layout still says it cannot be changed. A layout that is already hidden entirely is not repaired.
- Failing test (old code): `FIXY_StageHideGuardTests` (5 of 6 failed before the change; the sixth is the no-Current-slide case that must stay allowed, and one test setup was corrected).
- Not verified: how the refusal looks in the stage editor (hands-on 8).

## Files changed
Sources (package): `Domain/MediaAsset.swift`, `Domain/OutputRouting.swift`, `Domain/SlideObject.swift`, `MediaEngine/UI007c_ObjectVideoPlayers.swift`, `OperatorCore/MediaMarkerModel.swift`, `OperatorCore/MediaModel+Offline.swift`, `OperatorCore/MediaModel.swift`, `OperatorCore/MediaOffline.swift`, `OperatorCore/MediaTimeText.swift`, `OperatorCore/StageEditing.swift`, `OperatorCore/UI006e_StageModelExtras.swift`, `OperatorCore/UI006f_ScreenListEditing.swift`, `Persistence/LibraryStore+SYS015.swift`, `ProgramPackage/ProgramImporter.swift`; new `OperatorCore/LookNotices.swift`, `OperatorCore/NoteDraft.swift` (all under `Packages/WorshipFlowKit/Sources/`).
App: `App/Sources/AppModel.swift`, `ControlPanels.swift`, `EditObjectVideos.swift`, `MediaMarksPopover.swift`, `ScreensMap.swift`, `ScreensNotes.swift`, `ShowInspector.swift`.
New tests (48, under `Packages/WorshipFlowKit/Tests/`): `MediaEngineTests/FIXY_ObjectVideoMarksAndClearTests.swift` (4), `OperatorCoreTests/FIXY_TimeFieldEditTests.swift` (6), `FIXY_MarkerModelTests.swift` (3), `FIXY_NoteDraftTests.swift` (6), `FIXY_LookNoticesTests.swift` (7), `FIXY_OfflineStallTests.swift` (4), `FIXY_IdentifyDismissTests.swift` (4), `FIXY_StageHideGuardTests.swift` (6), `ProgramPackageTests/FIXY_MarksImportTests.swift` (8). No existing test was edited; the four source-rule suites (FIXO, FIXQ, FIXS, FIXU) pass unchanged.
Out of scope files untouched: `ScenePreparationGate`, `MetalOutput`, `OutputRenderer`, `FrameEventLog`, `TickTimeline`, the SDI adapter, the scheduler, Fill/Key, `UISnapshot*`, `EditDesignCapture`, `ComponentsBoard`, `LooksProbe`.

## For the coordinator
Change log text: "FIX-Y: a video object plays between its clip's in and out marks; Clear and Clear all keep the video objects' players (silenced) as the slide's own background keeps playing, so lifting Clear does not restart the clips; leaving a mark or marker time field no longer rounds it to a tenth; importing a package no longer brings equal marks or marks and markers on a picture or sound, keeps a marker whose id was taken under a new id, and says in the result what was and was not kept; marker actions are decoded once per load; a marker list read asked for during another read is no longer dropped; a typed key note or chain label is kept when another screen is chosen; the Look help no longer says every screen changes at once, Show names the screens that keep their own Look, and deleting a Look asks first; one hung disk no longer stops the Media offline marks for other disks; Identify screens labels come down when the screens open or the screen list changes; the Current slide of a stage layout cannot be hidden when nothing else would show the show."
Known issues (unnumbered): (a) an offline check that gave up on a hung volume leaves that volume's marks as they were and says nothing; (b) a mark changed while a video object is on air takes effect at the next publish; (c) the package format version is still 1 though a package can hold a video object (older builds say "missing or wrong shape", not "newer format"); (d) Identify labels are not taken down when the operator only switches mode.
Remove from known issues: KI-280 (Clear restarts the objects' video).
Hands-on: (1) clip with marks 1 s to 2 s used as a video object: loops only inside the marks; change a mark on air, trigger the slide again. (2) video object live: Clear, wait, un-clear: mid-play, not frame 0; an unmuted object is silent while cleared; Clear background keeps the object playing; Stop closes it. (3) Mark in from the playhead (12.37), open the list, Tab through the In field and a marker time field: the time stays 00:12.4 as shown but the stored value is unchanged (check the marker does not move). (4) Type a key note, click another screen without Return, come back: the note is there; also a chain label. (5) Look panel text, Delete asks with Cancel default, no red; Show inspector line appears only when a screen has its own Look and wraps in the 299 pt column. (6) A hung network volume plus a USB disk with a bin file: the USB file's offline mark updates within about 8 s. (7) Identify screens, then Open screens: labels go at once; rename a screen while they show. (8) Stage editor: hide the only Current slide: refused with the sentence; add Next slide, then it hides. (9) Import a program with equal marks / a picture with marks / a duplicate marker id: read the result's warnings.
Decisions for you: (a) the package format version (item 7); (b) whether objects' sound under Clear words should follow the background's (item 2); (c) whether an abandoned volume should be shown in the Media callout (item 10).

## Verification
- Each new test was first run against the old behaviour and failed for the reason stated above (pure functions and new API were added as old-behaviour stubs or checked through source rules where the old code had no such name).
- `./scripts/check.sh`: first full run exit 1: the four new `FIXY_OfflineStallTests` failed in the full run (a timing assumption of mine: they asserted a wall-clock bound and used a 6 s safety release; under the whole package's load the abandon timer was late). The code was right (they pass alone and in `OperatorCoreTests`). I changed the tests to assert on the state (the check returned while the stuck read was still stuck) with a 45 s safety release.
- Second full run: package tests 3639 tests in 579 suites passed (3591 before FIX-Y, +48), reached "== OK"; I did not read its exit status (it was run inside a pipeline).
- Third full run (final tree), exit status read by the script's own `EXIT=$?`: `./scripts/check.sh` exit 0, package tests passed, Debug and Release app builds passed, "== OK".
- Swift 6 strict concurrency: Debug and Release app builds are part of the script; no new warning in the changed files (the warnings in `AppModel.swift:1374` and `CuesActionList.swift:202` are older).
- Scratch: only the script's own DerivedData folders (`WORSHIPFLOW-check`, `WORSHIPFLOW-check-release`) were used; no other build was made and no `.app` was copied anywhere. The owner's library, `/Applications/WorshipFlow.app` and the running app were not touched; no soak, no process started.
