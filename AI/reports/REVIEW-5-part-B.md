# Independent review, fifth pass, Part B (data and media): findings

Range: `8590d5a..fb41ae2`. Scope: SYS-015 (migration v15, backup, store, package), UI-007c (video objects, Layers, lock, hide) and UI-007d (marks, markers). Read-only: code read through git (`git diff`, `git show`, `git grep`) at `fb41ae2`. Nothing was built, run or launched. No git state was changed. Reports in `AI/reports/` were not trusted. Line numbers are as of `fb41ae2`.

"Confirmed" means the path was read end to end. "Plausible" means the path exists but a timing, platform or input condition was not established.

Count: 0 high, 4 medium, 11 low.

## High

None found. Nothing in this part can put a wrong picture on air, lose a library, crash, or send notes to the wrong screen by a path I could read.

## Medium

### M1. A marker crossed in the last moment before a pause, a Stop or the clip's end is lost
- Where: `OperatorCore/MediaMarkerModel.swift:242-249` (`refresh`), `:252-264` (`tick`), `:234-239` (`needsObserver`).
- The observer is only needed while a layer `isPlaying`. When the layer pauses, ends or is cleared, `refresh()` stops the timer and calls `feed.reset()` at once. There is no last `tick()` first. The timer fires every 50 ms, so anything the playhead crossed since the last tick is never looked at.
- Scenario 1: a non-looping clip has a marker at (or within 50 ms of) its end or out mark ("lower third off", "prop off"). The clip ends between two ticks. `playerReportedEnd` takes the layer away, `refresh()` stops the observer, the marker never runs.
- Scenario 2: the operator pauses 20 ms after a marker's time but before the next tick. Nothing fires. On resume the feed starts a new pass from the playhead (`poll`, first branch) and arms only markers at or after it, so the marker is skipped for good.
- The test `UI007d_MarkerModelTests.aClipThatEndedStopsTheObserver` (line 153) advances the clock 11 s over a marker at 4 s with no tick in between and only asserts the observer stopped. It does not notice that the marker never ran.
- Confidence: confirmed for the end of a clip and for pause; the size of the window is the tick interval plus any main-thread delay.
- Fix idea: `refresh()` takes one more `tick()` before it stops, with the position clamped to the end.

### M2. Removing a mirror leaves the new key notes and signal chains on the wrong destination
- Where: `OperatorCore/ScreenEditing.swift:135-142` (`removingMirror`), against `Domain/OutputRouting.swift` (`connectedToKey`, `signalChains`, both indexed like `connectedTo`, 0 for the primary and n + 1 for mirror n).
- `removingMirror` removes entry `index + 1` from `connectedTo` so notes stay aligned. It was not changed by SYS-015 and does not touch `connectedToKey` or `signalChains`. After removing mirror 0 of two, the surviving mirror (now index 0, array position 1) shows the removed mirror's key note and chain, and its own are left past the end.
- Scenario: a Fill and Key setup with two mirrors, each with a typed chain ("enclosure, converter to ATEM input 5") and a key note. The operator removes the first mirror. The Screens signal map now describes the second mirror with the first one's wiring, marked "typed by you". For a broadcast Fill and Key path this can send someone to the wrong cable.
- Confidence: confirmed by reading; no other place shifts these arrays (`git grep signalChains connectedToKey`). No test removes a mirror with a key note or chain.

### M3. An imported marker that selects a Look keeps the package's Look id even when that Look was imported under a new id
- Where: `ProgramPackage/ProgramImporter.swift:210-219` (the marker remap, inside `if !assetIDMap.isEmpty`), against `ProgramImportPlan.swift:176` and `:248` (`plan.lookMap`, applied to slide actions only).
- The export follows a marker's actions to the Looks they select and ships those Looks (`ProgramExporter.swift`, the marker loop calls `references.add`). On import a Look that conflicts and is kept beside the existing one (`keepBoth`, or "in use on the live show") gets a new id. Slide actions are rewritten with `lookMap`. Marker actions are rewritten with `assetIDMap` only, and only when that map is not empty.
- Scenario: the library has a Look "Worship" with the same id but different content. The operator imports a program with "keep both". The slide actions select the imported copy. The clip's marker still selects the id of the library's own "Worship". When the clip plays live, the marker puts the wrong Look on the screens.
- Confidence: confirmed by reading. `aMarkerActionIsPointedAtTheExistingBinEntryWhenTheLibraryAlreadyHasThatClip` covers assets only; no test covers a marker and a renamed Look. The data dictionary says a marker's Look "comes along", which is true for the file but not for the id.

