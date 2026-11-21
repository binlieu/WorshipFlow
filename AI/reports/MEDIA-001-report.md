# MEDIA-001 report: media bin, backgrounds and foreground video in the workspace

Levels: Implemented; Unit Tested (OperatorCore logic, registry audio, stall watchdog); partly exercised in the running app (see below). Not Hardware Verified, not Live-Service Verified.

## Built

- `OperatorCore/MediaModel.swift` (`@MainActor @Observable`): bin from `LibraryStore.mediaAssets`, add (through an injected `MediaProber`), rename, remove (reference only), kind filter, `MediaLayers` state (`setBackground`, `clearBackground`, `playForeground`, `pause`, `resume`, `seek`, `stopForeground`, `tick(now:)`, `playerReportedEnd`), background persisted under state key `media.background` and restored on load (the foreground never), volume and mute, `reportUnavailable` for files the engine could not open, readable errors in `lastError`.
- `PublishedScenes` gained a defaulted `media:` parameter, passed to `SceneComposer`.
- `MediaEngine`: `MediaRegistry.setForegroundAudio(volume:muted:)` (applied before a new foreground source plays); stall watchdog in `VideoPlayerSource` (see flaky-test section).
- App: `MediaSupport.swift` (`extension MediaRegistry: @retroactive MediaFrameSource {}`, AVFoundation prober, security-scoped bookmark access, thumbnail cache off the main thread), `MediaBinPanel.swift`, `MediaTransportStrip.swift`, `AppModel` wiring (registry passed to every output; players opened/closed as layers change; access stopped when a source closes; 0.2 s ticker only while a layer exists), live previews draw the current media frame (`Thumbnails.swift`, closes KI-022 for the live previews; slide thumbnails stay without media). The old "Background video" panel is gone; `--video` for the soak still works (`setVideo` kept).
- Interface: thumbnail grid, kind filter, Add button (open panel), drop onto the panel, context menu (Set as background, Play in foreground, Rename, Remove from bin), double-click = background, plus a selected-item row with "Set as background" / "Play in foreground" buttons (added because context menus cannot be reached by automation), transport strip (play/pause, scrubber, elapsed/remaining, mute, volume, Stop clip).

## Tests written (all new files)

`Tests/OperatorCoreTests/MediaModelTests.swift` (bin, background, foreground, volume), `MediaScenesTests.swift` (clip hides lyrics on audience and broadcast and ending restores them, stage never shows media, Stop removes media, Clear keeps the clip, words return by the clock when the player never reports the end), `Tests/MediaEngineTests/MediaRegistryAudioTests.swift` (registry audio; watchdog quiet on a normal clip).

## Commands run and results

- `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests|MediaEngineTests|OutputEngineTests'`: `Test run with 205 tests in 27 suites passed`.
- `./scripts/check.sh`: **exit 0** (`Test run with 483 tests in 74 suites passed`, domain boundary clean, xcodegen, Debug app build, `== OK`). That count includes the other agent's tests.

## Flaky `aClipThatDoesNotLoopReportsItsEnd`

