// OUT-002: screen profiles and routing. A screen faults on its own; it is never moved to another display.
import Foundation

public enum OutputDestination: Sendable, Equatable, Codable, Hashable {
    /// A full-screen output on the display with this CGDirectDisplayID.
    case display(UInt32)
    case window
}

public struct ScreenProfile: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var role: ScreenRole
    public var destination: OutputDestination
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, role: ScreenRole, destination: OutputDestination, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.role = role
        self.destination = destination
        self.isEnabled = isEnabled
    }
}

public enum RoutingFault: Sendable, Equatable, Hashable {
    case displayMissing
    case displayInUse(by: UUID)
    case operatorDisplay

    /// Text for the operator window. Says what happened and what to do.
    public var operatorMessage: String {
        switch self {
        case .displayMissing:
            return "The display for this screen is not connected. Reconnect it, or choose another display or a window."
        case .displayInUse:
            return "Another screen already uses this display. Give each screen its own display, or use a window."
        case .operatorDisplay:
            return "This is the display the operator window is on. Choose another display or a window so the output does not cover the controls."
        }
    }
}

public struct RoutingPlan: Sendable, Equatable {
    public var assignments: [UUID: OutputDestination]
    public var faults: [UUID: RoutingFault]

    public init(assignments: [UUID: OutputDestination] = [:], faults: [UUID: RoutingFault] = [:]) {
        self.assignments = assignments
        self.faults = faults
    }
}

public enum OutputRouter {
    /// Disabled profiles appear in neither list. The first profile in order keeps a contested display.
    public static func plan(profiles: [ScreenProfile], availableDisplays: [UInt32], operatorDisplay: UInt32?) -> RoutingPlan {
        var plan = RoutingPlan()
        var owners: [UInt32: UUID] = [:]
        let available = Set(availableDisplays)
        for profile in profiles where profile.isEnabled {
            switch profile.destination {
            case .window:
                plan.assignments[profile.id] = .window
            case .display(let id):
                if id == operatorDisplay {
                    plan.faults[profile.id] = .operatorDisplay
                } else if !available.contains(id) {
                    plan.faults[profile.id] = .displayMissing
                } else if let owner = owners[id] {
                    plan.faults[profile.id] = .displayInUse(by: owner)
                } else {
                    owners[id] = profile.id
                    plan.assignments[profile.id] = .display(id)
                }
            }
        }
        return plan
    }
}
