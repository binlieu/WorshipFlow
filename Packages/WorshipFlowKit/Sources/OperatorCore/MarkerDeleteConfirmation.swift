// FIX-X (MEDIA, CUE-33; REVIEW-5 L9, L13): deleting a playback marker takes its cue actions with it and there is no undo, so a marker that has actions asks
// first. This is the one decision the marker list in the Media mode uses: does the delete need a confirmation, and with what words. Foundation only.
import Foundation

public enum MarkerDeleteConfirmation {
    public struct Prompt: Equatable, Sendable {
        public var title: String
        public var message: String
        /// The label of the one button that deletes. The other choice is Cancel, and Cancel is the default.
        public var confirmTitle: String
    }

    /// Nil when the marker may be deleted at once (it has no actions and its stored actions text is readable). Otherwise the question to ask. `name` is
    /// the marker's name, or nil when it has none, and then its time is used to name it.
    public static func prompt(name: String?, time: Double, actionCount: Int, actionsAreUnreadable: Bool) -> Prompt? {
        guard actionCount > 0 || actionsAreUnreadable else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = trimmed.isEmpty ? "the marker at \(MediaTimeText.format(time))" : "the marker \u{201C}\(trimmed)\u{201D}"
        let goes: String
        if actionCount > 0 {
            goes = "its \(actionCount) action\(actionCount == 1 ? "" : "s")"
        } else {
            goes = "the actions stored on it, which this version cannot read"
        }
        return Prompt(title: "Delete \(label)?",
                      message: "\(goes.prefix(1).uppercased())\(goes.dropFirst()) will be deleted with it. This cannot be undone.",
                      confirmTitle: "Delete marker")
    }
}
