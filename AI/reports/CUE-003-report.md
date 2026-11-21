# CUE-003 report: MIDI devices (CoreMIDI) behind a protocol

Feature: CUE-003 (AUTO-03, AUTO-04). Levels: Implemented; Unit Tested; Simulated (fake ports and CoreMIDI loopback in the test process). **Not Hardware Verified**: no physical MIDI device has been seen. Not Live-Service Verified. Behaviour and decisions: `docs/features/CUE-003-midi-devices.md`.

## Files

Created in `Packages/WorshipFlowKit`: `Sources/MIDIIO/{MIDIPorts,MIDIWire,Broadcaster,FakeMIDIPorts,CoreMIDIPorts,MIDIRouter}.swift`; `Tests/MIDIIOTests/{MIDIWireTests,FakeMIDIPortsTests,MIDIRouterTests,CoreMIDILoopbackTests}.swift`; `docs/features/CUE-003-midi-devices.md`. Deleted: both `Placeholder.swift` of MIDIIO. Not touched: `Package.swift`, `project.yml`, `App/`, `Sources/OperatorCore`, `Sources/CueEngine`, `Sources/RemoteControl`, `docs/UI`, `docs/adr`. Nothing committed.

## CoreMIDI APIs used and headers checked

Headers read under `$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreMIDI.framework/Headers` (`MIDIServices.h`, `MIDIMessages.h`) and the Swift overlay `usr/lib/swift/CoreMIDI.swiftmodule/arm64e-apple-macos.swiftinterface`:

- `MIDIClientCreateWithBlock` (notify block, "called on a thread chosen by the implementation"; `MIDINotifyProc` says notifications use the run loop of the thread that first called MIDIClientCreate), `MIDIClientDispose`, `MIDINotification.messageID` with `kMIDIMsgSetupChanged / ObjectAdded / ObjectRemoved / PropertyChanged`.
- `MIDIInputPortCreateWithProtocol` (macOS 11, replaces deprecated `MIDIInputPortCreate[WithBlock]`), `MIDIOutputPortCreate` (not deprecated), `MIDIPortConnectSource`, `MIDIPortDisconnectSource`, `MIDIPortDispose`.
- `MIDIDestinationCreateWithProtocol`, `MIDISourceCreateWithProtocol`, `MIDIEndpointDispose` (replace deprecated `MIDIDestinationCreate[WithBlock]`, `MIDISourceCreate`).
- `MIDISendEventList` (timestamp 0 = now) and `MIDIReceivedEventList` (header: timestamp 0 is NOT now, so `mach_absolute_time()` is passed), replacing deprecated `MIDISend`, `MIDIReceived`.
- `MIDIReceiveBlock` (`const MIDIEventList *`, refCon = the connRefCon passed to `MIDIPortConnectSource`), `MIDIEventList`, `MIDIEventPacket`, `MIDIProtocolID kMIDIProtocol_1_0`. Swift overlay: `UnsafePointer<MIDIEventList>.unsafeSequence()`, `UnsafePointer<MIDIEventPacket>.words()`, `UnsafeMutableMIDIEventListPointer(_:wordSize:inProtocol:).append(timestamp:words:)`.
- `MIDIGetNumberOfSources/Destinations`, `MIDIGetSource/Destination`, `MIDIObjectGetIntegerProperty`, `MIDIObjectGetStringProperty` (string is retained: `takeRetainedValue`), `MIDIObjectFindByUniqueID`, `MIDIObjectType` (`source`, `externalSource`, `destination`, `externalDestination`); properties `kMIDIPropertyUniqueID`, `kMIDIPropertyOffline`, `kMIDIPropertyDisplayName`, `kMIDIPropertyName`, `kMIDIPropertyManufacturer`; status codes `kMIDIServerStartErr`, `kMIDIMessageSendErr`, `kMIDINotPermitted`, `kMIDIObjectNotFound`, `kMIDIUnknownEndpoint`, `kMIDIIDNotUnique`.
- UMP layout (`MIDIMessages.h` `MIDIMessageType`, `kMIDIMessageTypeChannelVoice1 = 0x2`, word layout of `MIDI1UPChannelVoiceMessage`); word counts per message type come from the UMP specification (not in the header) and are tested.

No deprecated CoreMIDI call is used; the build shows no warnings from MIDIIO.

## Commands (exit status)

- Red first: `swift test --package-path Packages/WorshipFlowKit --filter MIDIIOTests` with tests and no sources: exit 1, "cannot find type 'MIDIRouter' / 'FakeMIDIPorts' in scope" (the first attempt failed for the wrong reason, an empty target, and was fixed with a stub before recording). Order caveat: the pure, fake and router tests were written and seen failing before any implementation; `CoreMIDIPorts` and its loopback tests were written after the contract and fake existed, so their first run is the evidence (they found the notification problem below).
- Real package, `swift test --package-path Packages/WorshipFlowKit --filter 'MIDIIOTests|CueEngineTests'`: exit 0, `Test run with 244 tests in 30 suites passed after 6.091 seconds` (43 of them MIDIIO). The 10 real-CoreMIDI loopback tests **ran**, none skipped.
- Full `swift test --package-path Packages/WorshipFlowKit`: exit 0, `Test run with 1934 tests in 292 suites passed after 60.830 seconds` on the last run. Two earlier full runs failed: first with failures in `RemoteControlTests` (`HostPolicy`, `RemoteServer` timing; the other agent's files) and in my router tests, which timed out their 5 to 10 s waits while the main actor was busy under the full-suite load; the second again RemoteServer timing plus the same three router tests. I raised the router tests' wait ceiling to 30 s (they return as soon as the condition holds); the third full run was clean. Before the other agent's files compiled, I ran my tests in a scratch copy of the package (no RemoteControl); it has been deleted.
- `./scripts/check.sh` was not run (it needs xcodebuild and the app, which I was told not to touch).

## Decisions where the brief left room

See the feature doc: event-list API at protocol 1.0 only; one process-wide run-loop thread for every client (found by test: notifications never arrived on a client created on an ordinary thread, nor after the first client's thread ended); stable id is `kMIDIPropertyUniqueID`; per-call independent incoming streams (bounded, newest kept, drops counted); router polls the device list every 3 s as a safety net; virtual output and chosen destination are independent; own endpoints are hidden from the app's lists; `MIDIRouter.perform` throws `CueTargetError` so it fits `CueTarget.perform`; `CueEngine` was not changed.

## Not verified

- No physical MIDI device, USB, Bluetooth or network MIDI session was seen; real hot-plug and reconnect by unique id, devices that vanish mid-send, and unique-id stability across reboots are reasoned from the headers, not observed.
- No other application was used as the peer; loopback is between two CoreMIDI clients in one process (CoreMIDI still routes through its server).
- Timing, jitter and latency were not measured; timestamps are host time converted to seconds.
- The 10,000-message burst was sent at full speed in a loop and arrived complete and in order on this Mac; slower consumers drop the oldest by design.
- CoreMIDI callbacks allocate small arrays during conversion (`MIDIParser.parse`, `words()`): fine here, not proven real-time safe.
- Sandbox entitlements were not examined (the app is assumed unsandboxed for MIDI).
- Whether other apps (DAWs) can see and use "WorshipFlow In" and "WorshipFlow Out" was not checked. Leftover endpoints: each test closes its clients, and one test asserts the endpoints vanish; no check of the Mac's global MIDI list was made afterwards.
- Not wired into the app; no interface.
