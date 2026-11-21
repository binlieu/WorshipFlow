// CUE-002b item 4: MIDI is off until the operator turns it on; chosen devices are remembered by stable id; incoming commands use
// the one command path; a lost device shows as offline and reconnects. FakeMIDIPorts only: no CoreMIDI in these tests.
import Testing
import Foundation
import CueEngine
import CueStore
import MIDIIO
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_MIDITests {
    let pad: MIDIEndpointID = 7
    let synth: MIDIEndpointID = 9

    struct Rig { var cue: CueModel; var show: FakeShow; var store: CueStore; var library: LibraryStore; var ports: FakeMIDIPorts; var made: Counter }
    final class Counter { var n = 0 }

    func rig(library: LibraryStore? = nil, ports: FakeMIDIPorts = FakeMIDIPorts()) throws -> Rig {
        let lib = try library ?? LibraryStore.inMemory()
        let store = CueStore(library: lib)
        let show = FakeShow()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { nil }),
                           clock: TestCueClock(), settingsStore: lib)
        let made = Counter()
        cue.midiPortsFactory = { made.n += 1; return ports }
        ports.addSource(id: pad, name: "nanoPAD2")
        ports.addDestination(id: synth, name: "Synth")
        return Rig(cue: cue, show: show, store: store, library: lib, ports: ports, made: made)
    }

    func waitUntil(_ what: String = "", _ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func bind(_ r: Rig, _ pattern: MIDIPattern, _ command: MIDICommand, name: String = "Pad") async {
        await r.cue.saveBinding(MIDIBinding(name: name, pattern: pattern, command: command))
    }

    @Test func midiIsOffByDefaultAndNothingIsCreatedUntilItIsTurnedOn() async throws {
        let r = try rig()
        await r.cue.start()
        #expect(r.cue.midi.isEnabled == false)
        #expect(r.cue.midiStatus.isEnabled == false)
        #expect(r.made.n == 0)
    }

    @Test func turningItOnCreatesThePortsOnceAndOffDisposesThem() async throws {
        let r = try rig()
        await r.cue.start()
        await r.cue.setMIDIEnabled(true)
        await r.cue.setMIDIEnabled(true)
        #expect(r.made.n == 1)
        #expect(r.cue.midiStatus.isEnabled)
        await r.cue.chooseMIDIInput(pad)
        await r.cue.setVirtualPorts(true)
        #expect(r.ports.virtualEndpointsEnabled)
        await r.cue.setMIDIEnabled(false)
        #expect(r.ports.connectedSourceIDs.isEmpty)
        #expect(r.ports.virtualEndpointsEnabled == false)
        #expect(r.cue.midiStatus.isEnabled == false)
    }

    @Test func theChoiceIsRememberedByStableIdAndBroughtBackAtLaunch() async throws {
        let library = try LibraryStore.inMemory()
        let first = try rig(library: library)
        await first.cue.start()
        await first.cue.setMIDIEnabled(true)
        await first.cue.chooseMIDIInput(pad)
        await first.cue.chooseMIDIOutput(synth)
        await first.cue.setVirtualPorts(true)
        first.cue.shutdown()

        let second = try rig(library: library, ports: FakeMIDIPorts())
        await second.cue.start()
        #expect(second.cue.midi.isEnabled && second.cue.midi.inputID == pad.rawValue && second.cue.midi.outputID == synth.rawValue)
        #expect(second.cue.midi.inputName == "nanoPAD2")
        #expect(second.made.n == 1)
        #expect(second.ports.connectedSourceIDs == [pad])
        #expect(second.ports.virtualEndpointsEnabled)
    }

    @Test func aBoundNoteRunsItsCommandThroughTheOnePathAndAHeldPadFiresOnce() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 62), .transport(.clear))
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        r.ports.emit(.noteOn(channel: 1, note: 62, velocity: 90), from: pad)
        r.ports.emit(.noteOn(channel: 1, note: 62, velocity: 90), from: pad)       // still held
        r.ports.emit(.noteOn(channel: 1, note: 99, velocity: 90), from: pad)       // not bound
        await waitUntil { r.cue.activity.contains { $0.source == .midi } }
        await r.cue.settled()
        #expect(r.cue.activity.filter { $0.source == .midi }.count == 1)
        r.ports.emit(.noteOff(channel: 1, note: 62, velocity: 0), from: pad)
        r.ports.emit(.noteOn(channel: 1, note: 62, velocity: 90), from: pad)
        await waitUntil { r.cue.activity.filter { $0.source == .midi }.count == 2 }
        #expect(r.cue.activity.filter { $0.source == .midi }.count == 2)
    }

    @Test func aPadPressedWhileTheOperatorsGoLiveIsRunningWaitsItsTurn() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 60), .transport(.next))
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        r.cue.submit(.goLive, from: .key)
        r.ports.emit(.noteOn(channel: 1, note: 60, velocity: 100), from: pad)
        await waitUntil { r.show.log.count >= 4 }
        await r.cue.settled()
        #expect(r.show.log == ["goLive begin", "goLive end", "next begin", "next end"])
    }

    @Test func aMacroBindingRunsTheMacro() async throws {
        let r = try rig()
        await r.cue.start()
        let timer = UUID()
        r.show.timers = [timer]
        let macro = Macro(name: "Start", steps: [.startTimer(timer)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        await bind(r, MIDIPattern(kind: .programChange, channel: 2, number: 5), .macro(macro.id))
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        r.ports.emit(.programChange(channel: 2, program: 5), from: pad)
        await waitUntil { r.show.log.contains("timer start") }
        #expect(r.show.log == ["timer start"])
    }

    @Test func aLostDeviceShowsAsWaitingAndReconnectsWhenItReturns() async throws {
        let r = try rig()
        await r.cue.start()
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        #expect(r.cue.midiStatus.source == .connected(name: "nanoPAD2"))
        r.ports.removeSource(id: pad)
        r.cue.refreshMIDI()
        #expect(r.cue.midiStatus.source == .waiting(lastKnownName: "nanoPAD2"))
        r.ports.addSource(id: pad, name: "nanoPAD2")
        r.cue.refreshMIDI()
        #expect(r.cue.midiStatus.source == .connected(name: "nanoPAD2"))
        #expect(r.cue.midiStatus.inputs.map(\.name) == ["nanoPAD2"])
    }

    @Test func learnTurnsTheNextNoteIntoABindingAndNothingRunsWhileLearning() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 48), .transport(.clear), name: "Existing")
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        let cue = r.cue
        async let learned = cue.learnBinding(command: .transport(.previous))
        await waitUntil { r.cue.midiStatus.isLearning }
        #expect(r.cue.midiStatus.isLearning)
        r.ports.emit(.noteOn(channel: 1, note: 48, velocity: 100), from: pad)        // the same pad as "Existing"
        let binding = await learned
        await r.cue.settled()
        #expect(binding?.pattern == MIDIPattern(kind: .noteOn, channel: 1, number: 48))
        #expect(r.cue.bindings.bindings.count == 2)
        #expect(r.cue.activity.allSatisfy { $0.source != .midi })                    // learning ran nothing
        #expect(r.cue.bindingConflicts.count == 1)                                   // and the clash is shown
        #expect(r.cue.notices.contains { $0.text.contains("Existing") })
        #expect(r.cue.midiStatus.isLearning == false)
    }

    @Test func learnCanBeCancelled() async throws {
        let r = try rig()
        await r.cue.start()
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        let cue = r.cue
        async let learned = cue.learnBinding(command: .transport(.next))
        await waitUntil { r.cue.midiStatus.isLearning }
        r.cue.cancelLearning()
        #expect(await learned == nil)
        #expect(r.cue.bindings.bindings.isEmpty)
    }

    @Test func deletingABindingStopsItRunning() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 61), .transport(.clear))
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        let id = try #require(r.cue.bindings.bindings.first?.id)
        await r.cue.deleteBinding(id)
        r.ports.emit(.noteOn(channel: 1, note: 61, velocity: 100), from: pad)
        try? await Task.sleep(for: .milliseconds(100))
        await r.cue.settled()
        #expect(r.cue.activity.allSatisfy { $0.source != .midi })
        #expect(try await r.store.midiBindings().isEmpty)
    }

    @Test func midiOutGoesToTheChosenDeviceAndSaysSoWhenMidiIsOff() async throws {
        let r = try rig()
        await r.cue.start()
        let macro = Macro(name: "Cue the band", steps: [.midiOut(.noteOn(channel: 1, note: 60, velocity: 100))])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        await r.cue.run(.runMacro(macro.id), from: .button)
        #expect(r.cue.notices.contains { $0.text.contains("MIDI is off") })
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIOutput(synth)
        await r.cue.run(.runMacro(macro.id), from: .button)
        #expect(r.ports.sent.map(\.message) == [.noteOn(channel: 1, note: 60, velocity: 100)])
        #expect(r.ports.sent.map(\.destination) == [synth])
    }

    @Test func aMessageFromAnotherAppOnTheVirtualPortRunsABinding() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 60), .transport(.next))
        await r.cue.setMIDIEnabled(true)
        await r.cue.setVirtualPorts(true)
        r.ports.emitToVirtualDestination(.noteOn(channel: 1, note: 60, velocity: 100))
        await waitUntil { r.show.log.count >= 2 }
        #expect(r.show.log == ["next begin", "next end"])
    }

    @Test func shuttingDownDisposesEverythingAndStopsListening() async throws {
        let r = try rig()
        await r.cue.start()
        await bind(r, MIDIPattern(kind: .noteOn, channel: 1, number: 60), .transport(.next))
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(pad)
        await r.cue.setVirtualPorts(true)
        r.cue.shutdown()
        #expect(r.ports.connectedSourceIDs.isEmpty && !r.ports.virtualEndpointsEnabled)
        r.ports.emit(.noteOn(channel: 1, note: 60, velocity: 100), from: pad)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(r.show.log.isEmpty)
    }
}

