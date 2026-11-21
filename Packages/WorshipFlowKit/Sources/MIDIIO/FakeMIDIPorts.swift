// CUE-003: an in-memory MIDIPorts for tests and previews. Behaves like the contract says: only connected sources
// deliver, offline endpoints refuse, removing an endpoint drops its connection and signals a change.
import Foundation
import CueEngine
import Synchronization

public final class FakeMIDIPorts: MIDIPorts {
    public struct SentMessage: Sendable, Equatable {
        public var message: MIDIMessage
        public var destination: MIDIEndpointID
    }

    private struct State {
        var sources: [MIDIEndpointInfo] = []
        var destinations: [MIDIEndpointInfo] = []
        var connected: Set<MIDIEndpointID> = []
        var virtualEnabled = false
        var sent: [SentMessage] = []
        var published: [MIDIMessage] = []
        var stats = MIDIPortStatistics()
        var failNextConnects = 0
        var closed = false
        var signalsChanges = true
    }

    private let state = Mutex(State())
    private let incoming = Broadcaster<ReceivedMIDI>(capacity: 65_536)
    private let changes = Broadcaster<Void>(capacity: 1)
    private let clock = Mutex(0.0)

    public init() {}

    // MARK: Test controls

    public func addSource(id: MIDIEndpointID, name: String, manufacturer: String = "", isOnline: Bool = true) {
        state.withLock { s in
            s.sources.removeAll { $0.id == id }
            s.sources.append(MIDIEndpointInfo(id: id, name: name, manufacturer: manufacturer, isOnline: isOnline))
        }
        signalChange()
    }

    public func addDestination(id: MIDIEndpointID, name: String, manufacturer: String = "", isOnline: Bool = true) {
        state.withLock { s in
            s.destinations.removeAll { $0.id == id }
            s.destinations.append(MIDIEndpointInfo(id: id, name: name, manufacturer: manufacturer, isOnline: isOnline))
        }
        signalChange()
    }

    public func removeSource(id: MIDIEndpointID) {
        state.withLock { s in
            s.sources.removeAll { $0.id == id }
            s.connected.remove(id)
        }
        signalChange()
    }

    public func removeDestination(id: MIDIEndpointID) {
        state.withLock { $0.destinations.removeAll { $0.id == id } }
        signalChange()
    }

    public func setOnline(_ online: Bool, source id: MIDIEndpointID) {
        state.withLock { s in
            if let i = s.sources.firstIndex(where: { $0.id == id }) { s.sources[i].isOnline = online }
            if !online { s.connected.remove(id) }
        }
        signalChange()
    }

    public func setOnline(_ online: Bool, destination id: MIDIEndpointID) {
        state.withLock { s in
            if let i = s.destinations.firstIndex(where: { $0.id == id }) { s.destinations[i].isOnline = online }
        }
        signalChange()
    }

    /// False simulates the system missing device notifications: lists still change, but no change is signalled.
    public var signalsChanges: Bool {
        get { state.withLock { $0.signalsChanges } }
        set { state.withLock { $0.signalsChanges = newValue } }
    }

    private func signalChange() {
        if state.withLock({ $0.signalsChanges }) { changes.send(()) }
    }

    /// The next this many `connect` calls fail with an error.
    public var failNextConnects: Int {
        get { state.withLock { $0.failNextConnects } }
        set { state.withLock { $0.failNextConnects = newValue } }
    }

    /// Delivers a message as if the source had sent it. Dropped when the source is not connected.
    public func emit(_ message: MIDIMessage, from source: MIDIEndpointID) {
        let connected = state.withLock { $0.connected.contains(source) }
        guard connected else { return }
        deliver(message, source: source)
    }

    /// Delivers raw MIDI 1.0 bytes from a connected source, decoded with the engine's parser.
    public func emit(bytes: [UInt8], from source: MIDIEndpointID) {
        let connected = state.withLock { $0.connected.contains(source) }
        guard connected else { return }
        for m in MIDIWire.messages(fromBytes: bytes) { deliver(m, source: source) }
    }

    /// Delivers a message as if another app had sent it to the virtual destination. Dropped while it is off.
    public func emitToVirtualDestination(_ message: MIDIMessage) {
        guard state.withLock({ $0.virtualEnabled }) else { return }
        deliver(message, source: nil)
    }

    public var sent: [SentMessage] { state.withLock { $0.sent } }
    public var published: [MIDIMessage] { state.withLock { $0.published } }

    private func deliver(_ message: MIDIMessage, source: MIDIEndpointID?) {
        let t = clock.withLock { c -> Double in c += 0.001; return c }
        let dropped = incoming.send(ReceivedMIDI(message: message, timestamp: t, source: source))
        state.withLock { $0.stats.delivered += 1; $0.stats.droppedMessages += dropped }
    }

    // MARK: MIDIPorts

    public func sources() -> [MIDIEndpointInfo] { state.withLock { $0.sources } }
    public func destinations() -> [MIDIEndpointInfo] { state.withLock { $0.destinations } }
    public var connectedSourceIDs: Set<MIDIEndpointID> { state.withLock { $0.connected } }

    public func connect(source: MIDIEndpointID) throws {
        try state.withLock { s in
            if s.failNextConnects > 0 {
                s.failNextConnects -= 1
                throw MIDIPortError("The MIDI input could not be opened (simulated failure).")
            }
            guard let info = s.sources.first(where: { $0.id == source }) else {
                throw MIDIPortError("That MIDI input is not available.")
            }
            guard info.isOnline else { throw MIDIPortError("\u{201C}\(info.name)\u{201D} is offline.") }
            s.connected.insert(source)
        }
    }

    public func disconnect(source: MIDIEndpointID) { state.withLock { _ = $0.connected.remove(source) } }

    public func makeIncomingStream() -> AsyncStream<ReceivedMIDI> { incoming.subscribe() }
    public func makeChangeStream() -> AsyncStream<Void> { changes.subscribe() }

    public func send(_ message: MIDIMessage, to destination: MIDIEndpointID) throws {
        guard message.isValid else { throw MIDIPortError("The MIDI message is not valid.") }
        try state.withLock { s in
            guard let info = s.destinations.first(where: { $0.id == destination }) else {
                throw MIDIPortError("That MIDI output is not available.")
            }
            guard info.isOnline else { throw MIDIPortError("\u{201C}\(info.name)\u{201D} is offline.") }
            s.sent.append(SentMessage(message: message, destination: destination))
        }
    }

    public var virtualEndpointsEnabled: Bool { state.withLock { $0.virtualEnabled } }
    public func setVirtualEndpointsEnabled(_ enabled: Bool) throws { state.withLock { $0.virtualEnabled = enabled } }

    public func publish(_ message: MIDIMessage) throws {
        guard message.isValid else { throw MIDIPortError("The MIDI message is not valid.") }
        try state.withLock { s in
            guard s.virtualEnabled else { throw MIDIPortError("The virtual MIDI output is off.") }
            s.published.append(message)
        }
    }

    public var statistics: MIDIPortStatistics { state.withLock { $0.stats } }

    public func close() {
        state.withLock { $0.closed = true; $0.connected = [] }
        incoming.finish()
        changes.finish()
    }
}
