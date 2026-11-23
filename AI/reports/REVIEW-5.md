# Independent review, fifth pass: findings

Range reviewed: 8590d5a to fb41ae2 (SYS-015, FIX-V, FIX-U, UI-007c, UI-007d, UI-007e, UI-007f, UI-008, OUT-002b to OUT-002e). Three reviewers read the code only; nothing was built or run, and no git state was changed. The three part files are kept beside this one: REVIEW-5-part-A.md, REVIEW-5-part-B.md and REVIEW-5-part-C.md.

Confidence words: "confirmed" means the path was read end to end. "Plausible" means the path exists but a timing, platform or input condition was not established.

Count: 0 high, 6 medium, 23 low.

## High

None found.

## Medium

### M1. A marker crossed in the last moment before a pause, a Stop or the clip's end is lost (part B M1)
- Where: `OperatorCore/MediaMarkerModel.swift:242-249` (`refresh`), `:252-264` (`tick`), `:234-239` (`needsObserver`).
- The observer is only needed while a layer `isPlaying`. When the layer pauses, ends or is cleared, `refresh()` stops the timer and calls `feed.reset()` at once. There is no last `tick()` first. The timer fires every 50 ms, so anything the playhead crossed since the last tick is never looked at.
- Scenario 1: a non-looping clip has a marker at (or within 50 ms of) its end or out mark ("lower third off", "prop off"). The clip ends between two ticks. `playerReportedEnd` takes the layer away, `refresh()` stops the observer, the marker never runs.
- Scenario 2: the operator pauses 20 ms after a marker's time but before the next tick. Nothing fires. On resume the feed starts a new pass from the playhead (`poll`, first branch) and arms only markers at or after it, so the marker is skipped for good.
- The test `UI007d_MarkerModelTests.aClipThatEndedStopsTheObserver` (line 153) advances the clock 11 s over a marker at 4 s with no tick in between and only asserts the observer stopped. It does not notice that the marker never ran.
- Confidence: confirmed for the end of a clip and for pause; the size of the window is the tick interval plus any main-thread delay.
- Fix idea: `refresh()` takes one more `tick()` before it stops, with the position clamped to the end.

### M2. Removing a mirror leaves the new key notes and signal chains on the wrong destination (part B M2)
- Where: `OperatorCore/ScreenEditing.swift:135-142` (`removingMirror`), against `Domain/OutputRouting.swift` (`connectedToKey`, `signalChains`, both indexed like `connectedTo`, 0 for the primary and n + 1 for mirror n).
- `removingMirror` removes entry `index + 1` from `connectedTo` so notes stay aligned. It was not changed by SYS-015 and does not touch `connectedToKey` or `signalChains`. After removing mirror 0 of two, the surviving mirror (now index 0, array position 1) shows the removed mirror's key note and chain, and its own are left past the end.
- Scenario: a Fill and Key setup with two mirrors, each with a typed chain ("enclosure, converter to ATEM input 5") and a key note. The operator removes the first mirror. The Screens signal map now describes the second mirror with the first one's wiring, marked "typed by you". For a broadcast Fill and Key path this can send someone to the wrong cable.
- Confidence: confirmed by reading; no other place shifts these arrays (`git grep signalChains connectedToKey`). No test removes a mirror with a key note or chain.
- Also found independently by the interface reviewer (part C M1), who adds: switching a destination from Fill and Key to plain leaves its key note stored but hidden; it comes back if keying is turned on again.

### M3. An imported marker that selects a Look keeps the package's Look id even when that Look was imported under a new id (part B M3)
- Where: `ProgramPackage/ProgramImporter.swift:210-219` (the marker remap, inside `if !assetIDMap.isEmpty`), against `ProgramImportPlan.swift:176` and `:248` (`plan.lookMap`, applied to slide actions only).
- The export follows a marker's actions to the Looks they select and ships those Looks (`ProgramExporter.swift`, the marker loop calls `references.add`). On import a Look that conflicts and is kept beside the existing one (`keepBoth`, or "in use on the live show") gets a new id. Slide actions are rewritten with `lookMap`. Marker actions are rewritten with `assetIDMap` only, and only when that map is not empty.
- Scenario: the library has a Look "Worship" with the same id but different content. The operator imports a program with "keep both". The slide actions select the imported copy. The clip's marker still selects the id of the library's own "Worship". When the clip plays live, the marker puts the wrong Look on the screens.
- Confidence: confirmed by reading. `aMarkerActionIsPointedAtTheExistingBinEntryWhenTheLibraryAlreadyHasThatClip` covers assets only; no test covers a marker and a renamed Look. The data dictionary says a marker's Look "comes along", which is true for the file but not for the id.

### M4. Video objects: a clip that fails to open, or is the fifth, draws nothing on air and is reported nowhere in the app (part B M4)
- Where: `App/Sources/EditObjectVideos.swift:103-114` (`syncObjectVideos`), `MediaEngine/UI007c_ObjectVideoPlayers.swift` (`unavailableAssetIDs`, `skippedAssetIDs`, `setOnAvailabilityChange`).
- The player set records failures, unhealthy players and clips beyond `limit` (4). `git grep` shows the app never reads `objectVideos.unavailableAssetIDs` or `skippedAssetIDs` and never sets `setOnAvailabilityChange` on it (only the capture code at `EditUI007cCapture.swift:79` reads it). The registry's own `unavailableAssetIDs` (read by the 0.2 s ticker, `AppModel.swift:1155`) is the layer slots only.
- Scenario: a slide with a video object whose file is on an external disk that was unplugged, or a slide with five clips. The service starts; the video area is empty; Show shows no warning. KI-239 says a missing clip is "reported only in the inspector", which only covers a clip that left the bin, not one that is in the bin and cannot be opened or decoded.
- Confidence: confirmed that nothing in the app reads it.

