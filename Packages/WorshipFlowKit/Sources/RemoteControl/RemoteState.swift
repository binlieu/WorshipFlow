// CUE-004 (AUTO-10, AUTO-13): what a remote client may see and what the app must provide. Foundation, CueEngine, Domain only.
import Foundation
import CueEngine

public enum RemoteMode: String, Sendable, Equatable, Codable {
    case live, stopped, cleared, blackedOut
}

public struct RemoteSlideText: Sendable, Equatable, Codable {
    public var primary: String
    public var secondary: String?
    public init(primary: String, secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct RemotePlaylistItem: Sendable, Equatable, Codable {
    public var title: String
    public var isLive: Bool
    public init(title: String, isLive: Bool) {
        self.title = title
        self.isLive = isLive
    }
}

public struct RemoteTimer: Sendable, Equatable, Codable {
    public var name: String
    /// Display text such as "04:32".
    public var value: String
    public var isRunning: Bool
    public init(name: String, value: String, isRunning: Bool) {
        self.name = name
        self.value = value
        self.isRunning = isRunning
    }
}

public struct RemoteMacro: Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A snapshot of the show for a phone. Plain values only.
public struct RemoteState: Sendable, Equatable, Codable {
    public var mode: RemoteMode
    public var live: RemoteSlideText?
    public var next: RemoteSlideText?
    /// For example "3 of 9". Nil when nothing is live.
    public var position: String?
    public var presentationTitle: String?
    public var playlist: [RemotePlaylistItem]
    public var timers: [RemoteTimer]
    public var macros: [RemoteMacro]

    public init(mode: RemoteMode = .stopped, live: RemoteSlideText? = nil, next: RemoteSlideText? = nil,
                position: String? = nil, presentationTitle: String? = nil, playlist: [RemotePlaylistItem] = [],
                timers: [RemoteTimer] = [], macros: [RemoteMacro] = []) {
        self.mode = mode
        self.live = live
        self.next = next
        self.position = position
        self.presentationTitle = presentationTitle
        self.playlist = playlist
        self.timers = timers
        self.macros = macros
    }

    public static func positionText(index: Int, count: Int) -> String { "\(index + 1) of \(count)" }
}

public enum RemoteTargetError: Error, Sendable, Equatable {
    case unknownMacro
    case unavailable
    /// A short operator-readable reason, shown to the client as is. Never put secrets in it.
    case rejected(String)
}

/// What the app implements. Every call may hop to the main actor on the app side. The server calls these one at a time,
/// in the order requests arrived.
public protocol RemoteControlTarget: Sendable {
    func perform(_ command: CueTransport) async throws
    func runMacro(id: UUID) async throws
    func snapshot() async -> RemoteState
}

/// Things worth showing the operator. Never carries a token or a pairing code.
public enum RemoteServerEvent: Sendable, Equatable {
    case started(port: UInt16)
    case stopped
    case paired(tokenID: UUID, label: String)
    case pairingRejected(address: String)
    case pairingLockedOut(address: String, retryAfter: TimeInterval)
    case tokenRevoked(UUID)
    case allTokensRevoked
    case refusedPeer(address: String)
    case refusedConnectionLimit
}

public enum RemoteServerError: Error, Sendable, Equatable {
    case alreadyRunning
    case couldNotListen(String)
}

public struct RemoteServerConfiguration: Sendable {
    /// 0 asks the system for a free port.
    public var port: UInt16 = 8765
    /// Bind to the loopback interface only. Tests do; the app does not.
    public var loopbackOnly = false
    public var maxConnections = 16
    /// Longest a client may take to deliver one complete request.
    public var requestTimeout: TimeInterval = 10
    /// Longest the server waits for the target to answer one request.
    public var handlerTimeout: TimeInterval = 15
    public var heartbeatInterval: TimeInterval = 15
    public var maxBodyBytes = 64 * 1024
    public var maxHeaderBytes = 8 * 1024
    public var pairingCodeLifetime: TimeInterval = 120
    public var pairingMaxFailures = 5
    public var pairingFailureWindow: TimeInterval = 60
    public var pairingLockout: TimeInterval = 60
    /// Wrong guesses allowed against one code, from all addresses together, before the code is replaced.
    public var pairingMaxFailuresPerCode = 10
    public var maxPairedDevices = 32
    /// Host names (besides localhost and this Mac's own names) that may appear in the Host header.
    public var additionalAllowedHosts: Set<String> = []

    public init() {}
}
