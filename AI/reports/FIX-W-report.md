# FIX-W report: fixes for REVIEW-5 M1 to M5 and L6

Brief: `AI/specs/FIX-W-review-5.md`. All six items were real and are fixed. Nothing was committed (the coordinator commits). No `docs/`, ADR, `AI/specs`, `Vendor/`, `dist/` or `.claude/` file was edited. Output path files named in the brief (`ScenePreparationGate`, `MetalOutput`, `OutputRenderer`, SDI adapter, scheduler, Fill/Key) were not touched.

Verification level for every item: **Implemented, Unit Tested**. Nothing here was run against real hardware or a live service, and the app-side wiring of item 4 and item 5 (two App files) is compiled by `check.sh` but not exercised by a test (see "Not verified").

## Item 1 (M1, and L5 in the same change): marker crossed just before a pause, Stop or the clip's end

- What the code did: `MediaMarkerModel.refresh()` stopped the timer and called `feed.reset()` as soon as the layer paused, ended or was cleared, with no last look. A marker crossed since the last 50 ms tick was never delivered. The reset also forgot the layer, so on resume `start(at:)` re-armed a marker that had run within half a frame before the pause (L5), with the same cause.
- Tests that failed first (`FIXW_MarkerLastLookTests`, 8 tests): clip end between two ticks, pause, Stop (`stopForeground`), screens Stop (`showStateChanged(isLive: false)`) all delivered nothing (expected the marker, got none); the two L5 tests (foreground pause/resume, looped background pause/resume with marks) saw the marker fire twice. The seek-across-a-marker and idle tests passed before and after (they pin the rules that must not change).
- Change: `MediaModel` gets `onPlaybackWillChange`, called from the `layers` setter when the value is about to change and from `showStateChanged` when going from live to stopped, while the layers still hold the clip. `MediaMarkerModel.lastLook()` takes one `tick()` then, only while the observer is running (nothing ticks while idle). `refresh()` no longer resets the whole feed when the observer stops: it keeps a layer that is only paused (its clock is still, it has markers), so resume continues the same pass, and forgets every other layer (new `MarkerFeed.forget(_:)`). Marker actions still go through `onFire` and the Cues command path.
- Once-per-crossing: a seek jump still fires nothing (the last look is taken before the seek mutates the layer, so it only delivers crossings that really happened); a loop pass is unchanged (loop tests in UI007d pass); two outputs are not involved (markers are per layer, not per output).
- Residual: the last look samples the position at the moment of the change. A seek made earlier than that but after the last tick is seen by the look as a seek (the feed compares `seekCount`), so it fires nothing, as for a normal tick.

## Item 2 (M2): removing a mirror

- Confirmed. `ScreenProfile` has exactly three per-destination arrays: `connectedTo`, `connectedToKey`, `signalChains` (all indexed 0 primary, n + 1 mirror n). `removingMirror` shifted only the first.
- Tests (`FIXW_RemoveMirrorTests`, 4): removing the first of two mirrors left the second with the first one's key note and chain (failed: "second key" expected, "first box" read). Also: last mirror removal, a mirror without a key note or chain, the only mirror, a missing index.
- Change: `ScreenEditing.removingMirror` removes entry `index + 1` from all three and trims empty tails. The other editing functions (adding, `choosingSDI`, keying, alpha, `settingMirror*`) neither add, remove nor reorder entries, so they do not have the fault. Nothing reorders destinations.
- Left as the brief says: a key note kept but hidden when a destination goes from Fill and Key to plain.

## Item 3 (M3): marker Look action on package import

- Confirmed. Slide actions are rewritten with `plan.lookMap` (`ProgramImportPlan`) and `assetIDMap` (importer). Marker actions were rewritten with `assetIDMap` only, and only when it was not empty.
- Tests (`FIXW_MarkerLookImportTests`, 3): with a library Look of the same id and other content imported with "keep both", the marker still named the library's Look (failed); a marker naming both another clip and the Look needed both remaps (failed on the Look); a marker keeps its Look when nothing was renamed (passed before and after).
- Change: marker actions go through `plan.lookMap` when inserted, and again through `assetIDMap` afterwards (applied on top of the Look-mapped text). The id kinds that slide actions remap are exactly Looks and assets; macros, timers and the like are not remapped for slide actions either, so markers match them. A marker whose clip already exists in the library is not imported (existing behaviour, REVIEW-5 L7, out of scope).

