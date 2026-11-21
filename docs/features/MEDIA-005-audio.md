# MEDIA-005 / MEDIA-006: audio library and audio routing

Catalogue: MEDIA-05 (import, play from a list, level control, visible meter), MEDIA-06 (media audio to a chosen sound device). ADR 0005 decision 8. SDI audio embedding is out of scope until the DeckLink bridge exists.

Verification level: Implemented; Unit Tested (decisions, meter arithmetic, the player on an offline-rendered AVAudioEngine); Simulated (a silent `--silent-audio` app run). **Not Hardware Verified**: no cue has been heard on a real device through this code in a test, and the device-switch path (`setDeviceID`, configuration change) has not been exercised against a real device being unplugged.

## Behaviour

- Audio section in the right-hand column, under the media bin: the bin's sound files with length, play or pause, a scrubber while one sounds, Loop and Overlap switches per file, volume and mute, a two-channel level meter (RMS bar, peak tick, -60 to 0 dB), and an Output picker (system default, or a device by name with channel count; the default is marked).
- One cue at a time. A file marked **Overlap** may sound together with others: starting it stops nothing, and starting an ordinary cue leaves it playing. Pressing Play on a playing cue does nothing; on a paused one it resumes. Stop sound ends everything.
- **Stop (the show) stops cues; Clear and Clear all do not.** Only the change from live to stopped counts, so a sound check while the screens are stopped is not cut by unrelated show changes.
- Volume, mute, the Overlap marks and the output device are stored in the library (`appState` keys `audio.volume`, `audio.muted`, `audio.overlap`, `audio.device`, `audio.deviceName`). Loop is per run.
- An unreadable or damaged file: a message naming the file; a cue that was playing keeps playing.

## Programme audio device and rule HW-08

One setting, "programme audio device" (`AudioModel.programmeDeviceUID`, nil = system default). **Every audio signal the app plays goes down one path only: to that device, once.**

- Cues: each cue has its own `AudioCuePlayer` (AVAudioEngine) whose output unit is pointed at the device.
- Foreground video: `MediaRegistry.setAudioOutputDevice(uid:)` sets `AVPlayer.audioOutputDeviceUniqueID` on the foreground player (and on every later one before it plays). A background loop is always muted.
- There is no second copy anywhere: nothing is sent to a second device, to the screens' outputs or to SDI. Microphones and instruments stay on the mixer; the app does not mix them. If the programme device is a mixer input and the same audio also reaches the ATEM another way, that duplication is outside the app and is the operator's wiring (rule HW-08).
- A chosen device that is not connected: sound plays on the system default, the operator sees a message naming the device (and, if sound was playing, that it keeps playing), the choice is kept and is honoured again when the device returns. Choosing a device that is not connected is refused the same way (the choice is not stored).

## Design

- `Domain/AudioTypes.swift`: `AudioOutputDevice`, `AudioLevels` (Foundation only).
- `MediaEngine`: `AudioDeviceCatalog` protocol and `CoreAudioDeviceCatalog`; `AudioCuePlayer`; `LevelAccumulator`/`LevelBox`; `VideoPlayerSource.audioOutputDeviceUniqueID`; `MediaRegistry.setAudioOutputDevice`.
- `OperatorCore/AudioModel.swift`: `@MainActor @Observable` rules, behind `AudioDeviceListing` and `AudioCueEngine` protocols (the app adopts them for the real classes in `App/Sources/AudioSupport.swift`). Reuses `MediaTransport`.
- Threading: the meter tap only fills a lock-protected accumulator; a 20 Hz main-run-loop timer reads it. AVFoundation callbacks are built in `nonisolated` functions (a closure written in a main-actor method traps when an audio queue calls it; found by a test crash). A tap that delivered nothing since the last poll leaves the meter as it was.
- `--silent-audio` launch argument: every cue is rendered offline to nowhere (nothing is heard) while the meter and transport run, for checking the interface.
- No Info.plist or entitlement change: output needs none (the app is not sandboxed).

## Known limits

- Meter is for cues only, not for video sound. The meter shows the first two channels of the mix.
- Whether `AVPlayer.audioOutputDeviceUniqueID` is honoured while frames are pulled through `AVPlayerItemVideoOutput` has not been listened to.
- Switching device restarts the cue's engine and resumes from the same place; a short gap is expected.
