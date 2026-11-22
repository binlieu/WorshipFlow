# Independent review, third pass: findings

Commit reviewed: a5ae9b2. Read-only, by reading code through git only (`git show`, `git grep`, `git ls-tree`). Nothing was built, run or launched, and no git state was changed. Line numbers are as of a5ae9b2.

Method: I read the crash, remote-control, show-state, scene-composition and docs areas myself. Three read-only sub-reviewers covered (a) data safety, (b) SwiftUI index use, observation and keyboard, (c) render and output threads. Every finding below marked "re-read" is one where I read the cited lines myself. Findings marked "sub-reviewer" were traced by one of the three and not re-read by me.

Confidence words: "confirmed" means the code path was read end to end. "Plausible" means the path exists but a timing, platform or input condition was not established.

Count: 1 high, 8 medium, 20 low.

## High

### H1. A program package can store an absurd media `duration`, and the Media bin then traps every time it is drawn
- Where: `ProgramPackage/ProgramFormat.swift:301` (`AssetEntry.duration: Double?`) and `:239` (`BackgroundEntry.duration`); no range check in `ProgramReader.validate` (`ProgramReader.swift:70-97`); written as is by `ProgramImporter.swift:195-199` and by `ProgramImportPlan.swift:191-194`. Read back and converted by `App/Sources/MediaBinPanel.swift:238-240`: `let s = Int(seconds.rounded())`, used at `MediaBinPanel.swift:202` and `:256`, and `MediaDockView.swift:198`. `MediaAudioColumn.swift:119` has the same shape.
- Scenario: a hand-made or damaged `.worshipflowprogram` has a media asset entry with `"duration": 1e300` (or `-1e300`). The package passes validation, the import succeeds, the row is stored in `mediaAsset.duration`. The next time a media tile or list row is drawn, `Int(Double)` traps for any value beyond the Int range. The crash repeats on every draw of the bin, and the value lives in the library, so only editing the database removes it.
- `MediaProbe` already filters to finite and positive (`MediaProbe.swift:59-60`), but nothing bounds the upper end, and the package path bypasses the probe.
- Confidence: confirmed (re-read). Swift traps on an out-of-range `Int(Double)` conversion; JSON accepts 1e300.
- Fix direction: validate `0 <= duration <= some cap` (and pixel sizes) in `ProgramReader.validate`, and make the three display conversions clamp.

## Medium

### M1. Next onto a Bible passage uses a playlist index across an `await`
- Where: `OperatorCore/WorkspaceModel+Transport.swift:206-240` (`step(by:)`), reads at `:209` (loop condition after `continue`), `:218`, `:235`, `:240`.
- `j` is taken from `PlaylistStepping.target` before the `await scripture?.resolve(spec)` at `:212`. The only recheck afterwards is `epoch == transportEpoch` at `:213`. `transportEpoch` is bumped by Go Live, Clear, Stop, Blackout, media and countdown actions only (seven sites in all, none in `WorkspaceModel+Playlists.swift`). Playlist edits and playlist switches (`playlistItems = list` at `WorkspaceModel+Playlists.swift:14`) do not bump it.
- Scenario: the operator presses Next while the next item is a passage; during the Bible read the playlist shrinks (an item is removed, or another playlist is selected). `playlistItems[j]` is then out of range: an Index out of range trap during a live service. This is the KI-193 shape (a position held across a suspension).
- Confidence: confirmed that the index is unguarded after the await (re-read). The window is the length of one database read, so it is narrow.
- Fix direction: after the await, re-find the item by id (`firstIndex(where:)`) and bail out if it is gone.

### M2. `deleteSlide(at:)` checks an index, suspends, then uses it; the confirmation holds a position, not an id
- Where: `OperatorCore/WorkspaceModel+Editing.swift:114-120`: `guard slides.indices.contains(index)` at `:115`, `await flushDrafts()` at `:116`, `slides[index].id` at `:117`. The index comes from `App/Sources/CentrePane.swift:162` (`pendingDelete: Int?`) and `:172`, set at context-menu time and used after the confirmation dialog.
- Scenario A (crash): slides shrink or reload during `flushDrafts()` (a queued move, `reloadOpen`, another delete); line 117 traps.
- Scenario B (wrong slide): a reorder or an insert while the dialog is open; "Delete slide" removes whatever sits at that position now.
- Confidence: confirmed (re-read). Scenario A needs an unlucky timing; B needs only an edit while the dialog is open.
- Fix direction: carry the slide id in `pendingDelete` and delete by id.

