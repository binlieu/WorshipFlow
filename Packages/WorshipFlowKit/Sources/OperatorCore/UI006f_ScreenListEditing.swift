// UI-006f (SC-03, SC-40): adding and removing a screen, as pure functions on the screen list and the Looks.
// Foundation and Domain only. `SettingsModel.addProfile` / `removeProfile` call these and write the result.
import Foundation
import Domain

public enum ScreenListEditing {
    /// A screen that was just added starts OFF and in a window. Adding a screen must never put a new picture on a projector, a
    /// confidence monitor or a card output by itself: the operator chooses the destination and then turns it on.
    public static func newScreen(existing: [ScreenProfile]) -> ScreenProfile {
        ScreenProfile(name: freshName(existing: existing), role: .audience, destination: .window, isEnabled: false)
    }

    /// "Screen 2", "Screen 3", ...: the smallest number above the list's size that no existing screen uses (compared without case).
    public static func freshName(existing: [ScreenProfile]) -> String {
        let taken = Set(existing.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var n = existing.count + 1
        while taken.contains("screen \(n)") { n += 1 }
        return "Screen \(n)"
    }

    /// The show always has at least one screen: the last one cannot be removed.
    public static func canRemove(_ id: UUID, from profiles: [ScreenProfile]) -> Bool {
        profiles.count > 1 && profiles.contains { $0.id == id }
    }

    public static func removing(_ id: UUID, from profiles: [ScreenProfile]) -> [ScreenProfile] {
        canRemove(id, from: profiles) ? profiles.filter { $0.id != id } : profiles
    }

    /// The row that is selected after `id` is removed: the one that took its place, else the one before it.
    public static func selection(afterRemoving id: UUID, from profiles: [ScreenProfile]) -> UUID? {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return profiles.first?.id }
        let rest = profiles.filter { $0.id != id }
        return rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
    }

    /// A Look's entry for a screen that was removed. A screen with no entry of its own follows the first screen of its role that has
    /// one (`Look.screenLook(for:in:)`), so dropping the removed screen's entry could change how a surviving screen looks. When no
    /// surviving screen of that role has its own entry, the entry moves to the first of them, so each keeps showing what it showed.
    public static func look(_ look: Look, afterRemoving id: UUID, before: [ScreenProfile]) -> Look {
        guard let entry = look.screens[id], let removed = before.first(where: { $0.id == id }) else { return look }
        var result = look
        result.screens[id] = nil
        let survivors = before.filter { $0.id != id && $0.role == removed.role }
        if !survivors.contains(where: { look.screens[$0.id] != nil }), let heir = survivors.first { result.screens[heir.id] = entry }
        return result
    }
}

/// UI-006f (SC-21): what "Identify screens" puts on each connected display. Only displays: an SDI connector has no display to label and
/// nothing here sends video to a card.
public struct ScreenIdentifyLabel: Sendable, Equatable {
    public var displayID: UInt32
    public var title: String
    public var detail: String
}

public enum ScreenIdentify {
    /// Labels would cover what the outputs show, so they are offered only while the screens are closed.
    public static func isAllowed(screensOpen: Bool) -> Bool { !screensOpen }

    public static let blockedReason = "Close the screens first: the labels would cover what the outputs are showing."

    /// One label per display. The operator's own display says so; a display a screen is set to names that screen (two screens set to
    /// one display name both); any other display says no screen uses it. Disabled screens count: the label is about the setting.
    public static func labels(displays: [(id: UInt32, name: String)], profiles: [ScreenProfile], operatorDisplay: UInt32?) -> [ScreenIdentifyLabel] {
        displays.map { display in
            let users = profiles.filter { profile in
                ([profile.destination] + profile.mirrors).contains { $0 == .display(display.id) }
            }
            if display.id == operatorDisplay {
                let note = users.isEmpty ? "WorshipFlow controls are on this display." : "Screens set to this display: \(users.map(\.name).joined(separator: ", "))."
                return ScreenIdentifyLabel(displayID: display.id, title: "Operator display", detail: note)
            }
            if users.isEmpty { return ScreenIdentifyLabel(displayID: display.id, title: display.name, detail: "No screen is set to this display.") }
            let roles = users.map { "\($0.name) (\($0.role.rawValue))" }.joined(separator: ", ")
            return ScreenIdentifyLabel(displayID: display.id, title: users.map(\.name).joined(separator: ", "), detail: roles)
        }
    }
}