@Suite struct CUE002b_MIDITextTests {
    @Test func notesAreNamedWithMiddleCAsC4() {
        #expect(MIDIText.noteName(60) == "C4")
        #expect(MIDIText.noteName(61) == "C#4")
        #expect(MIDIText.noteName(0) == "C-1")
        #expect(MIDIText.noteName(127) == "G9")
    }

    @Test func patternsReadLikeTheDesign() {
        #expect(MIDIText.pattern(MIDIPattern(kind: .noteOn, channel: nil, number: 62)) == "Note D4")
        #expect(MIDIText.pattern(MIDIPattern(kind: .noteOn, channel: 3, number: 62)) == "Note D4 · ch 3")
        #expect(MIDIText.pattern(MIDIPattern(kind: .controlChange, channel: nil, number: 7)) == "CC 7")
        #expect(MIDIText.pattern(MIDIPattern(kind: .programChange, channel: 2, number: 5)) == "Program 5 · ch 2")
        #expect(MIDIText.pattern(MIDIPattern(kind: .noteOn)) == "Any note")
        #expect(MIDIText.pattern(MIDIPattern(kind: .controlChange, channel: nil, number: 7, valueRange: 64...127)) == "CC 7 · 64–127")
    }

    @Test func commandsNameTheirMacro() {
        let m = Macro(name: "Start worship set", steps: [])
        #expect(MIDIText.command(.transport(.next), macros: []) == "Next slide")
        #expect(MIDIText.command(.macro(m.id), macros: [m]) == "Macro · Start worship set")
        #expect(MIDIText.command(.macro(UUID()), macros: [m]) == "Macro · (deleted)")
    }
}