### M3. A package whose media entries claim huge sizes crashes the app when the import sheet opens
- Where: `ProgramPackage/ProgramImportPlan.swift:345` (`plan.summary.mediaBytesToCopy += entry.size ?? 0`) and `ProgramImporter.swift:88` (`reduce(Int64(0)) { $0 + ($1.entry.size ?? 0) }`). `MediaEntry.size` is a bare `Int64?` (`ProgramFormat.swift:325`) and `ProgramReader` only compares real file sizes with nothing (`checkFiles` returns them but they are not matched against the manifest).
- Scenario: two included, referenced entries with `"size": 9223372036854775807`. Summing traps on Int64 overflow. The importer's summary calls the planner, so the crash comes when the sheet opens, before anything is written. Negative or understated sizes fail safe (the chunked copy throws and rolls back).
- Confidence: confirmed (re-read).
- Fix direction: validate `0 <= size` and compare with the lstat size in `checkFiles`; use `addingReportingOverflow` or clamp.

### M4. A failed SDI `start()` leaks the open port and its connector claim
- Where: `OutputEngine/OutputCoordinator.swift:368-388` (`startTarget`), `OutputEngine/SDIOutput.swift:260-264` and `:304-305`, `DeckLinkSDI/DeckLinkDevice.swift:115-119` and `:291` (`claimOutput`); no `deinit` releases a claim (checked by grep).
- `makeSDITarget` opens the port, which claims the connector. `SDIOutput.start()` then throws before `status = .running` when `port.supports(mode:keying:)` is false. The catch at `:381-383` clears `onStatusChange` and `running[slot]` but never stops the target or closes the port, and `SDIOutput.finish` returns immediately unless `status == .running`.
- Scenario: a mode or key route the card refuses on that connector. Every later Retry or restart of the same output fails with `connectorUnavailable` ("check the cable"), until the card is unplugged (which bumps the generation and clears claims) or the app restarts. A real cause (mode not supported) is hidden behind a claim leak.
- Confidence: confirmed (re-read). Not exercisable without a card or the simulated device with a refusing mode.
- Fix direction: close the port whenever `target.start()` throws.

### M5. The main thread can block on the SDI frame renderer's lock, which is held across the GPU wait
- Where: `OutputEngine/SDIOutput.swift:66-103` (`frame()` holds `lock` for the whole frame: shader setup on the first frame, Core Text on a text-cache miss, `cb.waitUntilCompleted()` at `:87`) versus the getters `:57-63` (`lastError`, `unavailableImagePaths`, `renderProblems`, `sceneIsOpaque`, `renderTiming`) that take the same lock. They are read on the main actor from `OutputCoordinator.swift:311` and `:344-347` (`slotReadout`, the periodic `updateReadouts`).
- Scenario: a slow first frame or a stalled GPU command buffer. The operator window freezes for as long as the frame takes; a hung command buffer would freeze it outright.
- Confidence: confirmed (re-read). Typical frame time is small, so in practice a short hitch; the hang case needs a GPU fault.
- Fix direction: publish the readout values through a separate small lock or atomic copy written at the end of `frame()`.

