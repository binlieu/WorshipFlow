# UI-007d report: mark in and mark out, markers, and marker actions in Cues

Feature IDs: UI-007d, MEDIA, CUE-33 (playback markers). Briefs: `AI/specs/UI-006-mode-features.md`, `AI/specs/UI-007-features-on-v15.md` (row UI-007d). Base: `0f89ce3`. Model: Sonnet. Branch `worktree-agent-a29aab43a5a373936`.

Levels reached: **Implemented, Unit Tested**, and **Simulated** only where a real AVFoundation player was driven by tests (below). Nothing here is Hardware Verified or Live-Service Verified, and no feature was exercised by hand in the running app (see "Not verified").

## What was built

1. **Mark in and mark out, honoured by live playback.** A clip chosen for playing (bin tile, dock, Cues action, folder, playlist item, background or foreground) carries its bin item's marks (`MediaSelection.forPlayback`). `MediaTransport` plays only the part between them: it starts at the in mark, a clip that does not loop ends at the out mark (position holds there, `ended`), a loop wraps from the out mark to the in mark, a seek stays inside the marks, Stop returns to the in mark. Marks that cannot work (in not before out, not inside the clip) are ignored, each judged on its own; a clip with no marks behaves exactly as before. The real player follows: `VideoPlayerSource` seeks to the in mark before it plays, stops at the out mark with `forwardPlaybackEndTime` (and reports its end once), and a loop inside marks is an `AVPlayerLooper` over that time range. Decoding stays on AVFoundation's queues; nothing new runs on the main thread. A clip chosen again with other marks is opened again by the registry; a clip that is on air keeps the marks it started with (editing never changes Live). A slide's own background video is played with the marks its bin item had when the slide went live; the slide stores none (`MediaSelection` encodes no marks, so stored slides and packages are unchanged).
2. **Marks in the bin player (preview).** Play starts at the in mark when the playhead is before it or at/after the out mark; the preview player stops at the out mark (or loops back to the in mark); Restart and Stop go to the in mark. Scrubbing is free, so marks can be set anywhere.
3. **Mark in / Mark out / Add marker in the Media strip** (design 05), a "Marks and markers" popover (type a time such as `1:05.5`, Set at playhead, Clear; each marker's time and name are editable, jump to it, delete; time order) and right-click Clear on the two buttons. For a video the strip's second-row room holds the three buttons and the two ways to send it live become a "Send live" menu in the first row; a picture and a sound keep their buttons. Hot-folder items are not in the library, so their buttons are disabled with the reason. Sounds and pictures get no mark buttons: the audio player does not honour marks (see "Not built").
4. **Playback markers in Cues (CU-33).** The design's "Playback markers" section below a macro's actions: a clip chooser, a timeline (the part that plays, one line per marker), the marker list, and the action list editor (the macro one, in a new `marker` context: no action that moves the show, directly or through a macro, because a looping clip would advance the show by itself).
5. **Live firing through the one command path.** `MediaMarkerModel` watches the live layers with a `MarkerFeed` built on the existing `MarkerTracker`. A marker fires once per crossing; not on a seek over it; not when the position steps back by less than a frame; not twice for a seek back and forth within one frame; a marker at the in mark fires at the start, one before the in mark or after the out mark never; a loop fires each marker once per pass (the one at the out mark with the pass it ends); a clip played again is a new pass; markers added, moved or deleted while playing are armed by their place; never while not live and never from the preview player. A reached marker becomes `OperatorCommand.markerReached`, submitted with the new `CommandSource.marker`: it is serialised with every other source, logged in Activity ("marker "Lower third on" at 00:12.5 in clip: 2 actions"), refused while the Hardware Test runs (like MIDI, remote and schedule), and re-checked at run time for a move of the show.
6. **The observer exists only while needed.** `needsObserver` is true only while a live layer plays (not paused, not ended) a video that has markers. The app's timer (`TimerMarkerScheduler`, 50 ms, `.common` run-loop mode) is started and stopped by that rule; nothing ticks while idle, for a clip without markers, with the screens stopped, or in the preview. No `TimelineView` was added.

## Verification levels per feature

| Feature | Level | Evidence |
|---|---|---|
| Transport marks (pure) | Unit Tested | 14 tests, hand-moved clock |
| Player honours marks | Unit Tested, Simulated | 4 tests with a real AVPlayer and a generated movie (first frame at the in mark, out mark stops and reports the end once, a loop inside marks never shows the outside, registry opens a marked clip) |
| Layers, readouts, sample | Unit Tested | model tests with a fake clock |
| Bin preview marks | Unit Tested (model, fake player); adapter Implemented | AVFoundation adapter (`BinPlayerSupport.swift`) not unit tested |
| Marker feed (fire rules) | Unit Tested | 17 tests, injected samples |
| Marker model, observer lifecycle | Unit Tested | fake scheduler, fake clock, injected positions |
| Command path (source, order, Activity, refusals) | Unit Tested | 8 tests |
| Media strip, popover, Cues section | Implemented | compiled in Debug and Release; see "Not verified" |

## Features not built

- **Marks for sounds (audio cues).** The store accepts marks on audio, but `AudioCuePlayer` and the audio list do not honour them; building that is a change to the audio engine, outside this slice. The Media UI offers marks for videos only, so no control is dead; `setMarkIn` on a sound is refused with that sentence.
- **Markers and marks on a slide's own background video are honoured for marks only** (resolved when the slide goes live); markers do not fire on a slide-own background, because the marker observer reads the layers `MediaModel` holds (clips started from the bin, dock, Cues, folders and playlist). Needs the registry to name the clip it plays; not done.
- **Marker actions for the audio of a video clip** none; actions are the cue actions (CU-28 loop and dissolve, CU-29 stage layout remain open as before).
- Markers on hot-folder items (not stored in the library).

## Still missing in storage

Nothing. Marks and markers use the v15 columns and `mediaMarker`; no schema change was made. (The brief's "missing in storage" list is empty.)

## Decisions and deviations

- **Position source.** The observer samples the transport the player is driven by (`MediaModel.playbackSample`: the clip's `MediaTransport` read at the injected clock, the same value the registry's `VideoPlayerSource` is given), not `AVPlayer.currentTime`. The brief says "the real player position"; the player is slaved to this clock and the registry's stall watchdog re-seeks it, but how far the decoded picture lags the clock was not measured. Position and "a seek" are injected in tests. This is the item to verify on hardware.
- **Marks are read when a clip starts.** A marker list is live (edits are armed at once); marks are not (they would restart a clip on air).
- **A marker's actions cannot move the show** (same rule as a slide's), saved and checked again when it runs.
- **Seeking the live clip stays inside the marks; seeking in the preview does not** (so a mark can be set anywhere).
- Cause of one scare: after the change to `MediaSelection`'s layout, an incremental SwiftPM build kept a stale `Persistence` object and returned garbage in the new fields; `swift package clean` and a full build fixed it (a clean build is what the gate does).

## Tests

New tests: **81** in 8 suites, all `UI007d_*`:
`UI007d_MediaTransportMarksTests` (13, MediaRulesTests), `UI007d_PlayerMarksTests` (4, MediaEngineTests, real AVPlayer), and in OperatorCoreTests `UI007d_MarkerFeedTests` (17), `UI007d_MediaMarksModelTests` (11), `UI007d_MediaTimeTextTests` (3), `UI007d_MarkerModelTests` (11), `UI007d_MarkerCommandPathTests` (8), `UI007d_PreviewMarksTests` (8).
Test-first: the transport tests were run against a stub that accepted marks and ignored them, and failed for the right reason (positions at 0, no end at the out mark, no wrap). The player, feed, model, command path and preview tests were written before their types existed and failed to compile for the missing API (`extra argument 'markIn'`, unknown `PlaybackSample`, `MarkerFeed` ...), then passed once implemented. No existing test was edited.

## Shared-file lines and public additions

- `Domain/MediaTransport.swift`: `markIn`, `markOut`, `start`, `end` and an `init` with defaulted marks (additive; old stored transports decode; unmarked transports behave exactly as before, the existing transport tests pass unchanged).
- `Domain/MediaLayers.swift`: `MediaSelection.markIn/markOut` (not coded: hand-written `Codable` keeps the stored shape), `forPlayback(_:)`, `withMarks(of:)`; `setBackground` / `startForeground` pass them to the transport.
- `MediaEngine/VideoPlayerSource.swift`, `MediaRegistry.swift`: marks passed to the player; the registry reopens a clip chosen with other marks.
- `OperatorCore/MediaModel.swift`: `forPlayback` at the five places a clip is chosen, `playbackSample`, per-layer start and seek counters, `onPlaybackChange`, readout `rangeStart`/`rangeEnd` (defaulted).
- `OperatorCore/LiveMedia.swift`: optional `resolve` parameter on `effective` / `playing`.
- `OperatorCore/CueCommands.swift`, `CueModel.swift`, `CueEditing.swift`: `CommandSource.marker`, `OperatorCommand.markerReached`, its run (about 10 lines in `execute`), `.marker` in `refusal(for:)`, `CueActionContext.marker`.
- `OperatorCore/MediaPreviewModel.swift`: `PreviewPlayback.setMarks(in:out:)` (default no-op, so existing fakes compile), `startPosition`.
- `App/Sources/AppModel.swift`: property `markers`; one block creating `MediaMarkerModel` after `self.media = media`; three lines in `media.onAssetsChange` (preview marks, read markers); `effectiveMedia()` freezes the marks of a slide's own background video. Not touched: key monitor, `KeyRouting`, section move/remove, Media collections app-state writes.
- `App/Sources/MediaStrip.swift`, `MediaTransportStrip.swift` (scrubber range), `BinPlayerSupport.swift`, `CuesEditors.swift` (the 142 pt room now holds the section), debug hooks `UISnapshotMediaDesign.swift`, `CuesDesignCapture.swift` (marks and three markers in the captures).
- New files: `OperatorCore/MediaMarkerFeed.swift`, `MediaMarkerModel.swift`, `MediaTimeText.swift`, `MediaModel+Marks.swift`; `App/Sources/MediaMarksPopover.swift`, `CuesMarkers.swift`.
- Not touched: `MediaDockView.swift` (FIX-U). `WORSHIPFLOW.xcodeproj/project.pbxproj` was regenerated by xcodegen and is not committed.

## Docs entries for the coordinator

**Change log** (UI-007d): Media: mark in and mark out on a video (set at the playhead or typed, cleared), honoured by the bin preview and by live playback (start at in, stop or loop at out) through `MediaTransport` and the player; markers (add at the playhead, rename, move, delete, time order) in a popover of the player strip. Cues: the "Playback markers" section (clip chooser, timeline, marker list, action editor); a marker's actions run when live playback crosses it, once per crossing, through the one command path (source "marker", shown in Activity), never from the preview and never when seeking over it. The observer runs only while a clip with markers plays live.

**Known issues** (unnumbered):
1. Markers read the transport clock the player is driven by, not `AVPlayer.currentTime`; picture lag behind the clock is unmeasured.
2. Sounds (audio cues) do not honour marks; marks and markers are offered for videos only.
3. A slide's own background video honours marks (as they were when the slide went live) but does not fire markers.
4. Marks edited while a clip is on air apply from its next start.
5. The Show dock's clip controller (`MediaDockView`) still draws its scrubber over the whole clip; with marks the position is the clip's own time (FIX-U's file).
6. A marker's actions text written by a newer version reads as no actions and runs nothing (shown in the list); saving new actions replaces it.
7. Marker times are shown and typed to a tenth of a second; stored times keep any precision typed.
8. Hot-folder items have no marks or markers.
9. The observer's 50 ms interval bounds how late a marker can run, plus the player's own lag; not measured under load or on hardware.

**Hands-on checklist**:
- Media: select a video, move the player to 0:04, press Mark in; to 0:09, Mark out. Play in the player: it starts at 0:04 and stops at 0:09; with Loop it starts again at 0:04. Open the list button: type `0:06` for In; clear Out. Right-click Mark in: Clear.
- Add marker at 0:07, rename it "Lower third on", move it by typing a time, delete it; they stay in time order; relaunch: they are back.
- Take a slide live, press Live foreground on the marked clip: it starts at the in mark and the words return at the out mark; with the clip looping it restarts at the in mark. Edit the marks while it plays: nothing changes until it is started again.
- Cues: choose the clip in Playback markers; give a marker "Prop on"; try to add "Next slide": refused with the reason. Play the clip live: Activity says "marker ... at 00:07.0 in ...", the prop shows once; seek over the marker with the transport scrubber: it does not run; seek back and play past: it runs again. Play the clip in the Media preview: nothing runs.
- With a loop (Live background): the marker runs once per pass. Take the screens down (Stop): nothing runs.
- Activity Monitor or Instruments: with no marked clip playing there is no 50 ms timer from the app.
- Light and dark; VoiceOver on Mark in, Mark out, Add marker, the list button and each marker row.

**Feature spec updates**: MEDIA-010 (or a new MEDIA-012): marks, markers, the playback rule; CUE-001 / a new CUE entry: `CommandSource.marker`, `markerReached`, the marker observer rule and the no-transport rule.

## Check results

`swift test --package-path Packages/WorshipFlowKit` (after a clean build): 3339 tests in 527 suites (base about 3258, plus 81 new); the only failure was `MIDIRouterTests.aHeldPadFiresOnceUntilReleased` (timing under load, the known one). The domain-boundary grep was not run by hand (Domain imports unchanged). `xcodegen generate`, Debug build and Release build (arm64) by hand: exit 0, no errors; the Release binary holds no `UI_SNAPSHOT_(DIR|FIXQ)` strings (checked on the first Release build; the final Release build exited 0). The Media design capture ran once against a temporary library (picture looked at: Mark in, Mark out, Add marker fit and show their state). `scripts/check.sh` itself was not run end to end; its steps were run separately. The Cues capture and rectangle tables were not run.

## Not verified

- Nothing was driven by hand in the running app: the Media strip, the popover, the Cues section, light and dark, VoiceOver, keyboard reach and the text fields' behaviour were compiled but not looked at or clicked (the screen may be locked).
- The AVFoundation adapter of the bin player (`AVPreviewPlayer.setMarks`, out-mark stop, loop to in) was not run.
- Marker timing against the real picture and sound (point 1 of the known issues), on a connected output, and under load: Not Verified. Hardware Verified and Live-Service Verified: Not Verified.
- The rectangle comparison (`scripts/compare-rects.py`) and `scripts/design-map-media.json` / `design-map-cues.json` were not extended for the new controls.
