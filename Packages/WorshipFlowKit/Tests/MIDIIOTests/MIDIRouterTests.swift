// CUE-003 (AUTO-03, AUTO-04): the router turns received messages into commands through the engine's binding rules,
// learns, remembers a chosen device across unplug and replug, and sends MIDI out without ever blocking.
import Testing
import Foundation
import CueEngine
@testable import MIDIIO

@MainActor
private func waitUntil(timeout: Double = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return true
}

private let next = MIDIBinding(name: "Next", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 60), command: .transport(.next))
private let prev = MIDIBinding(name: "Prev", pattern: MIDIPattern(kind: .controlChange, channel: 1, number: 20, valueRange: 64...127), command: .transport(.previous))

@MainActor
private final class Sink {
    var commands: [MIDICommand] = []
    var messages: [MIDIMessage] = []
}

@MainActor
private func makeRouter(_ f: FakeMIDIPorts, _ sink: Sink, bindings: [MIDIBinding] = [next, prev]) -> MIDIRouter {
    let r = MIDIRouter(ports: f, bindings: MIDIBindingSet(bindings: bindings)) { command, message in
        sink.commands.append(command)
        sink.messages.append(message)
    }
    r.start()
    return r
}

@MainActor
@Suite struct MIDIRouterTests {
    @Test func aBoundMessageRunsItsCommandOnTheMainActor() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(1)
        #expect(r.sourceState == .connected(name: "Pad"))
        f.emit(.noteOn(channel: 1, note: 60, velocity: 90), from: 1)
        f.emit(.noteOn(channel: 1, note: 99, velocity: 90), from: 1)       // unbound: nothing
        #expect(await waitUntil { sink.commands.count == 1 })
        #expect(sink.commands == [.transport(.next)])
        r.stop()
    }

    @Test func aHeldPadFiresOnceUntilReleased() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(1)
        for _ in 0..<5 { f.emit(.noteOn(channel: 1, note: 60, velocity: 90), from: 1) }
        f.emit(.noteOff(channel: 1, note: 60, velocity: 0), from: 1)
        f.emit(.noteOn(channel: 1, note: 60, velocity: 90), from: 1)
        f.emit(.noteOn(channel: 1, note: 70, velocity: 1), from: 1)          // sentinel, unbound
        #expect(await waitUntil { r.receivedCount == 8 })
        #expect(sink.commands == [.transport(.next), .transport(.next)])
        r.stop()
    }

    @Test func orderIsKeptForABurst() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = Sink()
        let all = MIDIBinding(name: "any cc", pattern: MIDIPattern(kind: .controlChange), command: .transport(.next))
        let r = MIDIRouter(ports: f, bindings: MIDIBindingSet(bindings: [all])) { c, m in sink.messages.append(m) }
        r.filter = MIDICommandFilter(noteStaleAfter: 5, ccRepeatWindow: 0)      // no hold-back: every message runs its command
        r.start(); r.selectSource(1)
        for i in 0..<2000 { f.emit(.controlChange(channel: 1, controller: i % 128, value: i % 100), from: 1) }
        #expect(await waitUntil(timeout: 30) { sink.messages.count == 2000 })
        let expected: [MIDIMessage] = (0..<2000).map { .controlChange(channel: 1, controller: $0 % 128, value: $0 % 100) }
        #expect(sink.messages == expected)
        r.stop()
    }

    @Test func learnReturnsTheNextUsableMessageAndSwallowsIt() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(1)
        let task = Task { @MainActor in await r.learn() }
        #expect(await waitUntil { r.isLearning })
        f.emit(.noteOff(channel: 1, note: 60, velocity: 0), from: 1)          // a release cannot be learned
        f.emit(.noteOn(channel: 1, note: 60, velocity: 80), from: 1)          // learned, and must not fire "Next"
        let learned = await task.value
        #expect(learned?.message == .noteOn(channel: 1, note: 60, velocity: 80))
        #expect(learned?.pattern == MIDIPattern(kind: .noteOn, channel: 1, number: 60))
        #expect(r.isLearning == false)
        f.emit(.noteOff(channel: 1, note: 60, velocity: 0), from: 1)
        f.emit(.noteOn(channel: 1, note: 60, velocity: 80), from: 1)
        #expect(await waitUntil { sink.commands.count == 1 })                // normal routing resumed
        r.stop()
    }

    @Test func cancellingLearnReturnsNil() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        let task = Task { @MainActor in await r.learn() }
        #expect(await waitUntil { r.isLearning })
        r.cancelLearning()
        #expect(await task.value == nil)
        #expect(r.isLearning == false)
        r.stop()
    }

    @Test func aChosenDeviceThatDisappearsIsRememberedAndReconnectedByID() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 7, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(7)
        #expect(r.sourceState == .connected(name: "Pad"))

        f.removeSource(id: 7)                                                  // unplugged
        #expect(await waitUntil { r.sourceState == .waiting(lastKnownName: "Pad") })
        #expect(r.selectedSourceID == 7)

        f.addSource(id: 7, name: "Pad")                                        // plugged back in
        #expect(await waitUntil { r.sourceState == .connected(name: "Pad") })
        f.emit(.noteOn(channel: 1, note: 60, velocity: 90), from: 7)
        #expect(await waitUntil { sink.commands.count == 1 })
        r.stop()
    }

    @Test func aDeviceThatGoesOfflineWaitsAndComesBack() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 7, name: "Pad")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(7)
        f.setOnline(false, source: 7)
        #expect(await waitUntil { r.sourceState == .waiting(lastKnownName: "Pad") })
        f.setOnline(true, source: 7)
        #expect(await waitUntil { r.sourceState == .connected(name: "Pad") })
        r.stop()
    }

    @Test func aMissedNotificationIsCoveredByPolling() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 7, name: "Pad")
        f.signalsChanges = false
        let sink = Sink()
        let r = MIDIRouter(ports: f, bindings: MIDIBindingSet(bindings: [next]), pollInterval: 0.02) { c, m in sink.commands.append(c) }
        r.start(); r.selectSource(7)
        f.removeSource(id: 7)
        #expect(await waitUntil { r.sourceState == .waiting(lastKnownName: "Pad") })
        f.addSource(id: 7, name: "Pad")
        #expect(await waitUntil { r.sourceState == .connected(name: "Pad") })
        r.stop()
    }

    @Test func choosingADeviceThatIsNotPresentWaitsForIt() async throws {
        let f = FakeMIDIPorts()
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(42, knownName: "Old Pad")
        #expect(r.sourceState == .waiting(lastKnownName: "Old Pad"))
        f.addSource(id: 42, name: "Old Pad")
        #expect(await waitUntil { r.sourceState == .connected(name: "Old Pad") })
        r.selectSource(nil)
        #expect(r.sourceState == .none)
        #expect(f.connectedSourceIDs.isEmpty)
        r.stop()
    }

    @Test func aFailingConnectIsReportedAndRetriedOnTheNextChange() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        f.failNextConnects = 1
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectSource(1)
        if case .failed = r.sourceState {} else { Issue.record("expected failed, got \(r.sourceState)") }
        f.addSource(id: 2, name: "Other")                                      // any change triggers a retry
        #expect(await waitUntil { r.sourceState == .connected(name: "Pad") })
        r.stop()
    }

    @Test func midiOutGoesToTheChosenDestination() throws {
        let f = FakeMIDIPorts(); f.addDestination(id: 5, name: "Lights")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectDestination(5)
        #expect(r.destinationState == .ready(name: "Lights"))
        try r.perform(.midiOut(.noteOn(channel: 2, note: 40, velocity: 127)))
        #expect(f.sent.map(\.message) == [.noteOn(channel: 2, note: 40, velocity: 127)])
        #expect(r.lastError == nil)
        r.stop()
    }

    @Test func midiOutToAnOfflineDestinationReportsAReadableErrorAndDoesNotBlock() throws {
        let f = FakeMIDIPorts(); f.addDestination(id: 5, name: "Lights")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectDestination(5)
        f.setOnline(false, destination: 5)
        let thrown = #expect(throws: CueTargetError.self) { try r.perform(.midiOut(.noteOn(channel: 2, note: 40, velocity: 127))) }
        #expect(thrown?.message.contains("Lights") == true)
        #expect(thrown?.message.contains("offline") == true)
        #expect(r.lastError == thrown?.message)
        #expect(f.sent.isEmpty)
        r.stop()
    }

    @Test func midiOutWithNoOutputChosenSaysSo() throws {
        let f = FakeMIDIPorts()
        let sink = Sink(); let r = makeRouter(f, sink)
        let thrown = #expect(throws: CueTargetError.self) { try r.perform(.midiOut(.programChange(channel: 1, program: 1))) }
        #expect(thrown?.message.contains("No MIDI output") == true)
        r.stop()
    }

    @Test func midiOutAlsoGoesToTheVirtualSourceWhenItIsOn() throws {
        let f = FakeMIDIPorts()
        try f.setVirtualEndpointsEnabled(true)
        let sink = Sink(); let r = makeRouter(f, sink)
        try r.perform(.midiOut(.programChange(channel: 1, program: 3)))        // no chosen destination, virtual on: fine
        #expect(f.published == [.programChange(channel: 1, program: 3)])
        r.stop()
    }

    @Test func invalidMidiOutIsRefusedBeforeAnythingIsSent() throws {
        let f = FakeMIDIPorts(); f.addDestination(id: 5, name: "Lights")
        let sink = Sink(); let r = makeRouter(f, sink)
        r.selectDestination(5)
        #expect(throws: CueTargetError.self) { try r.perform(.midiOut(.noteOn(channel: 0, note: 1, velocity: 1))) }
        #expect(f.sent.isEmpty)
        r.stop()
    }

    @Test func otherActionsAreNotTheRoutersBusiness() throws {
        let f = FakeMIDIPorts()
        let sink = Sink(); let r = makeRouter(f, sink)
        #expect(r.handles(.midiOut(.noteOn(channel: 1, note: 1, velocity: 1))))
        #expect(r.handles(.transport(.next)) == false)
        r.stop()
    }

    @Test func messagesFromTheVirtualDestinationDriveTheBindingsToo() async throws {
        let f = FakeMIDIPorts()
        try f.setVirtualEndpointsEnabled(true)
        let sink = Sink(); let r = makeRouter(f, sink)
        f.emitToVirtualDestination(.noteOn(channel: 1, note: 60, velocity: 100))
        #expect(await waitUntil { sink.commands == [.transport(.next)] })
        r.stop()
    }
}
