# MEDIA-005 / MEDIA-006 report: audio library and audio routing

Levels: Implemented; Unit Tested; Simulated (silent app run). Not Hardware Verified; no sound was played.

## Built
See `docs/features/MEDIA-005-audio.md` (behaviour, HW-08 statement, design). Files: `Domain/AudioTypes.swift`; `MediaEngine/AudioCuePlayer.swift`, `AudioDeviceCatalog.swift`, `AudioLevelMeter.swift`, `VideoPlayerSource.swift` (+`audioOutputDeviceUniqueID`), `MediaRegistry.swift` (+`setAudioOutputDevice`); `OperatorCore/AudioModel.swift`; `App/Sources/AudioPanel.swift`, `AudioSupport.swift`, `AppModel.swift`, `ContentView.swift`; tests `OperatorCoreTests/AudioModelTests.swift`, `MediaEngineTests/AudioCueTests.swift`; the doc; `project.yml` unchanged (no entitlement/Info.plist needed).

## Test-first
Tests were written before any implementation. Recorded red output (scratch copy, `swift build --build-tests`): `cannot find type 'AudioOutputDevice' / 'AudioCuePlayer' / 'AudioDeviceCatalog' in scope`, `cannot find 'LevelAccumulator' / 'CoreAudioDeviceCatalog'`, `MediaRegistry has no member 'setAudioOutputDevice'`, `VideoPlayerSource has no member 'audioOutputDeviceUniqueID'`. Failures found while going green and fixed: a main-actor-isolated tap/completion closure trapped on the audio queue (moved to `nonisolated` factories); `playerTime(forNodeTime:)` raised before the first render; `.dataPlayedBack` is never signalled when rendering offline and `.dataConsumed` fires far too early, so offline end/loop is driven from the node clock; a position read after the loop flag changed; one of my own tests had the engine indices wrong.

## Commands and results
- `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests|MediaEngineTests'`: exit 0, `Test run with 350 tests in 57 suites passed`.
- `swift test --package-path Packages/WorshipFlowKit` (full): `Test run with 749 tests in 126 suites passed`.
- `./scripts/check.sh`: exit 0 (package tests 749, domain boundary clean, xcodegen, Debug app build, `== OK`). The other agent's SDIEngine work had finished by then.

## APIs verified against the SDK headers (MacOSX.sdk in Xcode 26.6)
`AVPlayer.audioOutputDeviceUniqueID` (AVPlayer.h, macOS 10.9+); `AUAudioUnit.deviceID` / `setDeviceID:error:` (AUAudioUnit.h); `AVAudioEngineConfigurationChangeNotification`, `enableManualRenderingMode:format:maximumFrameCount:error:`, `renderOffline:toBuffer:error:` (AVAudioEngine.h). Everything else compiled in Swift 6 mode against the SDK (Core Audio property selectors and `AudioObject*` listener functions, `AVAudioPlayerNode` scheduling and `playerTime`, `installTap`) and was exercised, but I did not read its header text. Taken on trust: behaviour (not signatures) of `setDeviceID` on a running engine (I stop the engine, set, restart), `AVPlayer` honouring the device while frames go through a video output, and that `.dataPlayedBack` fires on a real device (it does not offline).

## Exercised in the running app (Debug build, temporary `--library` and `--silent-audio`, scratch folder)
Launched three times, each under a minute, quit each time. Sound files were seeded with `sqlite3` (the open panel was not driven). With background app control: the Audio section rendered; the picker showed "System default (Mac mini Speakers)"; volume 5% (seeded); Play on "Hymn tone" worked, the row switched to Pause with a scrubber and Stop, the scrubber advanced to 0:06 and the meter bars moved. Not exercised in the app: pause/resume, seek by dragging, loop and overlap switches, mute, Stop sound, choosing another device (menu popups cannot be clicked in background mode), Refresh, unplugging a device, relaunch persistence, show Stop/Clear, foreground-video routing, the real hardware path. A third launch (after the meter-hold fix) could not be driven because the owner's Space changed to a full-screen app; it was quit. Not seen in the app: the meter fix (a poll with no tap data keeps the previous value); the first run's meter flickered to empty between taps in silent mode, the fix is covered only by unit tests of the accumulator/poll.

## Sound
None. Every app run used `--silent-audio` (rendered to nowhere); no real device played anything, the system volume and default device were not touched. So whether a real cue is audible or meters on hardware is **not verified**; the meter moving was seen only on the silent offline path.

## Screenshot
`AI/reports/MEDIA-005-audio.png` (874 px wide, from the first silent run, before the meter-hold fix): right column scrolled to Audio: Output picker, speaker button and 5% volume slider, two thin meter bars with green fill on the upper one and a peak tick, "Hymn tone 0:12" highlighted with a scrubber part way along, Ambient bed and Chime below, the Screens panel beneath. The top left shows a stray Edit menu fragment, an artifact of the background capture, not of the app.

## Deviations and unverified
- Added a file to Domain (`AudioTypes.swift`) so the model and engine share two value types; not listed among files I own.
- Added the `--silent-audio` launch argument (not in the brief).
- Overlap rule is my interpretation: an ordinary cue replaces other ordinary cues only; overlap cues are untouched. Loop is not persisted; overlap, volume, mute and device are.
- Scratch-dir incident: I first synced my package copy into `scratchpad/pkg`, which turned out to be the other agent's directory; my rsync and one build ran there for a moment. Its files were rewritten by that agent afterwards; I did not delete anything of theirs, but I cannot rule out one of its runs failing once. Mine moved to `scratchpad/wf-media005-pkg`.
- `~/Library/Preferences/org.worshipflow.app.plist` existed before (not created by me); nothing was created in Application Support or Saved Application State.
- Not measured: CPU of the meter timer, long cues, many overlapping cues, 44.1 vs 48 kHz devices, Bluetooth/aggregate devices, devices with more than two channels (meter shows the first two), accessibility of the new controls beyond labels.
- Docs other than the feature doc (known issues, change log, status, handoff) were not updated.