## Item 4 (M4, with L1): a video object that fails to open or is past the limit is now reported

- Confirmed: nothing in the app read `objectVideos.unavailableAssetIDs`, `skippedAssetIDs` or set `setOnAvailabilityChange`.
- Tests: `FIXW_ObjectVideoProblemTests` (5, `MediaModel.reportObjectVideos`: clip could not be opened named with reason; fifth clip named with the limit; cleared when the clip opens and another message is never cleared; a dismissed message is not raised again until the problem goes and returns; nothing said when nothing is wrong). They failed first by not compiling (the method did not exist). `FIXW_ObjectVideoRecoveryTests` (1, real tiny movies): a clip that failed, then opens on a later `apply`, was still reported unavailable (failed on that expectation; passes with the fix, checked by temporarily removing the fix).
- Change: `ObjectVideoPlayers.apply` drops a clip from `failedIDs` when it opens (L1). New `MediaModel.reportObjectVideos(unavailable:skipped:limit:)` puts plain text in `lastError` (the banner the other media problems use; the app already reads `media.lastError` in `settingsError`). Text: `The video "X" on a slide could not be opened or has stopped playing, so its place on the screens is empty. Check that the drive or folder is connected.` and `A slide has more video objects than can play at once (the limit is 4): "Y" is not playing.` The App calls it from `syncObjectVideos` (after every publish, control side, main actor) and from the object players' availability callback (hops to the main actor). No timer was added; the render threads do not call it. The player limit and what is drawn are unchanged.
- Note: the unavailable set also contains a player that opened and then stalled, so the wording is "could not be opened or has stopped playing".

## Item 5 (M5 and L12): Edit's Broadcast and Stage previews

- Confirmed. `EditPreviewScene` built `PublishedScenes` with no `screenLooks` and the preview deck had no `sectionNames`.
- Tests (`FIXW_EditPreviewTests`, 5): broadcast preview equals the real broadcast scene with the screen's own Look and differs without it; the stage preview takes the stage screen's own Look for its props (equal to the real scene, differs without); a screen with no own Look follows the show's Look; the stage preview with a layout holding Section and Next section equals the real stage scene and draws both names; names never reach an audience or broadcast preview. They failed first by not compiling (new parameters). `FIXV_EditStagePreviewTests` was not edited and still passes.
- Change: `EditPreviewScene.scene(...)` (both overloads) and `previewState` take `screenLooks: [UUID: Look] = [:]` and `sectionNames: [String?] = []` (defaults keep existing callers and tests). Names are used only when the open deck is used. `AppModel.editPreviewScene` passes `screenLookOverrides` and `ArrangementResolver.sectionNames(for: workspace.slides, groups: workspace.groups)`, the same values the live path uses. Editing still never changes Live (the preview builds its own `ShowState`).

## Item 6 (L6): v15 backup skipped when the history could not be read

- Confirmed by reading: `try? DatabaseQueue(...)` and `try? source.read` returned early with no copy.
- ADR-0009 decision 4 is consistent with the change (a library that cannot be copied is not opened); no conflict.
- Tests (`FIXW_MigrationBackupTests`, 4): a non-empty file that is not a library, and a library locked exclusively by another connection, threw a raw `DatabaseError` instead of the copy refusal (failed on the error type); the refusal text; a zero-byte file still opens as a new library with no copy (passes before and after).
- Change: `backUpBeforeMigrating` now throws `MigrationBackupFailed` (nothing migrated, file untouched) when the file is non-empty and cannot be opened or its history cannot be read. A zero-byte file is a new library and is skipped as before. `MigrationBackupFailed.errorDescription` says "(to v15)" when it has no from-step. The older `newerMigration` guard in `LibraryStore.swift` still returns nil on an unreadable file, but the backup step now follows it directly, so no migration runs unprotected; it was left alone.
- First full `check.sh` run: exit 1, 3 failures (`FIXG_ImportGuardTests` x2, `FIXG_ReplaceImportIntegrationTests`), all `MigrationBackupFailed` ("unable to open database file") when the tests opened a backup copy (a clean WAL-mode file with no -wal or -shm) under the load of the full run; they pass alone (0.3 s) and had passed before this item. The old code skipped such a failed read-only open silently, which is why it never showed. Fix in the same item: if the read-only open or read fails, the history is read once through an ordinary connection (the one the open is about to make anyway); only when both fail is the library refused. This also means a clean library cannot be refused just because a read-only WAL open is not possible. I did not find the exact cause of the load-only read-only failure; it is the one open point of this item.
- I could not build a case in which the read-only open fails and the normal read-write open then succeeds and migrates, so the "migrates without a copy" scenario itself was not reproduced; in both cases tried the normal open also failed. The change closes the path by construction.

