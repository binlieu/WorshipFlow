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

    /// FIX-V item 2 (REVIEW-4 M4): why this screen cannot be removed now, or nil. It is refused while its output is running (`activeOutputs`: the
    /// screens whose output runs, is hidden or faulted), and while the screens are open and it is the only enabled screen of its role (that role
    /// would go dark mid-service). Closing the screens first makes it removable.
    public static func removalBlock(_ id: UUID, profiles: [ScreenProfile], activeOutputs: Set<UUID>, screensOpen: Bool) -> String? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return "That screen is already gone." }
        guard profiles.count > 1 else { return "The last screen cannot be removed." }
        if activeOutputs.contains(id) { return "\(profile.name) is on air. Close the screens first, then remove it." }
        if screensOpen, profile.isEnabled, !profiles.contains(where: { $0.id != id && $0.role == profile.role && $0.isEnabled }) {
            return "\(profile.name) is the only \(profile.role.rawValue) screen on air. Close the screens first, then remove it."
        }
        return nil
    }

    /// What goes with a screen, for the confirmation: its entry in each Look (and which screen inherits it), its stage layout choice.
    public struct RemovalImpact: Sendable, Equatable {
        public var lookCount: Int
        /// Look name to the surviving screen that takes over the removed screen's entry (see `look(_:afterRemoving:before:)`).
        public var handedTo: [String: String]
        public var hasStageLayoutChoice: Bool

        public var text: String {
            var parts: [String] = []
            if lookCount > 0 {
                var s = "its settings in \(lookCount) Look\(lookCount == 1 ? "" : "s")"
                if !handedTo.isEmpty {
                    let moves = handedTo.sorted { $0.key < $1.key }.map { "\($0.key) to \($0.value)" }.joined(separator: ", ")
                    s += " (the entry moves, so that screen keeps showing what it showed: \(moves))"
                }
                parts.append(s)
            }
            if hasStageLayoutChoice { parts.append("its stage layout choice") }
            parts.append("its destination, mirrors and notes")
            return "Its output stops and " + parts.joined(separator: ", ") + " are forgotten. This cannot be undone. Your slides and media are not touched."
        }
    }

    public static func removalImpact(_ id: UUID, profiles: [ScreenProfile], looks: [Look], hasStageLayoutChoice: Bool) -> RemovalImpact {
        var handed: [String: String] = [:]
        var count = 0
        for look in looks where look.screens[id] != nil {
            count += 1
            let after = Self.look(look, afterRemoving: id, before: profiles)
            if let heir = profiles.first(where: { $0.id != id && look.screens[$0.id] == nil && after.screens[$0.id] != nil }) { handed[look.name] = heir.name }
        }
        return RemovalImpact(lookCount: count, handedTo: handed, hasStageLayoutChoice: hasStageLayoutChoice)
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
