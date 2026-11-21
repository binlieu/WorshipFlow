// CUE-003 (AUTO-03, AUTO-04): the real CoreMIDI implementation of MIDIPorts.
//
// Uses only the non-deprecated, event-list API (macOS 11+; the package targets macOS 15): MIDIClientCreateWithBlock,
// MIDIInputPortCreateWithProtocol, MIDIDestinationCreateWithProtocol, MIDISourceCreateWithProtocol, MIDISendEventList
// and MIDIReceivedEventList, all with kMIDIProtocol_1_0 so the system converts everything to MIDI 1.0 channel voice
// words (UMP message type 2) for us, whatever the device speaks.
//
// Threading: CoreMIDI calls the receive and notify blocks on its own threads. Those blocks only convert words to
// MIDIMessage values and hand them to Broadcaster (a short lock and AsyncStream.yield). They touch no actor state and
// no `state` lock of this class.
import Foundation
import CoreMIDI
import CueEngine
import Synchronization
import Darwin

public final class CoreMIDIPorts: MIDIPorts {
    public let virtualDestinationName: String
    public let virtualSourceName: String

    private struct State {
        var client: MIDIClientRef = 0
        var inputPort: MIDIPortRef = 0
        var outputPort: MIDIPortRef = 0
        var virtualSource: MIDIEndpointRef = 0
        var virtualDestination: MIDIEndpointRef = 0
        var connections: [MIDIEndpointID: MIDIEndpointRef] = [:]
        var closed = false
    }

    /// Counters written from CoreMIDI's thread.
    private final class Counters: Sendable {
        let delivered = Atomic<Int>(0)
        let ignored = Atomic<Int>(0)
        let dropped = Atomic<Int>(0)
    }

    private let state = Mutex(State())
    private let incoming: Broadcaster<ReceivedMIDI>
    private let changes = Broadcaster<Void>(capacity: 1)
    private let counters = Counters()

    /// - Parameter incomingCapacity: how many messages each subscriber may have waiting before the oldest are
    ///   discarded (and counted). The default holds a very large burst.
    public init(clientName: String = "WorshipFlow",
                virtualDestinationName: String = "WorshipFlow In",
                virtualSourceName: String = "WorshipFlow Out",
                incomingCapacity: Int = 65_536) throws {
        self.virtualDestinationName = virtualDestinationName
        self.virtualSourceName = virtualSourceName
        let incoming = Broadcaster<ReceivedMIDI>(capacity: max(1, incomingCapacity))
        self.incoming = incoming
        let changes = self.changes
        let counters = self.counters

        // CoreMIDI delivers setup-change notifications on the run loop of the thread that FIRST called MIDIClientCreate
        // in the process (header: MIDINotifyProc), and a client created on a thread with no running run loop never
        // hears of new devices. So every client is created on one process-wide thread that runs its run loop for the
        // life of the process (observed in this package's tests: once the first client's thread ended, notifications
        // stopped for every later client).
        let created = MIDIRunLoopThread.shared.sync { () -> (MIDIClientRef, OSStatus) in
            var c = MIDIClientRef()
            let st = MIDIClientCreateWithBlock(clientName as CFString, &c) { notification in
                switch notification.pointee.messageID {
                case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                    changes.send(())
                default:
                    break
                }
            }
            return (c, st)
        }
        let (client, clientStatus) = created ?? (0, kMIDIServerStartErr)
        guard clientStatus == noErr else { throw Self.error("CoreMIDI could not start", clientStatus) }
        var status: OSStatus = noErr

        var input = MIDIPortRef()
        status = MIDIInputPortCreateWithProtocol(client, "WorshipFlow Input" as CFString, ._1_0, &input) { list, refCon in
            Self.receive(list, source: Self.sourceID(fromRefCon: refCon), incoming: incoming, counters: counters)
        }
        guard status == noErr else {
            MIDIClientDispose(client)
            throw Self.error("CoreMIDI could not open an input port", status)
        }

        var output = MIDIPortRef()
        status = MIDIOutputPortCreate(client, "WorshipFlow Output" as CFString, &output)
        guard status == noErr else {
            MIDIClientDispose(client)                       // disposing the client disposes its ports
            throw Self.error("CoreMIDI could not open an output port", status)
        }
        state.withLock { $0.client = client; $0.inputPort = input; $0.outputPort = output }
    }

