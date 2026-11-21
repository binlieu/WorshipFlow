// CUE-003 (AUTO-03, AUTO-04): the real CoreMIDI path, with no hardware. One CoreMIDIPorts ("app") owns uniquely named
// virtual endpoints; a second CoreMIDIPorts ("peer", its own CoreMIDI client) plays the other application. Every
// client and endpoint created here is closed at the end of its test, and a final test checks that nothing is left.
import Testing
import Foundation
import CueEngine
@testable import MIDIIO

/// Unique per test so a running WorshipFlow, or an earlier crashed run, can never collide with these endpoints.
private struct Loopback {
    let app: CoreMIDIPorts
    let peer: CoreMIDIPorts
    let inName: String
    let outName: String

    init(incomingCapacity: Int = 65_536) throws {
        let tag = UUID().uuidString.prefix(8)
        inName = "wf-cue003-\(tag)-In"
        outName = "wf-cue003-\(tag)-Out"
        app = try CoreMIDIPorts(clientName: "wf-cue003-app-\(tag)", virtualDestinationName: inName,
                                virtualSourceName: outName, incomingCapacity: incomingCapacity)
        do {
            peer = try CoreMIDIPorts(clientName: "wf-cue003-peer-\(tag)")
        } catch {
            app.close()
            throw error
        }
    }

    func close() { app.close(); peer.close() }

    func peerDestination() async -> MIDIEndpointInfo? { await find { peer.destinations().first { $0.name == inName } } }
    func peerSource() async -> MIDIEndpointInfo? { await find { peer.sources().first { $0.name == outName } } }

    private func find(_ look: () -> MIDIEndpointInfo?) async -> MIDIEndpointInfo? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let e = look() { return e }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}

/// CoreMIDI may be unusable in a sandboxed or headless test environment. Then the test is skipped with a recorded
/// reason rather than failed.
private func makeLoopback(incomingCapacity: Int = 65_536) throws -> Loopback {
    do {
        return try Loopback(incomingCapacity: incomingCapacity)
    } catch {
        try Test.cancel("CoreMIDI is not usable in this environment: \(error.localizedDescription)")
    }
}