### M6. Stopping an SDI output blocks the main actor for up to about two seconds, and stop can race a start still queued
- Where: `OutputEngine/SDIOutput.swift:304-313` (`finish`): `session.stop()` at `:308`, then `queue.sync { }` at `:309`, then `ahead.stop()` (waits up to 1 s), then `port.close()`. `start()` queues `ahead.start(prefill:timeout: 1)` and `session.start()` on the same queue (`:272-282`).
- Two effects. (1) `OutputCoordinator.stop()` and profile changes call this once per SDI slot on the main actor, so Close screens or a profile change can stall the UI for up to roughly a second per output. (2) The comment at `:309` says a start under way finishes first, but `session.stop()` runs before the wait. If `session.start()` has not yet run, stop marks the session stopped and tears nothing down; the queued start then passes its check, enables the port, schedules frames and starts playback, and only the later `port.close()` ends it. Whether the SDK tolerates `DisableVideoOutput` racing `ScheduleVideoFrame` is unknown without hardware.
- Confidence: confirmed for the ordering and the blocking calls (re-read); the hardware effect is plausible.

### M7. Imported playlist media and announcements items can point at a bin entry that was never inserted
- Where: `ProgramPackage/ProgramImporter.swift:186-193` builds `assetIDMap` (an existing bin row with the same path wins and the package asset is skipped); the map is applied to slide backgrounds and slide actions only. Playlist items are written from the package's own specs at `ProgramImporter.swift:279-286`, unmapped. `ProgramImportPlan.swift:196` also skips a package asset whose id already exists in the bin, even if it is a different file.
- Scenario: the library already has a bin item for the same path (`Media/Imported/<program>/<sha>.ext`) under a different id. The package asset is skipped with a warning; the imported media item keeps the package's id, which has no row, so it cannot play. A package asset id equal to an unrelated existing bin id makes slides reference the other file.
- Confidence: re-read for the importer lines; that the item payload carries the asset id unmapped is from the sub-reviewer and was not re-read.

