// HW-001 / SCRN-10, SCRN-11, HW-11: which physical connector carries which screen.
// The planner never guesses: a request that cannot be met exactly is a fault with a plain explanation,
// and nothing is ever moved to a different connector on its own.
import Foundation

/// One screen asking for a connector. Connectors are numbered from 1.
public struct SDIOutputRequest: Equatable, Sendable {
    public var screenID: UUID
    public var connector: Int
    /// Fill and key: the screen takes this connector for fill and the next one for the key.
    public var keying: Bool

    public init(screenID: UUID, connector: Int, keying: Bool = false) {
        self.screenID = screenID
        self.connector = connector
        self.keying = keying
    }
}

public struct SDIAssignment: Equatable, Sendable {
    public var connector: Int
    public var keyConnector: Int?
    public init(connector: Int, keyConnector: Int?) {
        self.connector = connector
        self.keyConnector = keyConnector
    }
}

public enum SDIConnectorRole: Equatable, Sendable {
    case unused
    case output(UUID)
    case fill(UUID)
    case key(UUID)
}

public enum SDIPlanFault: Equatable, Sendable {
    case connectorOutOfRange
    case connectorInUse(by: UUID)
    case keyingUnsupported
    case keyingNeedsFirstConnectorOfAPair
    case pairedConnectorInUse(by: UUID)
    case noPairedConnector
    case screenAlreadyAssigned

    /// Plain language for the operator; never mentions types or codes.
    public var operatorMessage: String {
        switch self {
        case .connectorOutOfRange:
            return "That SDI connector does not exist on this card. Choose one of the connectors the card has."
        case .connectorInUse:
            return "That SDI connector is already used by another screen. Choose a free connector."
        case .keyingUnsupported:
            return "This card cannot send a fill and key pair. Turn off keying for this screen."
        case .keyingNeedsFirstConnectorOfAPair:
            return "Fill and key must start on connector 1 or 3, so the key can use the next connector."
        case .pairedConnectorInUse:
            return "The connector needed for the key is already used by another screen. Free it or turn off keying."
        case .noPairedConnector:
            return "This card has no second connector to carry the key for that fill."
        case .screenAlreadyAssigned:
            return "This screen already has an SDI connector. A screen can only use one output."
        }
    }
}

public struct SDIConnectorPlan: Equatable, Sendable {
    public var assignments: [UUID: SDIAssignment]
    public var faults: [UUID: SDIPlanFault]
    private var roles: [Int: SDIConnectorRole]

    init(assignments: [UUID: SDIAssignment], faults: [UUID: SDIPlanFault], roles: [Int: SDIConnectorRole]) {
        self.assignments = assignments
        self.faults = faults
        self.roles = roles
    }

    /// Number of physical connectors in use, a key connector counting as one (HW-11).
    public var connectorsUsed: Int { roles.count }

    public func role(of connector: Int) -> SDIConnectorRole { roles[connector] ?? .unused }
}

public enum SDIConnectorPlanner {
    /// Earlier requests win. Pairs are (1, 2) and (3, 4); fill goes on the first of a pair, key on the second.
    public static func plan(requests: [SDIOutputRequest], connectorCount: Int, supportsExternalKeying: Bool) -> SDIConnectorPlan {
        var assignments: [UUID: SDIAssignment] = [:]
        var faults: [UUID: SDIPlanFault] = [:]
        var roles: [Int: SDIConnectorRole] = [:]
        // Which screen owns each connector, whether as output, fill or key.
        var owner: [Int: UUID] = [:]

        for request in requests {
            let id = request.screenID
            let c = request.connector
            if assignments[id] != nil {
                faults[id] = .screenAlreadyAssigned
                continue
            }
            guard c >= 1, c <= connectorCount else { faults[id] = .connectorOutOfRange; continue }
            if request.keying {
                guard supportsExternalKeying else { faults[id] = .keyingUnsupported; continue }
                guard c % 2 == 1 else { faults[id] = .keyingNeedsFirstConnectorOfAPair; continue }
                let partner = c + 1
                guard partner <= connectorCount else { faults[id] = .noPairedConnector; continue }
                if let other = owner[c] { faults[id] = .connectorInUse(by: other); continue }
                if let other = owner[partner] { faults[id] = .pairedConnectorInUse(by: other); continue }
                owner[c] = id
                owner[partner] = id
                roles[c] = .fill(id)
                roles[partner] = .key(id)
                assignments[id] = SDIAssignment(connector: c, keyConnector: partner)
            } else {
                if let other = owner[c] { faults[id] = .connectorInUse(by: other); continue }
                owner[c] = id
                roles[c] = .output(id)
                assignments[id] = SDIAssignment(connector: c, keyConnector: nil)
            }
        }
        return SDIConnectorPlan(assignments: assignments, faults: faults, roles: roles)
    }
}
