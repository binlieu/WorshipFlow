# Research: Phase 2 integrations (2026-11-20)

Done by a Sonnet research subagent. "Background knowledge" means not confirmed against a primary source in this pass.

## Syphon
- Repository github.com/Syphon/Syphon-Framework, maintained (last commit 2026-09-21). Latest tagged release is SDK 5 from 2019; the Metal classes are on `main`, probably not in that binary.
- BSD-style licence (clause count not confirmed).
- `SyphonMetalServer`: `initWithName:device:options:` and `publishFrameTexture:onCommandBuffer:imageRegion:flipped:`. Confirmed from the header.
- No `Package.swift`; no widely used Swift package found. Options: build `Syphon.framework` from its Xcode project, or vendor the source. Neither verified.
- Objective-C, not Sendable-annotated. Publish from the thread that owns the command buffer.
- Test clients: Syphon Simple Client, OBS (background knowledge).

## DeckLink SDK
- "Register and Download" at blackmagicdesign.com/developer. Current: Desktop Video 16.0 SDK (2026-04-08); runtime 16.5 (2026-10-30). No mention of macOS 27 found.
- Licence not read directly. Secondary sources say headers and dispatch source may be redistributed; Chromium, VLC and GStreamer vendor them. Confidence medium-low: read the licence block in the SDK files.
- Output: `CreateDeckLinkIteratorInstance` (NULL when the driver is absent, believed), `IDeckLinkOutput`: `DoesSupportVideoMode`, `EnableVideoOutput`, `CreateVideoFrame`, `ScheduleVideoFrame`, completion callback, `StartScheduledPlayback`, pre-roll. Mode `bmdModeHD1080p5994`. Formats include `bmdFormat8BitBGRA`.
- Keying: `IDeckLinkKeyer::Enable(isExternal)`, `SetLevel`; `BMDDeckLinkSupportsExternalKeying`. The app submits one frame with alpha and the card splits fill and key across a connector pair. Duo 2 at 1080p59.94 and the exact connector-mapping key: unconfirmed.
- Audio: `EnableAudioOutput`, `ScheduleAudioSamples`.
- Bridge with an Objective-C++ wrapper; COM-style reference counting; callbacks on SDK threads.

## Audio
- `AVPlayer.audioOutputDeviceUniqueID` routes one player to a Core Audio device UID (background knowledge).
- Enumerate with `kAudioHardwarePropertyDevices` and `kAudioDevicePropertyDeviceUID`; listen on the same property for devices appearing and disappearing.
- Cues and music: `AVAudioEngine` with `AVAudioPlayerNode`; meter with a mixer tap; choose the device with `kAudioOutputUnitProperty_CurrentDevice`; re-apply after a configuration-change notification. Taps run on real-time threads.

## Live inputs
- `AVCaptureDevice.DiscoverySession` with `.builtInWideAngleCamera`, `.external`, `.continuityCamera` (background knowledge).
- DeckLink inputs are reached through the DeckLink SDK, not AVFoundation (unconfirmed).
- `AVCaptureVideoDataOutput`, 32BGRA, Metal-compatible buffers, serial delegate queue.
- `NSCameraUsageDescription` plus the hardened-runtime entitlement `com.apple.security.device.camera`.