### M8. Status and handoff documents contradict each other and the code
- `docs/14-current-status.md`: "Updated: 2026-11-21"; the summary says "1815 package tests pass" while the same file's table cites 2645 and the handoff cites 3,017; it says keyboard control has not been seen running, while FIX-N and KI-182 describe real-key runs; it has no row for FIX-K to FIX-R, UI-005c/d/e/f/g, TESTDATA-001 or the KI-193 fix, all of which the handoff calls done; "Phase 1 is under way" is stale.
- `docs/15-agent-handoff.md`: the top section is dated 2026-11-21 (afternoon) and says "UI-003 is implemented and waiting for review" and lists "Next safe tasks" that are long done; two sections say "read this first"; the 2026-11-22 morning section says "Build 139 is current: no source has changed since it" and, a few lines earlier, "Installed for the owner: build 145 (commit a0fa76c)"; the evening section says "Installed build: 115". The top rule "never touch that folder" (the owner's real library) is contradicted by the later statement that the owner's library now holds the test library and 200 bin images.
- Verification levels themselves are not overstated: nothing is called Hardware Verified or Live-Service Verified, and KI-193 is honestly recorded as "Fixed (crash site); cause sequence open".
- Confidence: confirmed (re-read).

## Low

### L1. `wf-test-data-import` cannot delete or rewrite existing songs, but it is not guarded like a tool that touches a real library
Answer to the question asked: it is additive (songs skipped by title, bin items skipped by path), refuses a library with pending migrations, refuses a missing file without `--create-library`, and checks for another process with `lsof`. It can still hurt a real library in these ways (`TestDataKit/TestDataImporter.swift`, `LibraryUsage.swift`): no backup is taken before writing (the program import takes one); an unusable `lsof` with an empty `-wal` file is `.unknown`, which the run treats as free (`TestDataImporter.swift:59`, `LibraryUsage.swift:30,41`); there is a gap between `pendingMigrations` (`:67`) and `LibraryStore.open` (`:81`), and `open` itself migrates; the schema-changed refusal (`:87`) runs after the writes; songs and pictures are two transactions (`:84-85`), so a failure of the second leaves the first; `--report` opens the store (`:101`), which prepares the search and scripture index tables, although the help text says "only reads"; a path that does not exist and has no extension becomes `<path>/Library.sqlite` (`:45`), so a mistyped path with `--create-library` creates folders where it points. Confidence: confirmed (sub-reviewer, `main.swift` and importer lines re-read).

### L2. Migrations depend on today's types, and nothing backs up before they run
`Persistence/Schema.swift:314-322` (v11) decodes old background entries with today's `MediaSelection` using `try?`, then deletes them from `appState`; v13 (`:352`) encodes the "frozen" themes with today's `Theme`. A later change to either type changes what these old steps do. `LibraryStore.open` migrates an older file without a backup. v8 copies rows before its drop, and v1 to v14 are otherwise additive. Confidence: confirmed (sub-reviewer).

### L3. The hot-folder list can be replaced by one write after a read failure
`Persistence/LibraryStore+MEDIA010.swift:55-59` returns `[]` on any fetch or decode error (`try?`); `saveMediaFolder` and `removeMediaFolder` (`:83-97`) then write the one-element list over the old one. Needs an undecodable or unreadable stored value. Confidence: plausible (sub-reviewer).

### L4. Import plan is computed outside the write transaction
`ProgramImporter.apply` evaluates the plan (`:23`), takes the backup, copies media (can take minutes), then writes (`:42`). A "use imported" choice deletes the slides, arrangements and groups of the replaced presentation using a decision made against older data, so edits made in between are replaced; the backup predates them. A concurrent insert of the same id fails on the key and rolls back. Also the target is the first library by sort order whatever its kind (`ProgramImportPlan.swift:110`). Confidence: confirmed that planning is outside the transaction (sub-reviewer); whether the sheet blocks editing during the copy was not judged.

### L5. Slide and arrangement group ids that are not in the package are kept as written
`ProgramImportPlan.swift:247` and `:254` keep an unmapped id. A hand-made package can link a slide to a section of another real presentation (the foreign key only checks that the id exists somewhere). An id that exists nowhere fails the key and rolls the import back. Confidence: confirmed (sub-reviewer).

### L6. Smaller data-handling items (sub-reviewer, confirmed unless noted)
Stale bookmark flag ignored in `App/Sources/MediaSupport.swift:28-33` (never refreshed; falls back to the stored path); `.partial` backup files left by a crash are never pruned and a renamed file that still starts with the backup prefix can be pruned (`LibraryStore+Backup.swift`); the backup holds the database only, not `Media/Imported`; quadratic work in the planner for 20,000-entry packages (`ProgramImporter.swift:127`, `ProgramImportPlan.swift:191,324`); `RetryingWriteChain.swift:94-98` retries a failed write after later writes to other keys succeeded (plausible; callers not traced); `ProgramTransfer.swift:120-122` appends the extension after the save panel, so an existing `<name>.worshipflowprogram` is replaced without the panel having asked about that name.

### L7. Display output falls back to the main screen if its display is gone
`OutputEngine/DisplayOutput.swift:25` and `MetalOutput.swift:94-132`: `start()` never calls `availabilityProblem()`. The app path is protected (`AppModel.swift:1576` throws first), so this only affects another caller. Confidence: plausible (sub-reviewer).

### L8. The SDI feed runs about 100 ms behind display outputs
`OutputEngine/SDIRenderAhead.swift`, `SDIOutput.swift:206-219`: the scene is read when a frame is rendered ahead (about three frames in the queue plus about three in the card). Blackout and slide changes reach the broadcast feed later than the audience display, so the `SceneBox` comment "all outputs on the same frame" holds for the box only. Fill and key within one output come from one frame and one schedule call and cannot split. Confidence: confirmed (sub-reviewer).

### L9. Output teardown and restart details
`OutputCoordinator.swift:413-434` with `SDIOutput.finish`: `status = .stopped` fires `targetChanged` before the old session and port are closed, so a restart on the same connector can begin first (plausible; ordering held in practice by the prefill wait). `OutputCoordinator.swift:437`: the sleep guard releases when all outputs are faulted or waiting for a card, so the Mac may sleep mid-service. `AppModel.swift:1636-1641`: a simulated clock already running in another mode is reused (simulated card only). `MediaEngine/LoopingVideoSource.swift:48-65,83-95` holds its lock across AVFoundation calls (the R18 pattern; used only by the soak and `--video` path). `AudioCuePlayer.swift:122-125` opens the file and starts the engine on the main actor.

### L10. Transport keys are disabled by window title
`OperatorCore/KeyRouting.swift:219-236` matches the window title; the operator window's title is the playlist name when no service date is set (`ServiceTitle.swift:25`, `ContentView.swift:136`). A playlist named "Hardware Test" or "About WorshipFlow" disables Space, Return, B and the arrows in the operator window with no message. Match the identifier only. Confidence: confirmed (sub-reviewer, `KeyRouting.swift` re-read).

### L11. Keys that are by design not the show's while a control has focus
`KeyRouting.swift:183-185` (sub-reviewer): with any control entry in the focus tracker, B, Space and Return pass to the control; Escape first returns focus to the grid and only the second Escape clears. If an entry stays set after a click on a non-focusable area, Blackout on B does not fire. No latch beyond the tracker was found. `anySheetOpen` includes `showLiveQuickEdit` (`WorkspaceUIState.swift:84`, used at `AppModel.swift:668`); it is a popover binding anchored on a button that is shown only while `showsSlimRow` is true (`ShowInspector.swift:31,97`). If the anchor disappears while the popover is open and SwiftUI does not write `false` back, every transport key stays off until it is shown and closed again. Plausible; needs the app.

### L12. Song list arrows never reach `onMoveCommand`
`LibrarySidebar.swift:141-149` uses `.focusable()` with `onMoveCommand`, but the key monitor consumes the arrows for focus `.none` as `.moveSelection` (`KeyRouting.swift:151-154`, `AppModel.swift:696-699`). Confidence: confirmed (sub-reviewer).

### L13. `ShowHeader` reads an `@ObservationIgnored` property
`CentrePane.swift:69` reads `workspace.openPlaylistItemID`, declared `@ObservationIgnored` at `WorkspaceModel.swift:42`. Today the header still refreshes because `install` assigns `arrangements` (`WorkspaceModel+Library.swift:177-179`), which the header also reads, on every open. If that assignment ever becomes conditional, the arrangement popup shows and writes to the previous item. Fragile, not currently failing.

### L14. Cues action list lost update
`CuesActionList.swift:124-133` builds the new list from the row's captured `actions` and writes asynchronously (`CuesEditors.swift:125-127`); two quick edits before the first write lands act on the same old list. Plausible.

### L15. Scripture passage grid reads two parallel arrays
`ScriptureView.swift:272,290,292,309` iterates `passage.contents.indices` and reads `passage.slides[i]`. The type does not enforce equal length; the only constructor (`ScriptureModel.swift:344-345`) maps one from the other, so they are equal today. The view holds the passage by value, so it is not stale.

### L16. Remote control, small items
Everything under `/api` needs a token, the host and origin checks, the strict HTTP parser, the 256-job pump and the per-address and per-code pairing limits are sound (see below). Remaining: a host on the local network can hold up to 16 connections (`maxConnections`, 10 s head timeout) and starve a real phone; a paired device can hold all 16 as event streams; when the pump is full a state refresh is silently skipped (`RemoteServer.swift:439-445`); the bearer token and pairing code travel over plain HTTP on the local network (documented in the CUE-004 spec, accepted).

### L17. MIDI flood keeps only the newest messages
`MIDIIO/Broadcaster.swift:17` uses `.bufferingNewest(capacity)`, so a flood loses the oldest messages, including possibly a Next; the router's consumer runs on the main actor (KI-185, KI-189). Known and measured, listed for completeness.

### L18. Public documents carry a contact address and an author line
`docs/15-agent-handoff.md` (State section) and `Domain/AboutInfo.swift:9` contain the maintainer's contact e-mail address, while the handoff says staged files are scanned for personal strings. `AboutInfo` is intentional; the handoff line looks unintended. Not reproduced here.

### L19. Other crash-class items examined and left as low risk
`Domain/Scene.swift:74` (`Int(Double)` in `pixelRect`) and `Compositor.swift:736` (`width * height * 4`) would trap on an absurd frame; decoded frames are bounded to 100 screens (`Scene.swift:50-55`) and the editor sanitises, so no real input reaches it. `OperatorCore/ScriptureRules.swift:38-41` divides by `size * pitch` and `size * advance`; `size` is clamped to at least 1 and the line height is clamped, `averageAdvance` is positive for any real font. `MediaDockView.swift:312` and `MediaStrip.swift:80` use `Int(t)` on a playback time that is finite in practice.

### L20. Hot spots that use `Dictionary(uniqueKeysWithValues:)` on collections that are unique by construction
`OutputPlanner.swift:153`, `SDIPresets.swift:96`, `HotFolderModel.swift:389`, `StageModel+Messages.swift:79`, `WorkspaceModel+Library.swift:17`. A duplicate id (for example a hand-edited hot-folder list or screen profile JSON) would trap. Every source is keyed by a primary key or a generated id, so none was found reachable; listed so a future import path does not reuse them.

## Earlier findings: verified fixed or still open

Checked in the code at a5ae9b2:
- R1 key repeat: fixed (`isRepeat` read per event, `AppModel.swift:664`, passed to `KeyRouting.decision`).
- R2 tall text: fixed (`TextRasterizer.swift:160-195` caps the bitmap and flags the result).
- R4 close and quit while live, Hide: present (`QuitPolicy`, `AppModel.swift:500-504`).
- R7 stat on the render thread: fixed (`Compositor.swift:845-871`, background mode asks the loader; `statProbe` seam).
- R8 Clear versus Clear all: implemented (`ShowState` `.clearAll`, `AppModel.clearAll`).
- R11 empty section order in a playlist item: Next stops with a message (`emptyPlaylistItemIDs`, `WorkspaceModel.swift:37`; transport guard).
- R12 flush at quit and resign: `flushWorkspace` exists and is called on the quit path (`AppModel.swift:480`).
- R13 theme of the live presentation: `shownThemeID` captures it at trigger (`WorkspaceModel+Themes.swift:12-18`).
- R17 clip sound after Close screens: `stopScreens` calls `media?.screensClosed()` (`AppModel.swift:1545`).
- S1 profile restore in the hardware test: `restoreProfileIfNeeded` is called (`HardwareTestRunner.swift:210,340`).
- S6 unfinished run folder: present (`HardwareTestController.swift:45-57`).
- S9 render-ahead for SDI: present (`SDIRenderAhead.swift`).
- S15 keys in the Hardware Test window: `transportKeysActive` (`KeyRouting.swift:234`), with the title-matching weakness in L10.
- FIX-N M1 to M5 and L1 to L5: marked fixed in `AI/reports/FIX-P-report.md` with failing-first tests; I read that report, not every changed line. Open there: L3 (`gridHasFocus`, left alone, argued from a real-key run) and L4 (not reproducible).
- Closed-store, S12-style cases: see "sound" for the bridge.

Not re-checked in this pass (no evidence either way from me): R3 (failed draft save retried; `DebouncedSaver` itself does not retry, the retry is in `WorkspaceModel` and was not traced), R5, R6, R9, R10, R14 to R16, R18 (still present in `LoopingVideoSource`, soak path only, see L9), S2 to S5, S7, S8, S10 to S14, S16.

Still open from earlier passes and recorded as such by the project: KI-168 and KI-180 to KI-191 (main-thread cost of drops and Next), KI-185 (MIDI burst under load).

## Areas checked and found sound

- Show state: `ShowState` keeps `liveIndex` inside `liveDeck` by construction (both `private(set)`, set together; `quickEdit` never changes the count), so `RemoteStateBuilder.swift:14-16` (`deck.slides[i]`) and `AppModel.swift:1421-1423` (`own!`, `ownBackgroundStart!`) are safe.
- Scene composition: `SceneComposer.themed` produces an empty scene for a stopped or blacked-out show on audience and broadcast, adds props only to targeted roles, and never reads notes, messages or timers; stage content comes only from `stageScenes` for `.stage` profiles (`PublishedScenes.swift:20-26`); an unknown profile id gets black, never another screen's scene; a role change publishes before `setProfiles`. Foreground clip over Clear is the documented R8 behaviour.
- Output lifecycle: `OutputRenderer.tick` signals its semaphore on every path; compositor, text, shape and image caches are bounded; `SceneBox` and the media registry hold locks only briefly; display unplug and replug end in a fault with resume-on-return, never a move to another display; the bridge's reference counting and callback handling, `SDIRenderAhead`, `SDIOutputSession` locking (never held across the port) and the simulated clock balance.
- Fill and Key: fill and key leave one BGRA frame in one schedule call, so they cannot split in time or by scene.
- Remote control: loopback or all-interface binding is explicit and configurable (`loopbackOnly`); peers are limited to local-network addresses; Host must match a loopback, own-interface or own-name value and Origin must equal it; the HTTP reader is strict (no folded headers, no transfer encodings, bounded head, body and counts, per-phase timeouts, bounded discard); tokens are 256-bit random, stored as salted hashes, compared in constant time with a dummy hash for unknown ids; the six-digit code uses rejection sampling, rotates every two minutes, after success and after ten failures in all, with a per-address lockout; token revoke closes streams and is persisted with retry and an operator notice; commands run one at a time through a bounded pump; `goToSlide` is range-checked; the state sent to phones holds only live and next text, playlist titles, timers and macro names.
- Observation: `ObservedShow`, `ObservedSlideList` and `ObservedLayers` notify every part that can differ and notify before and after the write as intended (sub-reviewer, read end to end); the only `@ObservationIgnored` property read by a view that I found is the one in L13.
- Keyboard: a focused text field, text view, search field or field editor takes the key before any show decision, so typing cannot leak; Space, Return, B and Escape reach the show from the grid and from a canvas; `isRepeat` is read per event so nothing latches; `PressGuard` is pointer-only.
- SwiftUI index use: the Show grid, list and Edit film strip guard every lazy closure; the other `ForEach` sites over indices either capture the array by value in the same body pass or check bounds; `columnCount` and the card width are clamped, so a zero-width window gives no division by zero.
- Persistence and import: single-transaction writes for slides, playlists, scripture import and program import; renumbering inside the transaction; a newer-schema file is refused before any write; hostile package paths (absolute, `..`, backslash, control characters, outside `media/`, symlinks, hard links, duplicate names) are rejected; media copies are hash-checked, written as `.partial` then moved, never overwrite a different file, and roll back only what the call created; the manifest and the file count are capped; `.replace` takes a backup first and refuses if it fails; the backup never writes over the live library.
- Test-data tool: reads songs as strict UTF-8, resolves symlinks in the test folder, refuses a batch with a song that has no slides, and is idempotent on repeat.
- Status documents do not claim hardware or live-service verification anywhere.

## What cannot be judged without running the app or hardware

- Whether SwiftUI resets a popover's `isPresented` when its anchor view disappears (L11), and whether a SwiftUI popover can leave the operator window as the key window.
- Whether `gridHasFocus` stays true after leaving Show (arrows in Stage), and whether `.focusable()` on the Show centre still reports focus to child controls after Tab, which `ControlFocusTracker` assumes.
- Whether the DeckLink SDK tolerates `StopScheduledPlayback` or `DisableVideoOutput` racing `ScheduleVideoFrame` (M6), how long a stop blocks on a real card, key polarity and premultiplication on a real keyer, and whether a card that flushes by itself starves the scheduler (`SDIScheduler` returns no actions on a flush).
- The real size of the windows in M1 and M2 (a Bible read is a database round trip; a draft flush is a write).
- Whether the import sheet blocks editing during a long media copy (L4), and whether a cancelled task around the import write can leave a committed import with rolled-back media.
- Real latency, dropped frames and the effect of a GPU hang; CVPixelBuffer and IOSurface reuse by AVPlayer under load.
- Behaviour of v8 and v11 on a large old library, and whether `Theme` or `MediaSelection` changes since the early builds already break v11 or v13 on old files (L2).
- Whether `lsof` exits with partial output when only some of the database, `-wal` and `-shm` files are open (the test-data tool's parse step suggests it is handled).
