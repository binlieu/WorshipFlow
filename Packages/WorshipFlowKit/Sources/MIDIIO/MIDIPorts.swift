// CUE-003 (AUTO-03, AUTO-04): the device layer's contract. No CoreMIDI types appear here, so the router, the tests and
// a future interface depend on this file only.
import Foundation
import CueEngine

/// The stable identity of a MIDI endpoint. For CoreMIDI this is the endpoint's `kMIDIPropertyUniqueID`, which stays
/// the same when a device is unplugged and plugged in again (the object reference does not).
public struct MIDIEndpointID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByIntegerLiteral {
    public var rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public init(_ rawValue: Int32) { self.rawValue = rawValue }
    public init(integerLiteral value: Int32) { self.rawValue = value }
}

public struct MIDIEndpointInfo: Sendable, Equatable, Hashable, Identifiable {
    public var id: MIDIEndpointID
    public var name: String
    public var manufacturer: String
    /// False while the device is known to the system but not present (kMIDIPropertyOffline).
    public var isOnline: Bool

    public init(id: MIDIEndpointID, name: String, manufacturer: String = "", isOnline: Bool = true) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isOnline = isOnline
    }
}

/// A message that arrived, with the time it was received on a monotonic clock (seconds, arbitrary origin; only
/// differences mean anything) and where it came from (nil for the app's own virtual destination).
public struct ReceivedMIDI: Sendable, Equatable {
    public var message: MIDIMessage
    public var timestamp: TimeInterval
    public var source: MIDIEndpointID?

    public init(message: MIDIMessage, timestamp: TimeInterval, source: MIDIEndpointID? = nil) {
        self.message = message
        self.timestamp = timestamp
        self.source = source
    }
}

public struct MIDIPortStatistics: Sendable, Equatable {
    /// Messages handed to subscribers.
    public var delivered = 0
    /// Events that are not channel voice messages the engine understands (system exclusive, clock, active sensing,
    /// aftertouch, pitch bend, MIDI 2.0 events) and malformed words. Counted, never an error.
    public var ignoredEvents = 0
    /// Messages a slow subscriber could not take because its buffer was full (the oldest are discarded).
    public var droppedMessages = 0
    public init() {}
}

/// An error whose text can be shown to the operator as is.
public struct MIDIPortError: Error, Sendable, Equatable, LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Everything the app needs from MIDI hardware and the system's MIDI services. Methods are safe to call from any
/// thread. Nothing here blocks on a device.
public protocol MIDIPorts: AnyObject, Sendable {
    /// Sources and destinations the system knows, including offline ones (flagged). The app's own virtual endpoints
    /// are not listed.
    func sources() -> [MIDIEndpointInfo]
    func destinations() -> [MIDIEndpointInfo]

    /// Sources currently feeding `makeIncomingStream`. A source that has vanished from the system is no longer
    /// reported as connected.
    var connectedSourceIDs: Set<MIDIEndpointID> { get }
    /// Starts receiving from a source. Connecting a source that is already connected succeeds. Throws for an unknown
    /// or offline source.
    func connect(source: MIDIEndpointID) throws
    func disconnect(source: MIDIEndpointID)

    /// A new stream of received messages, in arrival order, from the connected sources and from the virtual
    /// destination. Each call returns an independent stream that sees messages from then on; it is bounded and drops
    /// the oldest messages if its consumer stalls (counted in `statistics`). Cancel the consumer to unsubscribe.
    func makeIncomingStream() -> AsyncStream<ReceivedMIDI>
    /// A stream that yields whenever sources or destinations appeared, disappeared or changed. Coalesced; re-list
    /// after each element.
    func makeChangeStream() -> AsyncStream<Void>

    /// Sends one message to a destination. Throws for an invalid message or an unknown or offline destination.
    func send(_ message: MIDIMessage, to destination: MIDIEndpointID) throws

    /// The virtual destination ("WorshipFlow In") other apps can send to, and the virtual source ("WorshipFlow Out")
    /// other apps can listen to. Off by default.
    var virtualEndpointsEnabled: Bool { get }
    func setVirtualEndpointsEnabled(_ enabled: Bool) throws
    /// Sends a message out of the virtual source. Throws when the virtual endpoints are off.
    func publish(_ message: MIDIMessage) throws

    var statistics: MIDIPortStatistics { get }

    /// Releases every client, port and endpoint. Safe to call more than once; the object is unusable afterwards.
    func close()
}
