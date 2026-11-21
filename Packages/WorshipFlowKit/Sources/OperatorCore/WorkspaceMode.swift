// UI-001 / ADR-0007: the six modes of the operator window. The mode is a view choice only: it never changes the show,
// and the transport bar and transport keys work in every mode. Foundation only.
import Foundation

public enum WorkspaceMode: String, CaseIterable, Sendable, Equatable, Identifiable {
    case show, edit, media, stage, cues, screens

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .show: "Show"
        case .edit: "Edit"
        case .media: "Media"
        case .stage: "Stage"
        case .cues: "Cues"
        case .screens: "Screens"
        }
    }

    /// Command-1 to Command-6, in the order of the switcher.
    public var commandDigit: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    public init?(commandDigit: Int) {
        guard let mode = Self.allCases.first(where: { $0.commandDigit == commandDigit }) else { return nil }
        self = mode
    }

    public init?(shortcutCharacter: Character) {
        guard let digit = shortcutCharacter.wholeNumberValue else { return nil }
        self.init(commandDigit: digit)
    }

    /// What was saved, or Show for a first run or a value that is not a mode.
    public static func restored(from stored: String?) -> WorkspaceMode {
        stored.flatMap(WorkspaceMode.init(rawValue:)) ?? .show
    }
}