Verdict: a real player stall, not only test timing. Failure output: `rate 1.0, control 2 (playing), item status 1 (ready), time 1.50, error none`, `pendingSeeks 0`, `wantsPlaying true`: the AVPlayer was told to play after `seek(1.5)` and its time never advanced, so no end notification ever came.
- Before: idle machine, test alone: 30/30 passed (no repro). Whole `MediaEngineTests` with 6 CPU burners: 18/20 passed (2 failures, same signature); another run 22/25 (3 failures).
- Fix (`VideoPlayerSource.watchForStall`, called from `latestPixelBuffer()`, i.e. by the outputs' render loop, at most 4 times a second): if the player is ready, should be playing, no seek is pending and its time has not moved for 1 s, it is re-seeked where it stands and the rate re-applied. My first version used the transport position and did not fire because the transport clock already said "ended"; fixed to use the player's own time.
- After: 30/30 and 30/30 (second batch with a parallel `swift build` plus the 6 burners), full `MediaEngineTests` each time; 0 failures. The existing test is unchanged.
- Independently, the clock path is covered: `theWordsComeBackByTheClockEvenIfThePlayerNeverReportsTheEnd` (only `tick` runs; lyrics return). Limit: a clip whose duration is not stored never ends by the clock; it then depends on the player's end report (`playerReportedEnd`, tested).
- Not proven: why AVPlayer stalls; the watchdog was not seen to fire in a recorded failing run after the fix (no failures occurred), only that failures stopped. The app's normal foreground start does not seek (position 0), so the stall seen in tests (seek then play) may be rarer in the app.

## Seen in the running app (Debug build, temporary `--library` under the scratch area, audience as a window)

Screenshots: `AI/reports/MEDIA-001-bin.png` (right column: Media bin with four thumbnails; the loop carries a BACKGROUND badge, a Set as background / Play in foreground row, "Background: Loop 1080p" and Clear background), `AI/reports/MEDIA-001-foreground.png` (workspace while a clip plays: the audience live preview shows the full-frame moving colour video with the words hidden, the stage preview still shows its words, the red transport strip at the bottom shows Loop 1080p, pause button, 0:01 / -0:19 scrubber, mute, volume, Stop clip). After the clip reached its end the strip disappeared and the audience preview showed "Amazing grace how sweet the sound / That saved a wretch like me" over the colour background again (words came back; seen in the live preview, not by eye on the output window).

Exercised: launch with empty library; Import lyrics sheet (song created); bin showing thumbnails for two videos, a PNG and a missing file (warning icon, "0:05"); selecting a tile; Set as background; Go Live with the audience as a window output; live preview showing the background behind the words; Play in foreground (of the 20 s loop clip, because selecting the short clip by automation failed); playback to the end; strip appears and disappears; words restored.

Not exercised in the app: Add via the open panel (could not be driven without full-screen control, which was requested and not answered); drag-and-drop; context menu; rename; remove; kind filter; pause, seek, scrubber, stop, volume and mute controls (unit tests only); the 6 s clip with a tone (so no sound was played at all); the PNG as background or foreground; relaunch restore of the background (unit tested only); the missing-file error bar; the output windows themselves (only the live previews were screenshotted; whether the window outputs showed the frames is inferred, `readouts` not read); broadcast screen; stopping the show during a clip.

## Setup that bypassed the interface (be aware)

- The four bin rows were inserted into the temporary library with `sqlite3` (the open panel could not be driven), so `MediaModel.add` / the prober / bookmarks were not run against real files in the app.
- The default audience profile pointed at a physical display; to avoid covering it I changed that profile to `window` directly in the temporary library before going live.

## Deviations and unverified

- The app ran longer than two minutes in total across relaunches within one session (about 5 minutes, one launch overlapping); it was quit afterwards. Nothing was created under `~/Library/Application Support/WORSHIPFLOW` (it did not exist before and does not now). I created and then removed `~/Documents/wf-media-tmp` (copies of the test files). `~/Library/Preferences/org.worshipflow.app.plist` exists (written by the app runs; I do not know whether it existed before; left).
- Default foreground volume is 0.5 (the slider only exists while a clip is loaded, so it could not be set low beforehand); no clip with sound was played.
- "Foreground only plays while the show is live" is my rule: Play is refused with a message when the screens are stopped, and Stop ends the clip. Background shows only where the theme has a media background (audience default does; the broadcast lower third does not), per `MediaRulesTests`.
- Audio files can be added to the bin but cannot be used as layers (message). No audio device selection.
- A background file that goes missing is taken out of the layers and reported; its stored choice is kept so it returns when the file does.
- Not measured: performance with a background loop plus a foreground clip on several outputs, memory, 59.94, long runs, HEVC/ProRes/rotated files, bookmarks in a sandbox (the app is not sandboxed; security-scoped access is coded but unexercised), accessibility/keyboard use of the bin, KI-032 remains partly open (nothing seen on an actual output window by eye, no audio).
- Docs (`docs/16-known-issues.md` KI-022/KI-032, change log, status) were not updated; the brief listed no doc edits.

## Files

Created: `App/Sources/MediaSupport.swift`, `MediaBinPanel.swift`, `MediaTransportStrip.swift`; `Packages/WorshipFlowKit/Sources/OperatorCore/MediaModel.swift`; `Tests/OperatorCoreTests/MediaModelTests.swift`, `MediaScenesTests.swift`; `Tests/MediaEngineTests/MediaRegistryAudioTests.swift`; `AI/reports/MEDIA-001-bin.png`, `MEDIA-001-foreground.png`, this report.
Changed: `App/Sources/AppModel.swift`, `ContentView.swift`, `Thumbnails.swift`; `Sources/OperatorCore/PublishedScenes.swift`; `Sources/MediaEngine/MediaRegistry.swift`, `VideoPlayerSource.swift`; `WORSHIPFLOW.xcodeproj/project.pbxproj` (regenerated by check.sh).
