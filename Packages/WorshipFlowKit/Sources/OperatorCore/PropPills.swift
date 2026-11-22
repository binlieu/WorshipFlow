// FIX-H item 10 (UI-005b): the AUD, STG and BRD pills of a prop and the rules for saving a text prop. Foundation and Domain only.
import Foundation
import Domain

/// One role's pill on a prop's row. Every role has one; a role the prop is not shown on is dimmed, not removed, so the same pill can
/// turn it on again.
public struct PropPill: Equatable, Sendable {
    public var role: ScreenRole
    public var isOn: Bool
    public var label: String
    public var isDimmed: Bool { !isOn }
}

public enum PropPills {
    public static func pills(for prop: Prop) -> [PropPill] {
        ScreenRole.allCases.map { PropPill(role: $0, isOn: prop.targets.contains($0), label: label(for: $0)) }
    }

    public static func label(for role: ScreenRole) -> String {
        switch role { case .audience: "AUD"; case .stage: "STG"; case .broadcast: "BRD" }
    }
}

public enum TextPropRules {
    /// Said under the Save button of the new text prop sheet.
    public static let savedOffNote = "Saved off. Switch it on when you want it shown."

    /// Why a text prop cannot be saved yet, in words for the operator; nil when it can.
    public static func problem(name: String, targets: Set<ScreenRole>) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the prop a name. Nothing was saved." }
        if targets.isEmpty { return "Choose at least one screen to show it on. Nothing was saved." }
        return nil
    }
}