### M4. Video objects: a clip that fails to open, or is the fifth, draws nothing on air and is reported nowhere in the app
- Where: `App/Sources/EditObjectVideos.swift:103-114` (`syncObjectVideos`), `MediaEngine/UI007c_ObjectVideoPlayers.swift` (`unavailableAssetIDs`, `skippedAssetIDs`, `setOnAvailabilityChange`).
- The player set records failures, unhealthy players and clips beyond `limit` (4). `git grep` shows the app never reads `objectVideos.unavailableAssetIDs` or `skippedAssetIDs` and never sets `setOnAvailabilityChange` on it (only the capture code at `EditUI007cCapture.swift:79` reads it). The registry's own `unavailableAssetIDs` (read by the 0.2 s ticker, `AppModel.swift:1155`) is the layer slots only.
- Scenario: a slide with a video object whose file is on an external disk that was unplugged, or a slide with five clips. The service starts; the video area is empty; Show shows no warning. KI-239 says a missing clip is "reported only in the inspector", which only covers a clip that left the bin, not one that is in the bin and cannot be opened or decoded.
- Confidence: confirmed that nothing in the app reads it.

## Low

### L1. A video object's failure flag is never cleared when the clip opens on a later attempt
- Where: `MediaEngine/UI007c_ObjectVideoPlayers.swift:89` (`failedIDs = failedIDs.intersection(wanted.keys).union(failed)`).
- A clip that failed is retried at every `apply`. If it opens now, it is in `opened`, but its id stays in `failedIDs` while it stays wanted, so `unavailableAssetIDs` goes on reporting it. It clears only when the clip leaves the requests.
- Scenario: a disk is plugged back in; the clip plays; the unavailable flag stays. Harmless today because nothing reads it (M4); wrong the day M4 is fixed. No test covers recovery.
- Confidence: confirmed.