    deinit { close() }

    // MARK: Receiving (CoreMIDI's thread)

    private static func receive(_ list: UnsafePointer<MIDIEventList>, source: MIDIEndpointID?,
                                incoming: Broadcaster<ReceivedMIDI>, counters: Counters) {
        for packet in list.unsafeSequence() {
            let time = MIDIWire.seconds(fromHostTime: packet.pointee.timeStamp)
            let decoded = MIDIWire.decode(words: packet.words())
            if decoded.ignored > 0 { counters.ignored.add(decoded.ignored, ordering: .relaxed) }
            for message in decoded.messages {
                let dropped = incoming.send(ReceivedMIDI(message: message, timestamp: time, source: source))
                counters.delivered.add(1, ordering: .relaxed)
                if dropped > 0 { counters.dropped.add(dropped, ordering: .relaxed) }
            }
        }
    }

    /// The source id travels through CoreMIDI as the connection's refCon, offset by one so id 0 is not a nil pointer.
    private static func refCon(for id: MIDIEndpointID) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: UInt(UInt32(bitPattern: id.rawValue)) + 1)
    }

    private static func sourceID(fromRefCon p: UnsafeMutableRawPointer?) -> MIDIEndpointID? {
        guard let p else { return nil }
        let raw = UInt(bitPattern: p)
        guard raw >= 1 else { return nil }
        return MIDIEndpointID(Int32(bitPattern: UInt32(truncatingIfNeeded: raw - 1)))
    }

    // MARK: Listing

    public func sources() -> [MIDIEndpointInfo] {
        let own = state.withLock { $0.virtualSource }
        return (0..<MIDIGetNumberOfSources()).compactMap { i in
            let e = MIDIGetSource(i)
            return e == own ? nil : Self.info(for: e)
        }
    }

    public func destinations() -> [MIDIEndpointInfo] {
        let own = state.withLock { $0.virtualDestination }
        return (0..<MIDIGetNumberOfDestinations()).compactMap { i in
            let e = MIDIGetDestination(i)
            return e == own ? nil : Self.info(for: e)
        }
    }

    private static func info(for endpoint: MIDIEndpointRef) -> MIDIEndpointInfo? {
        var uid: Int32 = 0
        guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid) == noErr else { return nil }
        var offline: Int32 = 0
        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        let name = string(endpoint, kMIDIPropertyDisplayName) ?? string(endpoint, kMIDIPropertyName) ?? "Unnamed MIDI port"
        return MIDIEndpointInfo(id: MIDIEndpointID(uid), name: name,
                                manufacturer: string(endpoint, kMIDIPropertyManufacturer) ?? "",
                                isOnline: offline == 0)
    }

    private static func string(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private enum EndpointKind { case source, destination }

    /// Finds the endpoint that currently has this unique id; nil when there is none or the id belongs to something
    /// else (a device, an entity, or the other direction).
    private static func endpoint(withID id: MIDIEndpointID, kind: EndpointKind) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(id.rawValue, &object, &type) == noErr, object != 0 else { return nil }
        switch (kind, type) {
        case (.source, .source), (.source, .externalSource), (.destination, .destination), (.destination, .externalDestination):
            return object
        default:
            return nil
        }
    }

    // MARK: Connections

    public var connectedSourceIDs: Set<MIDIEndpointID> {
        state.withLock { s in
            for (id, ref) in s.connections {
                let current = Self.endpoint(withID: id, kind: .source)
                let online = current.flatMap { Self.info(for: $0)?.isOnline } ?? false
                if current != ref || !online {
                    _ = MIDIPortDisconnectSource(s.inputPort, ref)       // the endpoint is gone or was replaced
                    s.connections[id] = nil
                }
            }
            return Set(s.connections.keys)
        }
    }

    public func connect(source id: MIDIEndpointID) throws {
        guard let endpoint = Self.endpoint(withID: id, kind: .source), let info = Self.info(for: endpoint) else {
            throw MIDIPortError("That MIDI input is not connected to this Mac.")
        }
        guard info.isOnline else { throw MIDIPortError("\u{201C}\(info.name)\u{201D} is offline.") }
        try state.withLock { s in
            guard !s.closed else { throw MIDIPortError("MIDI is shut down.") }
            if s.connections[id] == endpoint { return }
            if let old = s.connections[id] { _ = MIDIPortDisconnectSource(s.inputPort, old) }
            let status = MIDIPortConnectSource(s.inputPort, endpoint, Self.refCon(for: id))
            guard status == noErr else { throw Self.error("Could not open \u{201C}\(info.name)\u{201D}", status) }
            s.connections[id] = endpoint
        }
    }

    public func disconnect(source id: MIDIEndpointID) {
        state.withLock { s in
            if let ref = s.connections[id] { _ = MIDIPortDisconnectSource(s.inputPort, ref) }
            s.connections[id] = nil
        }
    }

    public func makeIncomingStream() -> AsyncStream<ReceivedMIDI> { incoming.subscribe() }
    public func makeChangeStream() -> AsyncStream<Void> { changes.subscribe() }

    // MARK: Sending

    /// A one-event MIDI 1.0 event list, built in a small stack buffer, handed to `body`.
    private static func withEventList<R>(word: UInt32, timestamp: MIDITimeStamp,
                                         _ body: (UnsafePointer<MIDIEventList>) -> R?) -> R? {
        var storage = [UInt32](repeating: 0, count: 64)
        return storage.withUnsafeMutableBytes { raw -> R? in
            guard let base = raw.baseAddress else { return nil }
            let list = base.bindMemory(to: MIDIEventList.self, capacity: 1)
            var builder = UnsafeMutableMIDIEventListPointer(list, wordSize: 64, inProtocol: ._1_0)
            guard builder.append(timestamp: timestamp, words: [word]) != nil else { return nil }
            return body(UnsafePointer(list))
        }
    }

    public func send(_ message: MIDIMessage, to id: MIDIEndpointID) throws {
        guard let word = MIDIWire.word(for: message) else {
            throw MIDIPortError("The MIDI message is not valid (channels are 1 to 16, values 0 to 127).")
        }
        guard let endpoint = Self.endpoint(withID: id, kind: .destination), let info = Self.info(for: endpoint) else {
            throw MIDIPortError("That MIDI output is not connected to this Mac.")
        }
        guard info.isOnline else { throw MIDIPortError("\u{201C}\(info.name)\u{201D} is offline.") }
        let port = state.withLock { $0.closed ? MIDIPortRef() : $0.outputPort }
        guard port != 0 else { throw MIDIPortError("MIDI is shut down.") }
        // Timestamp 0 means "now" for MIDISendEventList.
        let status = Self.withEventList(word: word, timestamp: 0) { MIDISendEventList(port, endpoint, $0) }
        guard let status else { throw MIDIPortError("The MIDI message could not be prepared.") }
        guard status == noErr else { throw Self.error("Could not send to \u{201C}\(info.name)\u{201D}", status) }
    }

    // MARK: Virtual endpoints

    public var virtualEndpointsEnabled: Bool { state.withLock { $0.virtualSource != 0 } }

    public func setVirtualEndpointsEnabled(_ enabled: Bool) throws {
        let incoming = self.incoming, counters = self.counters
        try state.withLock { s in
            guard !s.closed else { throw MIDIPortError("MIDI is shut down.") }
            if enabled {
                guard s.virtualSource == 0 else { return }
                var destination = MIDIEndpointRef()
                var status = MIDIDestinationCreateWithProtocol(s.client, virtualDestinationName as CFString, ._1_0, &destination) { list, _ in
                    Self.receive(list, source: nil, incoming: incoming, counters: counters)
                }
                guard status == noErr else { throw Self.error("Could not create the virtual MIDI input \u{201C}\(virtualDestinationName)\u{201D}", status) }
                var source = MIDIEndpointRef()
                status = MIDISourceCreateWithProtocol(s.client, virtualSourceName as CFString, ._1_0, &source)
                guard status == noErr else {
                    MIDIEndpointDispose(destination)
                    throw Self.error("Could not create the virtual MIDI output \u{201C}\(virtualSourceName)\u{201D}", status)
                }
                s.virtualDestination = destination
                s.virtualSource = source
            } else {
                Self.disposeVirtual(&s)
            }
        }
    }

    private static func disposeVirtual(_ s: inout State) {
        if s.virtualSource != 0 { MIDIEndpointDispose(s.virtualSource); s.virtualSource = 0 }
        if s.virtualDestination != 0 { MIDIEndpointDispose(s.virtualDestination); s.virtualDestination = 0 }
    }

    public func publish(_ message: MIDIMessage) throws {
        guard let word = MIDIWire.word(for: message) else {
            throw MIDIPortError("The MIDI message is not valid (channels are 1 to 16, values 0 to 127).")
        }
        let source = state.withLock { $0.virtualSource }
        guard source != 0 else { throw MIDIPortError("The virtual MIDI output is off.") }
        // MIDIReceivedEventList needs a real timestamp: 0 does not mean "now" there.
        let status = Self.withEventList(word: word, timestamp: mach_absolute_time()) { MIDIReceivedEventList(source, $0) }
        guard let status else { throw MIDIPortError("The MIDI message could not be prepared.") }
        guard status == noErr else { throw Self.error("Could not send from the virtual MIDI output", status) }
    }

    // MARK: Statistics and shutdown

    public var statistics: MIDIPortStatistics {
        var s = MIDIPortStatistics()
        s.delivered = counters.delivered.load(ordering: .relaxed)
        s.ignoredEvents = counters.ignored.load(ordering: .relaxed)
        s.droppedMessages = counters.dropped.load(ordering: .relaxed)
        return s
    }

    public func close() {
        let didClose = state.withLock { s -> Bool in
            guard !s.closed else { return false }
            s.closed = true
            for (_, ref) in s.connections { _ = MIDIPortDisconnectSource(s.inputPort, ref) }
            s.connections = [:]
            Self.disposeVirtual(&s)
            if s.inputPort != 0 { MIDIPortDispose(s.inputPort); s.inputPort = 0 }
            if s.outputPort != 0 { MIDIPortDispose(s.outputPort); s.outputPort = 0 }
            if s.client != 0 { MIDIClientDispose(s.client); s.client = 0 }
            return true
        }
        if didClose {
            incoming.finish()
            changes.finish()
        }
    }

    // MARK: Notification run loop

    /// One thread, started on first use and never stopped, whose run loop owns the notification delivery of every
    /// CoreMIDI client this process creates.
    private final class MIDIRunLoopThread: Sendable {
        static let shared = MIDIRunLoopThread()

        private struct LoopBox: @unchecked Sendable { var loop: CFRunLoop? }       // a CFRunLoop may be used from any thread
        private final class Holder: Sendable { let value = Mutex(LoopBox()) }
        private let holder = Holder()

        private init() {
            let ready = DispatchSemaphore(value: 0)
            let holder = self.holder
            let thread = Thread {
                holder.value.withLock { $0.loop = CFRunLoopGetCurrent() }
                RunLoop.current.add(Port(), forMode: .default)                      // keeps the run loop alive
                ready.signal()
                CFRunLoopRun()
            }
            thread.name = "WorshipFlow MIDI run loop"
            thread.qualityOfService = .utility
            thread.start()
            ready.wait()
        }

        /// Runs `body` on the thread and waits for its result. Never call it from the thread itself.
        func sync<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T? {
            guard let loop = holder.value.withLock({ $0.loop }) else { return nil }
            let done = DispatchSemaphore(value: 0)
            let result = Mutex<T?>(nil)
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) {
                let value = body()
                result.withLock { $0 = value }
                done.signal()
            }
            CFRunLoopWakeUp(loop)
            done.wait()
            return result.withLock { $0 }
        }
    }

    // MARK: Errors

    private static func error(_ what: String, _ status: OSStatus) -> MIDIPortError {
        let reason: String
        switch status {
        case kMIDIServerStartErr, kMIDIMessageSendErr: reason = "the system MIDI service is not available"
        case kMIDINotPermitted: reason = "this app is not permitted to use MIDI"
        case kMIDIObjectNotFound, kMIDIUnknownEndpoint: reason = "the device is no longer there"
        case kMIDIIDNotUnique: reason = "the name or id is already taken"
        default: reason = "CoreMIDI error \(status)"
        }
        return MIDIPortError("\(what): \(reason).")
    }
}
