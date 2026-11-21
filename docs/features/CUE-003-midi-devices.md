# CUE-003: MIDI devices (CoreMIDI) behind a protocol

Catalogue: AUTO-03 (MIDI input), AUTO-04 (MIDI output). Phase 3. No interface and no app wiring in this slice; nothing under `App/` or `Sources/OperatorCore` was touched.

Verification level: Implemented; Unit Tested; Simulated (fake ports, and real CoreMIDI loopback between two clients inside the test process). **Not Hardware Verified**: no physical MIDI device, USB or Bluetooth interface, or other application has been connected. Not Live-Service Verified.

Code: `Sources/MIDIIO` (CoreMIDI, Foundation, `CueEngine`). Tests: `Tests/MIDIIOTests`.

## Pieces

- `MIDIPorts` (protocol, `MIDIPorts.swift`): `sources()` / `destinations()` (`MIDIEndpointInfo`: stable `MIDIEndpointID`, name, manufacturer, `isOnline`), `connect(source:)` / `disconnect(source:)` / `connectedSourceIDs`, `send(_:to:)`, `publish(_:)` (out of the virtual source), `setVirtualEndpointsEnabled`, `makeIncomingStream()` (`AsyncStream<ReceivedMIDI>`: message, monotonic timestamp in seconds, source id), `makeChangeStream()` (devices appeared, disappeared or changed), `statistics`, `close()`.
- `FakeMIDIPorts`: in-memory implementation for tests and previews, with controls to add, remove and take endpoints offline, emit messages or raw bytes, and record what was sent.
- `CoreMIDIPorts`: the real implementation. Uses the event-list API only (see the report for the declarations checked), always with `kMIDIProtocol_1_0`, so the system converts whatever a device speaks to MIDI 1.0 channel voice words (UMP type 2).
- `MIDIWire`: pure conversion between UMP words or raw bytes and `MIDIMessage`. Byte decoding goes through the engine's `MIDIParser`, so there is one definition of a message (note-on velocity 0 is a note-off; running status works).
- `MIDIRouter` (`@MainActor`): binds a `MIDIPorts` to a `MIDIBindingSet`.

## Behaviour

- **Receiving**: CoreMIDI's callback only converts words to `MIDIMessage` values and hands them to subscribers (`Broadcaster`: a short lock and `AsyncStream.yield`). No actor state is touched there. System exclusive, clock, active sensing, aftertouch, pitch bend, MIDI 2.0 events and anything malformed are ignored and counted (`statistics.ignoredEvents`).
- **Bounded memory**: each subscriber's stream holds at most `incomingCapacity` messages (default 65,536). If a consumer stalls the **oldest** are discarded and counted (`statistics.droppedMessages`).
- **Virtual endpoints**: off by default; when on, "WorshipFlow In" (a destination other apps send to) and "WorshipFlow Out" (a source other apps listen to). Messages arriving at the destination reach the router like any other (`source == nil`). The app's own endpoints are not listed by its own `sources()` / `destinations()`.
- **Router in**: messages go through `MIDICommandFilter` and the binding set, so a held pad fires once and a note-off never fires anything. The command is delivered to the `onCommand` closure on the main actor, in arrival order. Timestamps are CoreMIDI host times converted to seconds.
- **Learn**: `await router.learn()` returns the next message that can become a binding, with the pattern `MIDIPattern.learned(from:)` makes from it. While learning nothing runs. A note-off cannot be learned and is skipped. Cancelling returns nil.
- **Remembered device**: `selectSource(id, knownName:)` stores the stable id. If the device is absent or offline the state is `.waiting(lastKnownName:)`; when it returns (by id) the router connects again and reports `.connected`. A device that is present but cannot be opened is `.failed(message:)` and retried on the next change. The system's device notifications drive this, plus a polling safety net (`pollInterval`, default 3 s) so a missed notification cannot leave a returned device unconnected.
- **Router out**: `perform(.midiOut(m))` (and `send(_:)`) sends to the chosen destination and, when the virtual endpoints are on, also out of the virtual source. An invalid message, an offline destination, a destination that refuses, or no output at all throws a `CueTargetError` with text for the operator and sets `lastError`. Sending asks CoreMIDI to send and returns; it never waits for a device.

## Decisions the brief left open

- **Event-list API with protocol 1.0 only.** The deprecated packet-list API is not used. Requesting MIDI 1.0 means CoreMIDI converts MIDI 2.0 devices for us, so the converter handles one word type. Type-4 words that still arrive are counted as ignored.
- **Notifications need a run loop that never ends.** CoreMIDI delivers notifications on the run loop of the thread that first created a client in the process. A client created on a thread without a running run loop heard nothing, and once the first client's thread ended, later clients heard nothing either (both seen in this slice's tests). So every client is created on one process-wide thread, started on first use, that runs its run loop for the life of the process.
- **Stable id = `kMIDIPropertyUniqueID`.** Resolved with `MIDIObjectFindByUniqueID`, and checked to be an endpoint of the right direction (a device or entity can share the id space). `connectedSourceIDs` drops a connection whose endpoint vanished or was replaced.
- **Multi-subscriber streams.** `makeIncomingStream()` returns an independent stream per call, so the router can be stopped and restarted and a future monitor can listen too. (A single `AsyncStream` would be terminated for good by cancelling its consumer.)
- **Virtual output and the chosen destination are independent.** If both exist, a `midiOut` goes to both; the operator error only concerns the chosen destination.
- **Own endpoints hidden** from the app's own lists, so a source choice can never be the app feeding itself.
- **No Info.plist or entitlement change** is needed for CoreMIDI outside the sandbox. If the app is ever sandboxed, check whether `com.apple.security.device.audio-input` or a MIDI-related entitlement is required; not checked here.

## Not verified

No physical MIDI device was seen. Hot-plug of real USB, Bluetooth and network MIDI, a device that disappears while sending, other applications' behaviour (a DAW sending to "WorshipFlow In", reading "WorshipFlow Out"), timing and jitter, system exclusive, MIDI 2.0 devices and sleep/wake behaviour are untested. The app is not wired to any of this yet.
