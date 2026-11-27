// FIX-Y (OUT, SC-51; REVIEW-5 L15): the words about Looks that were wrong once a screen could keep a Look of its own (UI-007f), and the question asked before
// a Look is deleted. Pure: the views read these and draw them. Foundation and Domain only.
import Foundation
import Domain

public enum LookNotices {
    /// The Look panel's one line of help.
    public static let panelText = "A Look sets the theme and visible layers of each screen below. Switching Look changes every screen that follows the show's Look; a screen with a Look of its own (chosen in Screens) keeps it."

    /// Show's line under the Look buttons: the screens that keep a Look other than the show's, with that Look. Nil when none does.
    public static func ownLookNotice(profiles: [ScreenProfile], global: Look?, looks: [Look], shown: Int = 2) -> String? {
        let own = ScreenLooks.overrides(profiles: profiles, global: global, looks: looks)
        let entries = profiles.compactMap { profile in own[profile.id].map { "\(profile.name) (\($0.name))" } }
        guard !entries.isEmpty else { return nil }
        let head = entries.prefix(shown).joined(separator: ", ")
        let more = entries.count > shown ? ", +\(entries.count - shown) more" : ""
        return "Own Look, not changed here: \(head)\(more)"
    }

    public struct Prompt: Equatable, Sendable {
        public var title: String
        public var message: String
        /// The label of the one button that deletes. The other choice is Cancel, and Cancel is the default.
        public var confirmTitle: String
    }

    /// What deleting a Look does: screens that chose it go back to the show's Look at once, and the show itself switches when this is its Look.
    public static func deletePrompt(look: Look, isShowLook: Bool, profiles: [ScreenProfile]) -> Prompt {
        var parts: [String] = []
        let chose = profiles.filter { $0.screenLookID == look.id }.map(\.name)
        if !chose.isEmpty {
            parts.append("\(chose.joined(separator: ", ")) chose it and will follow the show's Look again, at once.")
        }
        if isShowLook { parts.append("It is the show's Look: the show switches to another Look, at once, on every screen that follows it.") }
        parts.append("The themes it uses are not deleted. This cannot be undone.")
        return Prompt(title: "Delete the Look \u{201C}\(look.name)\u{201D}?", message: parts.joined(separator: " "), confirmTitle: "Delete Look")
    }
}