### M5. Edit's Broadcast and Stage previews ignore the screen's own Look (part C M2)
- Where: `App/Sources/EditCanvasChrome.swift:44` (calls `EditPreviewScene.scene(... look: currentLook ...)` with no per-screen Looks); `Packages/WorshipFlowKit/Sources/OperatorCore/UI006c_EditFeatures.swift:127-137` (the function has no `screenLooks` parameter and builds `PublishedScenes` without one).
- The audience preview goes through `thumbnailScene`, which was changed to pass `screenLooks: screenLookOverrides` (`AppModel.swift:543-545`), so the audience canvas is right. The other two roles in Edit are composed with the show's Look only.
- Scenario: the broadcast screen has its own Look "Lower third" while the show's Look is "Worship". In Edit the operator presses Broadcast to check a slide. The canvas draws it with Worship's theme and layers for that screen, not the Look the broadcast output will use. The caption says it is the screen's scene. For a stage screen the same gap changes which props sit on the preview.
- This is the same kind of mistake as REVIEW-4 M1 (a preview that is not the screen's real scene), now for the new per-screen Look. The M1 test (`FIXV_EditStagePreviewTests`) compares preview and real scene with no Look at all (`look: nil`), so it cannot see this.
- Confidence: confirmed by reading.

### M6. The preparation gate covers lyric text and images only, not slide objects (part A M1)
- Where: `OutputEngine/ScenePreparationGate.swift:18-23` (`needsWork` looks at `incoming.textLayers` and `incoming.imagePaths` only), `RenderEngine/TextStores.swift:132-138` (`TextWarmer.warmNow` calls `layoutReport`), `RenderEngine/Compositor.swift:757` (`layoutReport` places `scene.textLayers` only), `Compositor.swift:288-299` and `:392` (a text object's fit is computed at draw time), `Compositor.swift:769-` (shape bitmaps rasterised at draw time).
- Scenario: the operator goes live on a slide whose new content is a text box, a shape, or a text box with "Shrink to fit box" (UI-007c). Nothing in `textLayers` or `imagePaths` is new, so `needsWork` returns false and the scene is adopted at once. The text object's Core Text layout and its fit measure, and any new shape bitmap, then run on the render thread at the first frame. That is the same 30 ms first-use cost OUT-002c was written to remove. Text objects are never put in `SharedTextStore` because only the warmer publishes rasters, and the warmer never lays them out.
- Evidence the soak could not show this: the soak deck (`App/Sources/SoakConfig.swift`, copied in `OUT002c_SoakDeckTests`) has lyric lines only. The test asserts `objectFitComputationCount == 0`, which is trivially true when the deck has no text objects.
- Confidence: confirmed that the gate and the warmer skip objects. Whether a refresh is dropped on a real slide is plausible, not measured.

## Low

### L1. A video object's failure flag is never cleared when the clip opens on a later attempt (part B L1)
- Where: `MediaEngine/UI007c_ObjectVideoPlayers.swift:89` (`failedIDs = failedIDs.intersection(wanted.keys).union(failed)`).
- A clip that failed is retried at every `apply`. If it opens now, it is in `opened`, but its id stays in `failedIDs` while it stays wanted, so `unavailableAssetIDs` goes on reporting it. It clears only when the clip leaves the requests.
- Scenario: a disk is plugged back in; the clip plays; the unavailable flag stays. Harmless today because nothing reads it (M4); wrong the day M4 is fixed. No test covers recovery.
- Confidence: confirmed.

### L2. A video object ignores the bin item's in and out marks (part B L2)
- Where: `ObjectVideoRequest` (no marks) and `ObjectVideoPlayers.apply`, which builds `VideoPlayerSource(url:loops:duration:muted:)` without `markIn` or `markOut`.
- Every other place that plays a bin clip honours its marks (layers, preview, a slide's own background). The Mark in help text says "Play from the playhead". A clip used as a video object plays whole. Not in the known issues (KI-239 to KI-245).
- Confidence: confirmed. It may be intended; it should be written down.

### L3. Blackout (or any publish that removes the objects) closes the video players, and lifting it reopens them from the first frame (part B L3)
- Where: `AppModel.publish()` calls `syncObjectVideos` on every publish; under Blackout or Stop the composed scene has no `objectLayers`, so `apply([])` closes every clip. On lift they open again, start from 0 and draw nothing until a frame arrives.
- Scenario: a video object on the live slide, Blackout then lift: the video restarts and the box is empty for the first frames. The slide's own background does not do this (Blackout keeps that player).
- Confidence: plausible (depends on the composer returning no objects under Blackout, which the early return in `SceneComposer` suggests; I did not trace the Blackout branch to the line).

### L4. Focusing and leaving a time field rounds the stored time to a tenth of a second (part B L4)
- Where: `App/Sources/MediaMarksPopover.swift:137-143` (`MarkRow.commit`) and `:175-178` (`MarkerRow.commitTime`), both run on focus loss.
- The field shows `MediaTimeText.format` (one decimal). On focus loss it parses that text and compares with the stored value. A mark or marker set from the playhead at 12.37 reads "00:12.4" in the field; leaving the field writes 12.4 (the difference 0.03 s is over the 0.0005 s tolerance). A marker moves up to 50 ms, and a mark in moves its first frame.
- KI-249 says stored times keep precision typed; the focus round-trip does not.
- Confidence: confirmed.

### L5. Pause then resume can run a marker twice (part B L5)
- Where: `MarkerFeed.poll` first branch and `MarkerTracker.start(at:)` (`CueEngine/PlaybackMarker.swift`, arms markers with `time >= position - tolerance`), together with the reset in M1.
- A marker fires when the playhead is within half a frame (8 ms) before its time. The observer then stops at pause and the feed forgets the layer. On resume `start(at: p)` re-arms any marker at or after `p - 8 ms`. If the clip was paused within about 8 ms after the marker fired, the marker runs again on resume.
- The tracker's own rule "landing on a marker counts as being past it" applies to a seek; the model's pause-reset path does not apply it.
- Confidence: plausible (a narrow window).

### L6. The v15 backup is skipped silently when the library's history cannot be read (part B L6)
- Where: `Persistence/LibraryStore+Backup.swift:60` and `:62-64`. `try? DatabaseQueue(...)` and `try? source.read` return early with no backup when the read-only open or the history query fails. The migration then runs.
- ADR-0009 decision 4 says a library that cannot be copied is not opened. That holds only when the copy is attempted; a library that cannot be read read-only (a hot `-wal` file after a crash on a read-only folder, a locked file) takes no copy and still migrates.
- The same pattern is in the older `newerMigration` guard (`LibraryStore.swift:77-81`). The test `whenTheCopyCannotBeWrittenNothingIsMigrated` covers a blocked `Backups` folder only.
- Confidence: plausible.

### L7. Package import accepts marks that the store and the model refuse (part B L7)
- Where: `ProgramPackage/ProgramReader.swift:157-175` (`validateMarks`), `ProgramImporter.swift:196-200`.
- `MediaMarks.isValid` allows `markIn == markOut`. The store (`setMediaMarks`) refuses marks on a picture; the model refuses `markIn >= markOut` and marks on a sound. The importer applies none of these three: a package can bring an image with marks and markers, a clip with equal marks (the transport ignores both, but the strip says "In 5.0 · Out 5.0"), or markers on a sound (never played). Nothing is lost or unsafe; the data is not what the app can write.
- Also, `INSERT OR IGNORE INTO mediaMarker` (`:203`) drops a marker whose id already exists in the library without a word, and a clip that maps to an existing bin item (`assetIDMap`) brings neither its marks nor its markers (the existing item is kept as it is, with a warning about the file only).
- Confidence: confirmed.

### L8. Marker actions are decoded on every observer tick and on every view body (part B L8)
- Where: `MediaMarkerModel.playbackMarkers` (`:224`, called twice per slot per tick at 20 Hz on the main actor, decoding each marker's JSON), `actions(of:)` and `actionsAreUnreadable` (`:134-143`, scan all clips and decode), used per row at `CuesMarkers.swift:116` and `MediaMarksPopover.swift:98`.
- With a normal clip (a handful of markers) this is cheap. A clip at the permitted 1,000 markers, or an imported one with large actions (up to 64 KiB each), makes each tick and each redraw do thousands of JSON decodes on the main thread, with `feed.poll` also comparing the whole marker array by value each tick.
- Confidence: plausible (limit case; not measured).

### L9. Deleting a marker has no confirmation and no undo (part B L9)
- Where: `App/Sources/MediaMarksPopover.swift:168`. The trash button calls `markers.delete` directly. A marker holds the actions the operator built in Cues; they go with it. Deleting a media item also cascades to its markers (`mediaMarker.assetID ... ON DELETE CASCADE`, tested) with no word about the markers lost.
- Confidence: confirmed (check whether the media-item delete confirmation names markers; I read the marker side only).

### L10. A marker list can read stale after Add while the first load is still in flight (part B L10)
- Where: `MediaMarkerModel.load` (`:148-155`): `guard !loading.contains(assetID) else { return }`. `add` inserts, then `await load`; if `syncAssets` has a read of that asset in flight, the second `load` returns at once and the in-flight read may predate the insert.
- The list and the armed markers miss the new marker until the next reload. Narrow: `syncAssets` only loads an asset with no list yet.
- Confidence: plausible.

### L11. The data dictionary still describes fields as "stored only" that are now honoured (part B L11)
- Where: `docs/19-data-dictionary.md`, rows for `isLocked` ("the editor honouring it is later work"), the video content case ("nothing draws it yet"), `backgroundFill` ("Stored only"), `screenLookID` ("Stored only"); and `Domain/OutputRouting.swift`, `Domain/SlideObject.swift` and `Domain/MediaLayers.swift` comments say the same for `screenLookID`, `isLocked`, `fit` and `backgroundFill`. UI-007c and UI-007f make them live. The schema columns themselves agree with the dictionary (`mediaAsset.markIn/markOut`, `mediaMarker` with its seven columns and index, checked against `Schema.swift`).
- The format version of the program package stays 1 although a package can now hold a `video` object an older build cannot decode: the older build says "Something in it is missing or has the wrong shape", not "newer format". Marks and markers in a package are ignored by an older build without a warning.
- Confidence: confirmed.

### L12. Edit's Stage preview leaves out the section names, so a Section element draws nothing there (part C L1)
- Where: `OperatorCore/UI006c_EditFeatures.swift:158-170` (`previewState` builds `ShowDeck(presentationID:slides:)` with no `sectionNames`), called by the stage branch added for FIX-V M1.
- The live deck is built with `sectionNames` (`WorkspaceModel.swift:349-350`). The preview deck is not. A stage layout that has the new Section or Next section element therefore shows neither in Edit's Stage preview, while the real stage screen does.
- The M1 test hides this: `FIXV_EditStagePreviewTests.real(...)` (line 25) builds its own deck without `sectionNames`, so preview and "real" agree in the test and differ in the app.
- Confidence: confirmed by reading.

### L13. A marker is deleted with one click and no confirmation (part C L2)
- Where: `App/Sources/MediaMarksPopover.swift:168` (`markers.delete(marker.id)` from a trash icon).
- Deleting a marker also deletes the list of cue actions stored on it, and there is no undo. The project rule is that no destructive action goes without confirmation. The button carries `role: .destructive`, but the custom button style does not draw it red, so the colour rule is kept; the confirmation rule is not.
- Confidence: confirmed by reading.

### L14. A typed note can be lost when the screen selection changes while its field is still focused (part C L3)
- Where: `App/Sources/ScreensNotes.swift:153-175` (`CommitField` commits on Return or when focus is lost), with `ScreensDetail.swift:40` giving the whole notes block `.id(profile.id)`.
- The older "Connected to" field writes on every keystroke. The new key note and chain label keep a draft and write only on Return or focus loss. On macOS a click on a plain SwiftUI row does not always take focus out of a text field. If the operator types a note and clicks another screen in the list, the notes block is replaced by one with a new id, and the draft may be dropped with no focus-lost event.
- Confidence: plausible (depends on whether the focus change fires before the view is removed). Hands-on item 3 below settles it.

### L15. Look controls still say a Look applies to every screen, and nothing in Show says a screen keeps its own (part C L4)
- Where: `App/Sources/ControlPanels.swift:501` and `:520` ("Switching Look changes every screen at once"); `ShowInspector.swift:118` and `:131` (the Look buttons); `ControlPanels.swift:514` (Delete, no confirmation).
- After UI-007f a screen with its own Look does not change when the show's Look changes (by design, `ScreenLooks.overrides`). The only place that says so is Screens (the list row and the notes block). The Look panel text is now wrong, and in Show the operator picks a Look and one audience screen silently stays on another. Deleting a Look (also unconfirmed, as before) now sends every screen that chose it back to the show's Look at once, which can be on air.
- Confidence: confirmed by reading. The behaviour is as designed; the words and the missing hint are the defect.

### L16. One stalled volume can block every later offline check (part C L5)
- Where: `OperatorCore/MediaModel+Offline.swift:15-16` (`offlineRunning`).
- The FIX-V L8 fix allows only one check at a time and never cancels it. If that check is stuck reading a hung network volume, `offlineRunning` stays true, so every later request, including the one after a different disk is plugged in, only sets `offlineAgain` and never runs. The offline marks then stay as they were until the app restarts. This is the cost of the L8 fix, which removed the pile-up of threads.
- Confidence: plausible (needs a volume that hangs rather than fails).

### L17. A scene that is already prepared is still held at least one frame, and a new `Compositor` is built for each request (part A L1)
- Where: `ScenePreparationGate.swift:18-23`, `:63-84`; `TextStores.swift:133`.
- `needsWork` compares only with the scene on screen. It does not ask the shared stores whether the words and images are already there. The app already warms the Preview slide ahead of Go Live (FIX-J), so the usual slide is warm. Even so, every scene with new words is sent to the background queue. `isReady` is read on the same tick (`:81`) when the worker has not run yet, so the old scene is drawn for that frame. In practice every normal slide change, and every return from Blackout to a slide, is shown one frame later than before (about 17 ms at 60 Hz) on each output. The worker also makes a new `Compositor()` (Metal device, queue, sampler, texture) for every request.
- No wrong output; it is added latency on the common path that the brief for OUT-002c does not mention. Confirmed by reading; the size depends on how fast the worker starts, not measured.

### L18. The stage Blackout scene is not blank, so the gate holds it; the file's comment says Blackout is never held (part A L2)
- Where: `Domain/SceneComposer.swift:180`, `Domain/StageLayout.swift:365-370` (`blackoutLayer`, a "BLACKOUT" text layer added on top of the stage's normal layers); `ScenePreparationGate.swift:6-7` (comment) and `:18-23`.
- Audience and broadcast Blackout are blank scenes (`SceneComposer.swift:83-86`), so `needsWork` is false and they are drawn at once. A stage screen keeps its lyrics and adds a new non-ticking "BLACKOUT" layer. That layer is not in the scene on screen, so `needsWork` is true and the stage keeps showing the old scene for up to 3 frames (one frame at least, see L17) before the warning appears. The test `blackoutAndClearNeverWait...` uses a hand-made empty scene (`OUT002c_ScenePreparationTests.swift:29`), not the stage composer's.
- Impact is small (stage confidence screen, tens of milliseconds, and the warning text is one fixed string). The rule "Blackout never waits" is true only for screens whose Blackout is blank. Confirmed.

### L19. Refresh rate, frame-rate range and the frame target are updated only when the screen parameters change, not when a window moves to another display (part A L3)
- Where: `OutputEngine/MetalOutput.swift:161-166` (`didChangeScreenNotification` only reconciles geometry) against `:167-180` (the only place `refreshRate`, `setTargetInterval` and `link.preferredFrameRateRange` are changed after start).
- Scenario: a window-destination output (not the pinned display outputs) is dragged from a 60 Hz display to a 120 Hz one, or the reverse. `didChangeScreenParametersNotification` is not sent for a window move. The link range stays at the old rate (`min = max = preferred`, `:142`, `frameRateRange(hz:)`), and `statistics.targetInterval` stays at the old interval. Moving from 120 Hz to 60 Hz leaves the target at 8.3 ms, so every presented frame at 16.7 ms is counted as one dropped and late frame in the Screens readout and the soak totals. Output only; the picture is not wrong. Whether the link follows the window's display by itself is not stated in the header (hands-on item 4). Confirmed for the statistics; plausible for the link.

### L20. A preparation that never returns makes every later new scene wait the full 3 frames (part A L4)
- Where: `ScenePreparationGate.swift:138-148` (`drain` runs `warm` with no time limit), `:129-136`.
- The wait for one scene is bounded (`held >= maxHeldFrames`, `:81`), so the gate cannot hold for ever, and `done()` is never needed to leave the hold. If `warm` blocks (an image on a stalled network volume: `SharedImageStore.load` stats and decodes the file), the one worker of that output stays busy, `workerScheduled` stays true, and later requests only replace `latest`. From then on each new scene with new words is held for the full 3 frames and then drawn unprepared, so the gate adds delay and no benefit. Each output has its own preparer and so its own worker; N outputs can warm the same text at the same time, because the shared stores do not merge work in progress (wasted time, not unsafe). Plausible: needs a stalled read.

### L21. Outputs no longer switch on the same frame (part A L5)
- Where: `OutputRenderer.swift:42-45`, `:118` (one gate per output renderer).
- Each audience, stage and broadcast output decides alone when its new scene is ready. A slide change that needs preparation can appear on one output up to 3 frames before another (50 ms at 60 Hz). Before OUT-002c the outputs already ran on separate links, so they were never locked to each other; the difference is that the offset can now be a whole number of held frames. Not wrong for lyrics; it matters if the broadcast feed must change with the projector. Confirmed by reading.

### L22. A text object with a fit floor allocates and hashes on every frame (part A L6)
- Where: `RenderEngine/Compositor.swift:288-299` (`objectFitStatus` builds a `FitKey` with a one-element array and hashes the text and style on each call; no "same as last frame" shortcut as the lyric path has at `Compositor.swift:272-275`), called every frame from `:392`.
- Scenario: a slide with one or more text boxes using "Shrink to fit box" costs an array allocation and string and style hashing per box per frame on the render thread. Small per frame; it breaks the stated rule for the live path (no allocation per frame). Confirmed by reading.

### L23. The "callback lateness" rule uses `targetTimestamp` as if it were the time the callback was due; the header does not say so (part A L7)
- Where: `MetalOutput.swift:36` (`update.targetTimestamp` is passed as `linkTimestamp`), `OutputEngine/TickTimeline.swift` (`FrameLateness.classify`, second branch: tick start minus `linkTimestamp` over 1.5 periods is "app late"), `margin` (`linkTarget - (start + work)`).
- If `targetTimestamp` is a time in the future (as `CADisplayLink.targetTimestamp` is), the difference is negative and that branch never fires; the "app late" class is then decided only by the gap between tick starts. If it is the due time of the callback, the rule is right. The header does not define it, and the test `aCallbackFarAfterTheLinksOwnTimestampIsAppLate` feeds values chosen to match the assumption. The reported class split in the 60-minute soak ("late callbacks") depends on this. Plausible; a real run's `cb` figures would settle it (a steady negative `cb` means it is a future time).

## Coordinator's check of the medium findings

The coordinator read the code for these before accepting them. Mirror removal: confirmed, `ScreenEditing.removingMirror` (OperatorCore/ScreenEditing.swift:135-142) shifts `connectedTo` only. Video object failures not shown: confirmed, the app reads `mediaRegistry.unavailableAssetIDs` (App/Sources/AppModel.swift:1155) but nothing in App/Sources reads the object players' `unavailableAssetIDs` or `skippedAssetIDs` outside the capture hook. Preparation gate: confirmed, `ScenePreparationGate.needsWork` (lines 18-22) compares `textLayers` and `imagePaths` only. Look map on import: `ProgramImportPlan.swift:248` applies `lookMap` to slide actions; the marker path was not re-read by the coordinator. Marker in the last 50 ms and the Edit preview's Look: not re-read by the coordinator; they stand on the reviewer's reading.

## Review-4 findings: fixed, partly fixed or still open

- M1 (Edit Stage preview not the stage screen's layout): partly fixed. `EditPreviewScene.scene(... stage:, deck:, index:, notes:)` passes the stage screen's own scene (`UI006c_EditFeatures.swift:127-156`, `EditCanvasChrome.swift:40-52`); layout, Hide, Auto-fit, next line and notes (stage role only) now match. Two gaps remain: section names (L12 above) and the screen's own Look (M5 above). Notes reach only the stage role; the audience and broadcast previews are given none (confirmed by `stageScene` being built only for `role == .stage`).
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
- L8 (offline check blocks threads): partly fixed. One check at a time, and activation checks only after a change or 60 seconds (`MediaOffline.shouldCheckOnActivation`). The cost is L16 above.
- L9 (red confirmation buttons): partly fixed. The three named sites (Remove screen, Delete collection, Delete element) no longer use `role: .destructive`. Many other dialogs still do (for example `CentrePane.swift:172`, `MediaBinPanel.swift:83`, `LibrarySidebar.swift:80`, `ThemeEditorSheet.swift:51`, `StageEditorView.swift:60`, `SectionOrderSheet.swift:44`, `CuesEditors.swift:29`, `:202`, `CuesControlInputs.swift:216`, `ScriptureTranslationsView.swift:56`). Cosmetic, as in REVIEW-4.
- REVIEW-4 note on `Delete collection` line: the first FIX-V commit (`5c80e68`) left the action inside a line comment; `df075aa` repaired it, and the line at `MediaMode.swift:124` is correct in the final tree.

## Tests that do not test, or test less than they say

### Output path

- `OUT002d_TickRecordTests.aRenderedTickLeavesOneRecordOfItsPhases` (`:337`): returns without any expectation when no drawable can be had (`guard layer.nextDrawable() != nil else { return }`), so on a machine without a display it passes asserting nothing. When it does run, it takes a drawable first and then calls `tick` with no `drawable:`, so it exercises the old `layer.nextDrawable()` fallback, not the new path where the link hands the drawable in.
- Nothing tests the new link wiring: `MetalLinkTarget`, `MetalOutput.start` and `finish` (link added, invalidated, delegate released), `frameRateRange(hz:)`, `preferredFrameLatency`, the use of the given drawable's own texture size (`OutputRenderer.swift:103`), or that the two-frames-on-GPU guard still skips when the drawable is given. A headless test cannot make a `CAMetalDrawable`, so this is hands-on only, but the brief's "look hardest" list is entirely in this untested part.
- `OUT002c_SoakDeckTests` holds its own copy of the six soak lines ("the same six lines as ... SoakConfig.swift"). If the soak deck changes the test does not follow. Its zero-cost assertions use a synchronous preparer and `renderImage`, never the real `BackgroundScenePreparer` with threads, and never a scene with text objects (see M6).
- `OUT002c_ScenePreparationTests`: the gate cases (order, cancel, late finish, bound, Blackout) fail if the logic breaks and use injected completions, which is right. Missing: no test that uses the real `BackgroundScenePreparer` together with the gate on real threads; no test that holds the stage composer's Blackout scene (L18).
- `FIXV_RetiredOutputTests.afterManyOpenAndCloseCycles...` uses fake targets that report `isTearingDown == false`. It proves the coordinator keeps nothing, but not that a real `MetalOutput` (window, layer, link, renderer) is released. The `SlowTarget` tests are sound and fail if `retire`, `releaseFinishedTargets` or the waiting stop change.
- `OUT002d` classification tests (slow, late, presented late, skipped, window edges, marks, caps) assert on injected numbers and would fail if the rule or its order changed. They cannot show whether the numbers the renderer records mean what the rule assumes (L23).
- `OUT002b_DropTimesTests` and `OUT002e_TickMarginTests` are pure and real; they would fail if the cap, split or margin arithmetic changed.

### Data and media

New test files in this part and whether they would fail if the named behaviour broke:

- `SYS015_MigrationTests`: real v14 file built step by step, row-by-row dump compared before and after, FK check, run twice, fresh library same shape, copy opens as v14 and has no `markIn`, blocked `Backups` folder gives `MigrationBackupFailed` and leaves v14, unknown step `v16` refused with no copy. Strong. Missing: unreadable history (L6); a library with many rows.
- `SYS015_StoreTests`: mark and marker bounds (NaN, negative, beyond length, in after out, a picture, the 1,000 limit), refusal changes nothing, ordering, cascade through the store, screen fields and Look deletion clearing screens. Strong.
- `SYS015_ProgramTests`: hostile marks, marker times, action text, count, bounded names, video object with no clip in the package, existing-bin remap for a video object and for a marker's clip. Missing: marker with a Look that is imported as a copy (M3), `markIn == markOut`, a marker on a picture, duplicate marker ids.
- `UI007d_MarkerFeedTests` and `UI007d_MarkerModelTests`: fire once, several in order, in-mark, after out mark, seek forward and back, one-frame jitter, loop wrap with a marker at the out mark, clip started again, another clip, marker added or moved while playing, hardware test refusal, the one command path, show-moving action refused at save and again at fire (including through a macro), nothing ticks while idle or for a clip without markers. Good coverage of the feed. `aClipThatEndedStopsTheObserver` and `aPausedClipFiresNothing...` pin the observer lifecycle and do not catch M1 or L5 (the feed test keeps the feed across a pause; the model drops it).
- `UI007d_MediaMarksModelTests`, `UI007d_PreviewMarksTests`, `UI007d_MediaTransportMarksTests`, `UI007d_PlayerMarksTests` (real player, in mark first frame, out mark and end reported once, loop inside marks): they would fail if marks were not honoured. Marks and a video object (L2) are not tested together.
- `UI007c_ObjectVideoPlayersTests`: opens, closes, reopens on change, limit of 4 with the rest reported, missing file reported while the others play. Missing: recovery after a failure (L1); a clip shared by two scenes.
- `UI007c_EditObjectsTests`, `UI007c_ObjectSceneTests`, `UI007c_ObjectFramesTests`, `UI007c_ObjectRenderTests`, `UI007c_RenderDigestTests`, `SYS015_ScenesDigestTests`, `SYS015_FieldsTests`, `SYS015_EditorTests`: lock refuses move, resize, nudge, align and delete by every path; hidden objects are not in the scene and a hidden video is not asked for; no new value gives the same scene bytes (digests pinned). Sound. A hidden object is dropped in exactly one place (`SlideObject.drawableLayers`, called once from `SceneComposer`), so Preview, Live, thumbnails and broadcast all agree; stage never draws slide objects.
- No test removes a mirror with a key note or chain (M2).
- Nothing in these files asserts nothing or tests a copy of the logic that I could find.

### Interface and fixes

For each new test file in this part:

- `FIXV_MacroKeyRoutingTests`: real. Would fail if M5 regressed in `KeyRouting`. Does not test `AppModel`'s call (window, modal, mode arguments).
- `FIXV_RemoveScreenTests`: real for the rules, the model and `forgetScreen`. Missing: removal against a running coordinator, and `activeOutputIDs` (REVIEW-4 listed this as untested; it still is).
- `FIXV_SectionOrderTests`: real. Two `async let` calls reproduce the review's case, and a repeated section is covered.
- `FIXV_RetiredOutputTests`: real for the coordinator's list with fake targets. The weak-reference loop proves nothing is held; it does not prove a real `MetalOutput` is freed.
- `FIXV_EditStagePreviewTests`: real for layout, Hide, Auto-fit, next line, notes and the draft slide. It uses `look: nil`, and its `real(...)` builds a deck without section names (M5, L12).
- `FIXV_LowFindingsTests`: real; the one-at-a-time offline test blocks a real read and counts. Not covered: a check that never returns (L16).
- `FIXU_ViewSourceTests`: reads source text. It fails if someone moves a read back into `WorkspaceView`, `ShowInspector` or `TransportBar`, and passes if a new read is added under another name. It cannot see how often a body runs; the report says the real numbers came from a script. Same limits as the REVIEW-4 source-text tests, which are unchanged.
- `UI007e_StageSectionTests`: real for the composer (live section, no section, stopped, cleared, next only on change, hidden, never on audience or broadcast, round trip). Missing: a deck with a custom section order through `WorkspaceModel` (`SYS015_EditorTests` only checks names against the slides' own groups), and the two elements in Edit's preview.
- `UI007f_ScreenLookTests`: real for resolution, composition, deletion fall-back, persistence and image paths. One assertion is weak: `aStageScreenOnlyTakesTheLookForItsProps` (line 210) passes if the scenes are merely unequal (`<` or `!=`) and does not go through `stageScenes`. Missing: removing a screen that has a chosen Look, and the Edit previews (M5).
- `UI007f_SignalChainTests` and `UI007f_SignalMapNotesTests`: real for the pure editing and the map tiles. Missing: mirror removal (M2).
- `UI007f_ScenesDigestTests`: a recorded digest of the scenes with no per-screen Look; a real guard that nothing moved for libraries that do not use the feature.
- Not tested at all: the Screens notes view, the draft behaviour of `CommitField` (L14), the toolbar and transport split views at run time.

## Areas checked and found sound

### Output path

- Thread and lifetime of the link: the callback runs on the output's `RunLoopThread` (link added to that run loop in `.common` mode, `MetalOutput.swift:143`). `link.delegate` is weak (header) and `MetalOutput` holds the target strongly (`:49-50`, `:149`), so the link cannot call a freed target. The handler holds the renderer weakly. No cycle between link, delegate, layer and output. `finish` removes the observers, invalidates the link, drops the target, stops the renderer (`running = false`) and the thread, then closes the window. A callback already in flight finds `running == false` or a nil renderer and returns. Closing the window (`willClose`), a screen change that cannot be reconciled, and an unplugged display all go through `finish`; `finish` is guarded by `status == .running`, so a second call does nothing.
- A drawable is used once: it comes in with the callback, is presented once through `cb.present`, and is not stored. When the tick returns early (GPU behind, no compositor, encode error) the drawable is dropped unpresented and the in-flight count is given back (`if !submitted { inFlight.signal() }`). The two-frames-on-GPU guard runs before any encoding and is unchanged in effect; `inFlight` is released in the command buffer's completed handler together with the media textures (`OutputRenderer.swift:144-148`), including the new object textures (`MediaFrameTextures.hold`).
- The gate's data races: `shown`, `pending`, `pendingToken`, `nextToken`, `held` are touched only from `tick` on the render thread; `wantedToken` and `readyToken` only under `lock`. A late `done()` only sets `readyToken` when its token is still wanted, and `adopt` and `cancelPending` clear the wanted token, so an old preparation cannot bring an old scene back and a newer scene is never overtaken. The token only grows. Blackout and Clear scenes that carry no new words or images are adopted on their first frame, and a Blackout while a scene is pending cancels the pending one. `held` carries over from an older pending scene to a newer one on purpose (the test `aNewSceneEveryFrame...` asserts it), which is what keeps the total wait bounded.
- `BackgroundScenePreparer` has no lost wake-up: the `workerScheduled` flag is set under the lock in `prepare` and cleared under the same lock in `drain` when `latest` is empty. One request waits at most; older requests are replaced. A request that is no longer wanted is skipped. The shared stores are bounded: `SharedTextStore` (192 MB, LRU fits at 256), `SharedImageStore` (32 entries, 192 MB, pins last 60 s and are still evictable when over the limit).
- `FrameEventLog`, `TickRing`, `TickWorkHistogram`, `EventMarks`, `VisibilityTimeline`: storage is reserved once and capped (2,000 events, 8 ticks, 2,000 marks, 500 spans, fixed buckets); past a cap there is only a count. The ring snapshot (the one allocation) is built only for a notable frame under the cap (autoclosure), on the presented-handler thread, not on the render thread. `TickRing.push` and `snapshot` index arithmetic checked (first = `next` once full; `count` never above capacity). Per tick the render thread takes the renderer lock twice at most and does a handful of stores. The classification rule order and the window (`eventTime - gap - 3 periods` to the event) match the text in `ruleLines` and the doc comment.
- SDI, scheduler and Fill/Key: the diff in `SDIOutput.swift` is the teardown counter (`TeardownCounter`, `begin` on the main actor before the queued stop, `end` on the queue after it) and the `onTeardownFinished` hop, plus `objectMedia: media.objectTextures` in `SDIFrameRenderer`. The SDI renderer does not use the gate, the display link or the new log. Scheduler, pacing and key code are not in the diff. One real change to note: video objects (UI-007c) now also reach SDI frames, at most 8 clips per frame (`MediaFrameResolver.objectVideoLimit`).
- Retiring list (FIX-V M2): `retire` adds only a target that reports `isTearingDown`; `onTeardownFinished` is set in the same main-actor turn, and the queued hop that calls it runs after that turn, so the callback cannot be missed. A teardown that ends before `retire` runs leaves the target out of the list. `awaitRetiredTargets` still empties the list for a waiting stop and an SDI start.
- Swift 6 annotations in the changed files: `ScenePreparationGate`, `BackgroundScenePreparer`, `TeardownCounter` (`@unchecked Sendable`) each carry a comment naming the owner thread or the lock, and the code matches it. `OutputRenderer`'s new fields (`events`, `ring`) are written only under `lock`. No `nonisolated(unsafe)` was added in this range. The unstructured tasks added are the `Task { @MainActor }` hop in `SDIOutput` and the soak's own task; both are short and hold `self` weakly or are cancelled by exit.
- Soak code (`AppModel.swift:1840-1990`): marks are bounded, the event log is read once after the run, `exit` at the end. `LoopingVideoSource.itemChanges` is appended and read under the existing lock and capped at 2,000.

### Data and media

- Migration v15: additive, literal column names, atomic per migration, FK with cascade, index; the data dictionary agrees with the schema; fresh and migrated libraries reach the same shape.
- The backup: taken after the newer-library check and before the pool opens, SQLite backup API into a hidden `.partial` file moved into place, a name that is never reused (counter), never overwrites or deletes anything, and is not matched by the import-backup prune (prefix differs). A failed copy throws and nothing migrates. Not taken for a new, in-memory or step-by-step fixture library.
- Opening a library from a newer build: refused by the existing history guard before anything is written. Opening this library in an older build: the older build's guard refuses (v15 is unknown to it); builds before FIX-H item 14 were not examined.
- Defaults write no key: `SlideObject`, `TextObject`, `ScreenProfile`, `ScreenProfileExtras` and the package asset entry encode as before when the new fields are unused.
- Package import: marks, marker times, counts, action size and shape, bounded names, a video object with no clip in the package (refused), a clip that maps to an existing bin item, and fixed marker action ids all behave as the tests say. Marker actions are checked again by the command path before they run, so an imported marker cannot move the show.
- Transport marks: `MediaTransport.usable` ignores marks that cannot work, position, remaining, loop count, play after end, pause, seek and stop are consistent with the marks; a clip with no marks is unchanged.
- Player marks: loop uses a time range, a non-loop clip uses `forwardPlaybackEndTime`, the start seek and the stall watchdog use the played part's end.
- Marker feed: once per crossing on a loop (one at the out mark included, one at the in mark each pass), a seek never fires, a back-step under a frame is jitter, a marker is per layer (not per output), and a marker action goes through `CueModel.submit(.markerReached)` with source `marker`, refused during the hardware test.
- Nothing ticks while idle: the timer exists only while a live video layer with markers plays.
- Video objects: `ObjectVideoPlayers` is bounded at 4, all state under one lock, no file is opened on a render thread, clips close when the scene no longer names them, Stop and Blackout close them, Edit and every thumbnail use the poster (`stillScene`) and never open a player, and editing writes through the one edit path so Live is unchanged.

### Interface and fixes

- FIX-U's three split views (`ToolbarStateTag`, `ShowSlimRow`, `TransportText`): the same content, labels (`Show state`, `Edit live slide...`, `Drop the live background override`), help texts, `accessibilityElement(.combine)` on the text block and keyboard paths were carried over. `fixedSize` keeps the badge width. No timer, `TimelineView` or polling was added; each view reads only what it shows. The popover on "Edit live slide" and the Drop button still work from the moved view.
- UI-008: the changes are one button style (Add screen keeps its label, help and disabled rule), tag-only `wfRect` calls, prefixed rectangle ids for the nested action list, the Auto-fit label size and field width, and a fixed hex field width inside a fixed 299 pt inspector. No behaviour change found.
- Per-screen Look (UI-007f): `ScreenLooks.overrides` skips a screen whose own Look is the show's, so changing the show's Look never moves a screen that kept its own; a deleted Look clears the choice in memory and in the stored profiles in the same call; a removed screen takes its choice with it; a new screen starts following the show's Look; `editScreenLook` edits the Look the screen uses; every composer except Edit's previews takes the overrides (`makeSnapshot`, `thumbnailScene`, the soak snapshot, layer chips, theme lookups, image usage, program export's Looks in use). A note or chain edit does not change the output signature, so it never restarts an output (`OutputCoordinator.signatures`). The choice does not re-plan outputs; it republishes through `onAppearanceChange` like `selectLook`.
- Notes and layouts to the wrong screen: stage scenes are put into `PublishedScenes` only for stage-role profiles; the Edit preview takes notes only for the stage role; the new Look path gives a stage screen only props. No new path puts notes or a stage layout on an audience or broadcast screen.
- Signal chain and key note editing: label trimmed and cut to 120 characters (also when read from storage, through the initialiser), chain cut to 12, a mirror that does not exist takes nothing, empty tails are dropped, stored only when non-empty (a library using none stores what it stored before). The map shows the key tile's own note and falls back to the fill's, and shows at most three typed boxes with "+N more".
- Stage Section and Next section (UI-007e): drawn by `StageComposer` only; the audience and broadcast composers never read the names. The right section is used with a custom section order, because the names come from the slides of the arranged list (`WorkspaceModel.previewDeck`); an empty, blank or missing name draws nothing; next section draws only when its name differs from the live one (by design). Neither element ticks, so nothing is added to the stage's one-second refresh.
- The two merge resolutions: `thumbnailScene` passes the overrides and then `stillScene` (poster for each video object); `SlideCanvas` uses `thumbnailScene` for the audience role (already still) and `stillScene(editPreviewScene(...))` for the others, so each role goes through `stillScene` exactly once and a video object is never played in Edit. For Broadcast with a transparent theme, objects are left out by the composer as before. The only gap is M5/L12, which is about what the preview composes, not about the merge.
- Editing never changes Live: Remove screen, Select Look for a screen and marker edits write only settings or library rows; nothing in this part writes to `ShowState`. Red is not used for anything but on air in new code (the Blackout and Cleared word is amber, as before).

## What cannot be judged without running the app: a hands-on script

### Output path

1. Frame cadence at a first show. Run the soak with the lyric deck at 60 Hz for a few minutes: expect no `gate holding` tick that ends in a drop. Then repeat with a deck whose slides are text boxes and shapes only (M6) and compare drops at slide changes.
2. Added latency (L17). Go Live on a warm slide on a window output with a slow-motion capture or a log of `sceneChanged` ticks: note whether the new slide appears one frame later than the command. Compare audience and stage on one slide change (L21).
3. Stage Blackout (L18). Press Blackout with a stage screen open: note how long the "BLACKOUT" text takes to appear compared with the audience screen going black.
4. Refresh rate. With two displays of different rates, drag a window-destination output from one to the other: check the Screens readout for a sudden count of dropped and late frames (L19), and check the link keeps calling (frames still presented).
5. Link lifecycle. Open and close screens 20 times and watch memory (the retiring fix is tested only with fakes). Close the output window by hand while live. Unplug a display, and put the Mac to sleep and wake it with an output running: check frames resume, that nothing is presented twice, and that a faulted output shows an actionable message.
6. Occlusion. Cover the output window with a full-screen app, then uncover: check the link resumes and `isOccluded` is reported (the old NSView display link tracked the window; whether `CAMetalDisplayLink(metalLayer:)` does is not stated in the header).
7. Callback timing (L23). In a soak report, read the `cb` figure of several ticks: if it is always negative the rule's second branch can never fire.
8. A stalled file (L20). Put a slide image on a network volume, drop the connection, and change slides: note how long each later change takes to show.

### Data and media

Short hands-on script:
1. Play a clip with a marker 0.3 s before its end (foreground, once). Does the marker run (M1)? Pause 10 ms after a marker and resume: does it run twice (L5)?
2. Import a program with "keep both" on a Look that conflicts, where a marker selects that Look: which Look does the marker apply (M3)?
3. Give two mirrors typed chains and key notes, remove the first mirror, read the second (M2).
4. Put a video object on a slide, unplug the disk, make the slide live: is there any message (M4)? Replug and trigger again.
5. Put a video object on a slide and Blackout then lift: does the video restart and gap (L3)?
6. Set Mark in from the playhead, open the marks list, tab through the In field: does the time change by up to 0.05 s (L4)?
7. A clip with marks used as a video object: does it play the whole clip (L2)?
8. Time: open a large v14 library on first launch with the backup (the copy runs on the opening thread; the cost for a large file is unmeasured).
9. Marker timing against the picture (KI-243) and the 50 ms observer under load (KI-251) need the real player and screens.

### Interface and fixes

1. Macro key. Give a macro "Select Look" the key F5 (hold Fn if needed). In Show with the grid focused, press F5: the Look changes once. Click a button so it has focus and press F5: it still runs. Switch to Edit, select an object, press F5: nothing runs. Open Settings and press F5: nothing runs. Press F5 in a text field: nothing runs.
2. Per-screen Look. In Screens give the lobby audience screen its own Look. In Show pick another Look: the lobby stays, the main screen changes, and the list row says "Look: ...". Delete the lobby's Look in the Look panel: the lobby follows the show's Look at once (L15). Remove the lobby screen: the dialog names its Looks.
3. Notes. Type a key note, then click another screen in the list without pressing Return: reopen the first screen and check the note is there (L14). Add a chain to a mirror, remove the first of two mirrors, and read the map (M2).
4. Edit previews. Give the broadcast screen its own Look, then in Edit press Broadcast and compare with the real broadcast window (M5). Add a Section element to a stage layout and press Stage in Edit (L12).
5. Remove screen. With one audience window running, press Remove screen: it must refuse. Close screens, remove it: its output is gone and the stage layout choice with it. Open screens and press Remove on a screen that has just been opened: check the refusal appears at once.
6. Section order. In a song with three sections, remove the second and, at once, the third row: the right two are left. Drag a section: it lands before the one it was dropped on.
7. Stage Section. Give the stage window a layout with Section and Next section; Go Live through a song with a custom order and a repeated chorus: the section name follows the arranged order, and Next section appears only when the name changes.
8. Display memory. With display or window outputs only, open and close the screens twenty times; compare memory in Activity Monitor (FIX-V M2 with a real output).
9. Offline check. With a network volume that hangs, plug in a USB disk with a bin file: check the offline marks update (L16).
10. Transport bar and Show inspector. Press Next, Clear and Blackout with the app idle in between: the words and the badge update, the buttons do not flicker, and the CPU stays quiet when idle.