## Check result

`./scripts/check.sh`: exit 0 on the second run (package tests: 3580 tests in 568 suites passed, of which 30 are new in the seven `FIXW_*` files; domain boundary; project generation; Debug build; Release compile with 195 s; no measuring hooks in the Release binary). The first run exited 1 for the reason given under item 6. A scratch derived-data folder (outside the repository) was used and deleted afterwards; no `.app` was left behind. `MIDIRouterTests`, `ToolProcessRunnerTests` and `ScriptureLibraryTests` did not fail.

## Files changed

Sources: `Packages/WorshipFlowKit/Sources/OperatorCore/MediaModel.swift`, `MediaMarkerModel.swift`, `MediaMarkerFeed.swift`, `ScreenEditing.swift`, `UI006c_EditFeatures.swift`; `Sources/ProgramPackage/ProgramImporter.swift`; `Sources/MediaEngine/UI007c_ObjectVideoPlayers.swift`; `Sources/Persistence/LibraryStore+Backup.swift`; `App/Sources/AppModel.swift`, `EditObjectVideos.swift`, `EditCanvasChrome.swift`.
Tests (new): `Tests/OperatorCoreTests/FIXW_MarkerLastLookTests.swift`, `FIXW_RemoveMirrorTests.swift`, `FIXW_ObjectVideoProblemTests.swift`, `FIXW_EditPreviewTests.swift`; `Tests/ProgramPackageTests/FIXW_MarkerLookImportTests.swift`; `Tests/MediaEngineTests/FIXW_ObjectVideoRecoveryTests.swift`; `Tests/PersistenceTests/FIXW_MigrationBackupTests.swift`. No existing test was edited. No source-rule test (`FIXO_`, `FIXQ_`, `FIXS_`, `FIXU_`) conflicted.

## Text for the coordinator to place in docs (not edited here)

Change log: "FIX-W: a marker crossed between the last observer tick and a pause, Stop or the clip's end now runs once (and a marker that ran just before a pause no longer runs again on resume); removing a mirror shifts the key notes and signal chains with it; an imported marker selects a Look imported under a new id; a video object that cannot open or is past the limit of four is named in the media banner; Edit's Broadcast and Stage previews use the screen's own Look and the stage preview has section names; a library whose history cannot be read is refused with the copy message instead of being migrated unprotected."
Known issues (unnumbered): a video object's in and out marks are still ignored (REVIEW-5 L2, not in scope); a key note kept but hidden after a destination goes from Fill and Key to plain (accepted); the unavailable text covers both "could not be opened" and "stopped playing" because the player set reports them together.
Data dictionary: no change (no schema or stored field changed).
Hands-on entries: (a) play a clip with a marker 0.3 s before its end and one with a marker just before a Pause: the marker runs once; (b) put a video object on a slide with its file on an unplugged disk, go live: the banner names the clip; replug, publish again: the banner goes; (c) five video objects on one slide: the fifth is named; (d) in Edit give the broadcast screen its own Look and press Broadcast: it matches the broadcast window; add Section to a stage layout: Edit's Stage shows it; (e) remove the first of two mirrors that have key notes and chains: the second keeps its own.

## Not verified

- The App-side wiring (`syncObjectVideos`, the availability callback, `editPreviewScene`) is compiled by `check.sh` but has no unit test; it needs a hands-on pass (entries b to d above).
- The marker observer against a real player and the 50 ms timer (KI-243, KI-251) is not measured.
- Item 6: see the last bullet of that item.