### L2. A video object ignores the bin item's in and out marks
- Where: `ObjectVideoRequest` (no marks) and `ObjectVideoPlayers.apply`, which builds `VideoPlayerSource(url:loops:duration:muted:)` without `markIn` or `markOut`.
- Every other place that plays a bin clip honours its marks (layers, preview, a slide's own background). The Mark in help text says "Play from the playhead". A clip used as a video object plays whole. Not in the known issues (KI-239 to KI-245).
- Confidence: confirmed. It may be intended; it should be written down.

### L3. Blackout (or any publish that removes the objects) closes the video players, and lifting it reopens them from the first frame
- Where: `AppModel.publish()` calls `syncObjectVideos` on every publish; under Blackout or Stop the composed scene has no `objectLayers`, so `apply([])` closes every clip. On lift they open again, start from 0 and draw nothing until a frame arrives.
- Scenario: a video object on the live slide, Blackout then lift: the video restarts and the box is empty for the first frames. The slide's own background does not do this (Blackout keeps that player).
- Confidence: plausible (depends on the composer returning no objects under Blackout, which the early return in `SceneComposer` suggests; I did not trace the Blackout branch to the line).

### L4. Focusing and leaving a time field rounds the stored time to a tenth of a second
- Where: `App/Sources/MediaMarksPopover.swift:137-143` (`MarkRow.commit`) and `:175-178` (`MarkerRow.commitTime`), both run on focus loss.
- The field shows `MediaTimeText.format` (one decimal). On focus loss it parses that text and compares with the stored value. A mark or marker set from the playhead at 12.37 reads "00:12.4" in the field; leaving the field writes 12.4 (the difference 0.03 s is over the 0.0005 s tolerance). A marker moves up to 50 ms, and a mark in moves its first frame.
- KI-249 says stored times keep precision typed; the focus round-trip does not.
- Confidence: confirmed.

### L5. Pause then resume can run a marker twice
- Where: `MarkerFeed.poll` first branch and `MarkerTracker.start(at:)` (`CueEngine/PlaybackMarker.swift`, arms markers with `time >= position - tolerance`), together with the reset in M1.
- A marker fires when the playhead is within half a frame (8 ms) before its time. The observer then stops at pause and the feed forgets the layer. On resume `start(at: p)` re-arms any marker at or after `p - 8 ms`. If the clip was paused within about 8 ms after the marker fired, the marker runs again on resume.
- The tracker's own rule "landing on a marker counts as being past it" applies to a seek; the model's pause-reset path does not apply it.
- Confidence: plausible (a narrow window).

### L6. The v15 backup is skipped silently when the library's history cannot be read
- Where: `Persistence/LibraryStore+Backup.swift:60` and `:62-64`. `try? DatabaseQueue(...)` and `try? source.read` return early with no backup when the read-only open or the history query fails. The migration then runs.
- ADR-0009 decision 4 says a library that cannot be copied is not opened. That holds only when the copy is attempted; a library that cannot be read read-only (a hot `-wal` file after a crash on a read-only folder, a locked file) takes no copy and still migrates.
- The same pattern is in the older `newerMigration` guard (`LibraryStore.swift:77-81`). The test `whenTheCopyCannotBeWrittenNothingIsMigrated` covers a blocked `Backups` folder only.
- Confidence: plausible.

### L7. Package import accepts marks that the store and the model refuse
- Where: `ProgramPackage/ProgramReader.swift:157-175` (`validateMarks`), `ProgramImporter.swift:196-200`.
- `MediaMarks.isValid` allows `markIn == markOut`. The store (`setMediaMarks`) refuses marks on a picture; the model refuses `markIn >= markOut` and marks on a sound. The importer applies none of these three: a package can bring an image with marks and markers, a clip with equal marks (the transport ignores both, but the strip says "In 5.0 · Out 5.0"), or markers on a sound (never played). Nothing is lost or unsafe; the data is not what the app can write.
- Also, `INSERT OR IGNORE INTO mediaMarker` (`:203`) drops a marker whose id already exists in the library without a word, and a clip that maps to an existing bin item (`assetIDMap`) brings neither its marks nor its markers (the existing item is kept as it is, with a warning about the file only).
- Confidence: confirmed.

### L8. Marker actions are decoded on every observer tick and on every view body
- Where: `MediaMarkerModel.playbackMarkers` (`:224`, called twice per slot per tick at 20 Hz on the main actor, decoding each marker's JSON), `actions(of:)` and `actionsAreUnreadable` (`:134-143`, scan all clips and decode), used per row at `CuesMarkers.swift:116` and `MediaMarksPopover.swift:98`.
- With a normal clip (a handful of markers) this is cheap. A clip at the permitted 1,000 markers, or an imported one with large actions (up to 64 KiB each), makes each tick and each redraw do thousands of JSON decodes on the main thread, with `feed.poll` also comparing the whole marker array by value each tick.
- Confidence: plausible (limit case; not measured).

### L9. Deleting a marker has no confirmation and no undo
- Where: `App/Sources/MediaMarksPopover.swift:168`. The trash button calls `markers.delete` directly. A marker holds the actions the operator built in Cues; they go with it. Deleting a media item also cascades to its markers (`mediaMarker.assetID ... ON DELETE CASCADE`, tested) with no word about the markers lost.
- Confidence: confirmed (check whether the media-item delete confirmation names markers; I read the marker side only).

### L10. A marker list can read stale after Add while the first load is still in flight
- Where: `MediaMarkerModel.load` (`:148-155`): `guard !loading.contains(assetID) else { return }`. `add` inserts, then `await load`; if `syncAssets` has a read of that asset in flight, the second `load` returns at once and the in-flight read may predate the insert.
- The list and the armed markers miss the new marker until the next reload. Narrow: `syncAssets` only loads an asset with no list yet.
- Confidence: plausible.

### L11. The data dictionary still describes fields as "stored only" that are now honoured
- Where: `docs/19-data-dictionary.md`, rows for `isLocked` ("the editor honouring it is later work"), the video content case ("nothing draws it yet"), `backgroundFill` ("Stored only"), `screenLookID` ("Stored only"); and `Domain/OutputRouting.swift`, `Domain/SlideObject.swift` and `Domain/MediaLayers.swift` comments say the same for `screenLookID`, `isLocked`, `fit` and `backgroundFill`. UI-007c and UI-007f make them live. The schema columns themselves agree with the dictionary (`mediaAsset.markIn/markOut`, `mediaMarker` with its seven columns and index, checked against `Schema.swift`).
- The format version of the program package stays 1 although a package can now hold a `video` object an older build cannot decode: the older build says "Something in it is missing or has the wrong shape", not "newer format". Marks and markers in a package are ignored by an older build without a warning.
- Confidence: confirmed.

## REVIEW-4 items in this part
Not part of Part B (Part C reads them).

## Tests
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

## Areas checked and found sound
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

## What cannot be judged without running the app or hardware
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
