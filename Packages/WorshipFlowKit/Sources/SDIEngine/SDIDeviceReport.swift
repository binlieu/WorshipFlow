// HW-004: what a device says about itself beyond "how many connectors": which connector carries the fill and which the
// key (KI-053), what each connector can do, and which profile the card is in and what keying would need (KI-054).
// Plain data. The planner and the interface read it; nothing in here knows about any vendor SDK.
import Foundation

/// Where one pair of connectors puts the fill and the key. `firstConnector` is the connector a keyed port is opened on
/// (1 or 3 on a four-connector card); the fill and key connectors are the two connectors of that pair, in either order.
public struct SDIKeyRoute: Equatable, Sendable {
    /// Where the answer came from. None of them is a measurement on a real card.
    public enum Source: String, Equatable, Sendable {
        /// Read from the vendor manual's connector table by the bridge: the SDK has no attribute that says it.
        case manualTable
        /// The simulated card's own implementation.
        case simulator
        /// The app's old convention (fill on the first connector), used where nothing better is known.
        case assumed
    }

    public var firstConnector: Int
    public var fillConnector: Int
    public var keyConnector: Int
    public var source: Source

    public init(firstConnector: Int, fillConnector: Int, keyConnector: Int, source: Source) {
        self.firstConnector = firstConnector
        self.fillConnector = fillConnector
        self.keyConnector = keyConnector
        self.source = source
    }

    /// Fill on the first connector, key on the next: what the planner assumed before devices reported a route.
    public static func convention(firstConnector: Int, source: Source = .assumed) -> SDIKeyRoute {
        SDIKeyRoute(firstConnector: firstConnector, fillConnector: firstConnector, keyConnector: firstConnector + 1, source: source)
    }

    /// True when the key is on the first connector and the fill on the second.
    public var isReversedFromConvention: Bool { fillConnector != firstConnector }

    /// "Uses connectors 1 and 2: fill on 2, key on 1": the wording the interface shows.
    public var caption: String {
        let low = min(fillConnector, keyConnector), high = max(fillConnector, keyConnector)
        return "Uses connectors \(low) and \(high): fill on \(fillConnector), key on \(keyConnector)"
    }
}

/// What one physical connector can do right now, in the card's current profile.
public struct SDIConnectorInfo: Equatable, Sendable {
    public var connector: Int
    public var canOutput: Bool
    public var canInput: Bool
    /// When the pair is keyed: whether this connector carries the fill or the key. Nil where it cannot key.
    public var keyRole: SDIKeyRole?

    public init(connector: Int, canOutput: Bool, canInput: Bool, keyRole: SDIKeyRole? = nil) {
        self.connector = connector
        self.canOutput = canOutput
        self.canInput = canInput
        self.keyRole = keyRole
    }
}

public enum SDIKeyRole: String, Equatable, Sendable { case fill, key }

/// A profile change that would let a pair key. The card applies it to the whole pair, and it can interrupt other connectors
/// for a moment, so the operator is asked first (KI-054).
public struct SDIProfileChange: Equatable, Sendable {
    public var firstConnector: Int
    public var fromName: String?
    public var toName: String
    /// Connectors that may drop out while the card changes profile.
    public var interruptedConnectors: [Int]

    public init(firstConnector: Int, fromName: String?, toName: String, interruptedConnectors: [Int]) {
        self.firstConnector = firstConnector
        self.fromName = fromName
        self.toName = toName
        self.interruptedConnectors = interruptedConnectors
    }

    /// The question for the operator, in plain words.
    public var question: String {
        let from = fromName.map { "from \"\($0)\" " } ?? ""
        let list = interruptedConnectors.map(String.init).joined(separator: ", ")
        return "To send a fill and key pair on connectors \(firstConnector) and \(firstConnector + 1), the card must change its profile \(from)to \"\(toName)\". "
            + "This can interrupt any output on the card for a few seconds" + (list.isEmpty ? "." : " (connectors \(list)).") + " Change the profile now?"
    }
}

/// One connector pair's profile state, as the device reports it.
public struct SDIProfileState: Equatable, Sendable {
    public var firstConnector: Int
    public var activeName: String?
    /// Whether the pair can send fill and key in the profile it is in now.
    public var keyingAvailableNow: Bool
    /// What switching would do, when keying is not available now but a profile on the card offers it.
    public var keyingChange: SDIProfileChange?

    public init(firstConnector: Int, activeName: String?, keyingAvailableNow: Bool, keyingChange: SDIProfileChange?) {
        self.firstConnector = firstConnector
        self.activeName = activeName
        self.keyingAvailableNow = keyingAvailableNow
        self.keyingChange = keyingChange
    }
}