private func collect(_ stream: AsyncStream<ReceivedMIDI>, count: Int, timeout: Double = 10) async -> [ReceivedMIDI] {
    await withTaskGroup(of: [ReceivedMIDI].self) { group in
        group.addTask {
            var got: [ReceivedMIDI] = []
            for await r in stream {
                got.append(r)
                if got.count == count { break }
            }
            return got
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}

private func everyKindOnEveryChannel() -> [MIDIMessage] {
    var all: [MIDIMessage] = []
    for ch in 1...16 {
        all.append(.noteOn(channel: ch, note: 36 + ch, velocity: 100))
        all.append(.noteOff(channel: ch, note: 36 + ch, velocity: 64))
        all.append(.controlChange(channel: ch, controller: ch, value: 127 - ch))
        all.append(.programChange(channel: ch, program: 100 + ch))
    }
    return all
}

@Suite(.serialized) struct CoreMIDILoopbackTests {
    @Test func virtualEndpointsAreOffByDefaultAndSwitchOnAndOff() async throws {
        let l = try makeLoopback(); defer { l.close() }
        #expect(l.app.virtualEndpointsEnabled == false)
        #expect(l.peer.destinations().contains { $0.name == l.inName } == false)
        try l.app.setVirtualEndpointsEnabled(true)
        #expect(l.app.virtualEndpointsEnabled)
        #expect(await l.peerDestination() != nil)
        #expect(await l.peerSource() != nil)
        #expect(l.app.sources().contains { $0.name == l.outName } == false)          // the app does not list its own
        #expect(l.app.destinations().contains { $0.name == l.inName } == false)
        try l.app.setVirtualEndpointsEnabled(false)
        #expect(l.app.virtualEndpointsEnabled == false)
        let deadline = Date().addingTimeInterval(5)
        while l.peer.destinations().contains(where: { $0.name == l.inName }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(l.peer.destinations().contains { $0.name == l.inName } == false)
    }

    @Test func everyMessageKindOnEveryChannelReachesTheVirtualDestination() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        let sent = everyKindOnEveryChannel()
        let stream = l.app.makeIncomingStream()
        for m in sent { try l.peer.send(m, to: dest.id) }
        let got = await collect(stream, count: sent.count)
        #expect(got.map(\.message) == sent)
        #expect(got.allSatisfy { $0.source == nil })
        #expect(zip(got, got.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp })
    }

    @Test func everyMessageKindOnEveryChannelLeavesTheVirtualSource() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let src = try #require(await l.peerSource())
        try l.peer.connect(source: src.id)
        #expect(l.peer.connectedSourceIDs == [src.id])
        let sent = everyKindOnEveryChannel()
        let stream = l.peer.makeIncomingStream()
        for m in sent { try l.app.publish(m) }
        let got = await collect(stream, count: sent.count)
        #expect(got.map(\.message) == sent)
        #expect(got.allSatisfy { $0.source == src.id })
        l.peer.disconnect(source: src.id)
        #expect(l.peer.connectedSourceIDs.isEmpty)
    }

    @Test func noteOnWithVelocityZeroArrivesAsNoteOff() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        let stream = l.app.makeIncomingStream()
        try l.peer.send(.noteOn(channel: 1, note: 60, velocity: 0), to: dest.id)
        let got = await collect(stream, count: 1)
        #expect(got.map(\.message) == [.noteOff(channel: 1, note: 60, velocity: 0)])
    }

    @Test func invalidMessagesAreRefusedAndNeverSent() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        #expect(throws: MIDIPortError.self) { try l.peer.send(.noteOn(channel: 17, note: 60, velocity: 1), to: dest.id) }
        #expect(throws: MIDIPortError.self) { try l.peer.send(.noteOn(channel: 1, note: 128, velocity: 1), to: dest.id) }
        #expect(throws: MIDIPortError.self) { try l.app.publish(.controlChange(channel: 1, controller: -1, value: 0)) }
        let stream = l.app.makeIncomingStream()
        try l.peer.send(.noteOn(channel: 1, note: 1, velocity: 1), to: dest.id)       // a good one proves nothing leaked before it
        let got = await collect(stream, count: 1)
        #expect(got.map(\.message) == [.noteOn(channel: 1, note: 1, velocity: 1)])
    }

    @Test func aBurstOfTenThousandMessagesKeepsOrderWithoutLoss() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        let sent: [MIDIMessage] = (0..<10_000).map {
            .controlChange(channel: 1 + $0 % 16, controller: ($0 / 16) % 128, value: $0 % 128)
        }
        let stream = l.app.makeIncomingStream()
        let reader = Task { await collect(stream, count: sent.count, timeout: 30) }
        for m in sent { try l.peer.send(m, to: dest.id) }
        let got = await reader.value
        #expect(got.count == sent.count)
        #expect(got.map(\.message) == sent)
        #expect(l.app.statistics.droppedMessages == 0)
    }

    @Test func aStalledSubscriberIsBoundedAndTheDropsAreCounted() async throws {
        let l = try makeLoopback(incomingCapacity: 50); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        let stalled = l.app.makeIncomingStream()                                    // nobody reads it yet
        for i in 0..<500 { try l.peer.send(.noteOn(channel: 1, note: i % 128, velocity: 1 + i % 127), to: dest.id) }
        let deadline = Date().addingTimeInterval(10)
        while l.app.statistics.delivered < 500 && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(l.app.statistics.delivered == 500)
        #expect(l.app.statistics.droppedMessages == 450)
        let kept = await collect(stalled, count: 50, timeout: 5)
        #expect(kept.count == 50)
        let newest = (450..<500).map { MIDIMessage.noteOn(channel: 1, note: $0 % 128, velocity: 1 + $0 % 127) }
        #expect(kept.map(\.message) == newest)                                      // the newest are kept
    }

    @Test func aDeviceListChangeIsSignalled() async throws {
        // CoreMIDI sends notifications on the run loop of the process's first client; a client that came and went
        // before must not silence the ones created later.
        let early = try makeLoopback(); early.close()
        let l = try makeLoopback(); defer { l.close() }
        let changes = l.peer.makeChangeStream()
        try l.app.setVirtualEndpointsEnabled(true)
        let signalled = await withTaskGroup(of: Bool.self) { group in
            group.addTask { var it = changes.makeAsyncIterator(); return await it.next() != nil }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000); return false }
            let r = await group.next() ?? false
            group.cancelAll()
            return r
        }
        #expect(signalled)
    }

    @Test func routerDrivesCommandsAndSendsOverRealCoreMIDI() async throws {
        let l = try makeLoopback(); defer { l.close() }
        try l.app.setVirtualEndpointsEnabled(true)
        let dest = try #require(await l.peerDestination())
        let bindings = MIDIBindingSet(bindings: [
            MIDIBinding(name: "Next", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 60), command: .transport(.next)),
        ])
        let box = CommandBox()
        let router = await MainActor.run {
            let r = MIDIRouter(ports: l.app, bindings: bindings) { c, _ in box.commands.append(c) }
            r.start()
            return r
        }
        try l.peer.send(.noteOn(channel: 1, note: 60, velocity: 100), to: dest.id)
        let deadline = Date().addingTimeInterval(5)
        while await MainActor.run(body: { box.commands.isEmpty }) && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let commands = await MainActor.run { box.commands }
        #expect(commands == [.transport(.next)])

        // Out: the router publishes on the virtual source; the peer hears it.
        let src = try #require(await l.peerSource())
        try l.peer.connect(source: src.id)
        let heard = l.peer.makeIncomingStream()
        try await MainActor.run { try router.perform(.midiOut(.programChange(channel: 2, program: 7))) }
        let got = await collect(heard, count: 1)
        #expect(got.map(\.message) == [.programChange(channel: 2, program: 7)])
        await MainActor.run { router.stop() }
    }

    @Test func closingDisposesEveryEndpointAndClient() async throws {
        let tag = UUID().uuidString.prefix(8)
        let inName = "wf-cue003-\(tag)-In", outName = "wf-cue003-\(tag)-Out"
        let observer: CoreMIDIPorts
        do { observer = try CoreMIDIPorts(clientName: "wf-cue003-observer-\(tag)") }
        catch { try Test.cancel("CoreMIDI is not usable in this environment: \(error.localizedDescription)") }
        defer { observer.close() }
        let app = try CoreMIDIPorts(clientName: "wf-cue003-closing-\(tag)", virtualDestinationName: inName, virtualSourceName: outName)
        try app.setVirtualEndpointsEnabled(true)
        let deadline = Date().addingTimeInterval(5)
        while !observer.destinations().contains(where: { $0.name == inName }) && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(observer.destinations().contains { $0.name == inName })
        app.close()
        app.close()                                                                  // idempotent
        let gone = Date().addingTimeInterval(5)
        while (observer.destinations().contains { $0.name == inName } || observer.sources().contains { $0.name == outName }) && Date() < gone {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(observer.destinations().contains { $0.name == inName } == false)
        #expect(observer.sources().contains { $0.name == outName } == false)
        #expect(throws: MIDIPortError.self) { try app.setVirtualEndpointsEnabled(true) }
    }
}

@MainActor private final class CommandBox { var commands: [MIDICommand] = [] }
