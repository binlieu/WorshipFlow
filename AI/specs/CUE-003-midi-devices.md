# Brief: CUE-003 — MIDI devices (CoreMIDI) behind a protocol

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/MASTER-SPEC.md` rows AUTO-03 and AUTO-04, `docs/features/CUE-001-cue-engine.md`, `AI/reports/CUE-001-report.md`, `Sources/CueEngine/MIDIMessage.swift`, `MIDIBinding.swift`.

Catalogue: AUTO-03 (MIDI input), AUTO-04 (MIDI output). Phase 3. **No interface and no app wiring in this slice**: the owner is redesigning the interface, so nothing under `App/` or `Sources/OperatorCore` may be touched.

## Scope

A new target `Sources/MIDIIO` (CoreMIDI, Foundation, `CueEngine`). Delete both placeholders. Test first for every decision.

## What to build

1. `MIDIPorts` protocol: list sources and destinations (stable unique id, display name, manufacturer, online flag), observe devices appearing and disappearing, connect to chosen sources, send a `MIDIMessage` to a chosen destination, and deliver received messages as `MIDIMessage` values with a timestamp through a `@Sendable` callback or `AsyncStream`. A fake implementation for tests, and the real `CoreMIDIPorts`.
2. `CoreMIDIPorts`: a client with input and output ports; handles both the legacy packet list and the Universal MIDI Packet event list as the SDK on this Mac offers (check the CoreMIDI headers: use the non-deprecated API for the deployment target, macOS 15), converting MIDI 1.0 channel voice messages to and from `CueEngine.MIDIMessage` using its existing byte parser where bytes are involved; everything else (sysex, clock, active sensing) is ignored and counted, never crashes. Callbacks arrive on CoreMIDI's thread: do no work there beyond conversion and hand-off; no actor state touched.
3. A virtual destination named "WorshipFlow In" and a virtual source named "WorshipFlow Out" (so other apps on the Mac can drive or follow the app without hardware), switchable on and off.
4. `MIDIRouter`: ties `MIDIPorts` to a `MIDIBindingSet`: received messages become commands through the engine's binding rules (held pad fires once, and so on), delivered on the main actor in order; "learn" mode returns the next message; a chosen device that disappears is remembered and reconnected by its stable id when it returns, with a reported state in between. Outgoing: a `CueAction.midiOut` goes to the chosen destination; an offline destination reports an operator-readable error and never blocks.
5. Tests: everything through the fake; plus real-CoreMIDI loopback tests that create a virtual source and destination inside the test process, send every message kind on every channel, and assert what arrives (these need no hardware; if CoreMIDI is unavailable in the test environment, skip with a recorded reason rather than fail). Running status, note-on velocity zero, out-of-range values, a burst of 10,000 messages (no loss, order kept, bounded memory).
6. Docs: `docs/features/CUE-003-midi-devices.md`.

## Do not modify

Anything outside `Sources/MIDIIO`, `Tests/MIDIIOTests`, the feature doc, and source-compatible additions to `Sources/CueEngine` if genuinely needed. Not `Package.swift`, `project.yml`, `App/`, `Sources/OperatorCore`, `docs/UI/`, `docs/adr/`. Another agent is working at the same time in `Sources/RemoteControl`; touch nothing there. If a full `swift test` fails solely because of its unfinished files, run your tests in a uniquely named scratch copy outside the repository (`wf-cue003-<random>`) and retry the real run before finishing.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps. No entitlement or Info.plist change is expected for MIDI on macOS outside the sandbox; if you find one is needed, say so and do not edit `project.yml`. Do not commit or change git state. Do not consult any advisor tool. Do not download anything. Do not request full computer control. Play no sound.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'MIDIIOTests|CueEngineTests'` passes in the real package (or you state exactly why not and give the scratch result). Paste the summary line.
2. `AI/reports/CUE-003-report.md`: files, which CoreMIDI APIs you used and where you checked their declarations, decisions, commands with exit status, and everything not verified (in particular: no physical MIDI device has been seen).
