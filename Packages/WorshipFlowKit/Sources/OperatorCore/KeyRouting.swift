// APP-001 / KI-021: which keys drive the show. The decision is a pure function so it can be tested; the app's key
// monitor only reads the window state, calls it, and acts on the answer. Foundation only.
import Foundation

public enum TransportCommand: Sendable, Equatable {
    case goLive, next, previous, clear
}

/// The keys the operator window cares about. `init(keyCode:)` maps macOS virtual key codes.
public enum KeyboardKey: Sendable, Equatable {
    case returnKey, keypadEnter, space, leftArrow, rightArrow, upArrow, downArrow, escape, deleteKey, other

    public init(keyCode: UInt16) {
        switch keyCode {
        case 36: self = .returnKey
        case 76: self = .keypadEnter
        case 49: self = .space
        case 123: self = .leftArrow
        case 124: self = .rightArrow
        case 126: self = .upArrow
        case 125: self = .downArrow
        case 53: self = .escape
        case 51, 117: self = .deleteKey          // Delete (backspace) and forward delete
        default: self = .other
        }
    }
}

public enum KeyDecision: Sendable, Equatable {
    /// The key drives the show and is consumed.
    case transport(TransportCommand)
    /// Escape in the search field: leave it and put keyboard focus back on the slide grid. Consumed.
    case leaveSearch
    /// SLIDE-001b: Delete with nothing being typed: remove the selected slide object, if there is one. The app lets
    /// the key through when no object is selected.
    case deleteSelectedObject
    /// The key is not ours: let the focused control, menu or system have it.
    case passThrough
}

public enum KeyRouting {
    /// - Parameters:
    ///   - textInputFocused: a text field or text editor is being edited (includes the search field).
    ///   - searchFieldFocused: the search field is the one being edited.
    ///   - sheetOpen: a sheet, popover or dialog is open over the workspace.
    ///   - commandModifierDown: Command, Control or Option is held; those are menu shortcuts, never transport keys.
    public static func decision(for key: KeyboardKey, textInputFocused: Bool, searchFieldFocused: Bool = false,
                                sheetOpen: Bool, commandModifierDown: Bool = false) -> KeyDecision {
        guard !sheetOpen, !commandModifierDown else { return .passThrough }
        if textInputFocused {
            return searchFieldFocused && key == .escape ? .leaveSearch : .passThrough
        }
        switch key {
        case .returnKey, .keypadEnter: return .transport(.goLive)
        case .space, .rightArrow, .downArrow: return .transport(.next)
        case .leftArrow, .upArrow: return .transport(.previous)
        case .escape: return .transport(.clear)
        case .deleteKey: return .deleteSelectedObject
        case .other: return .passThrough
        }
    }

    /// The show command for a key, or nil if the key is not for the transport right now.
    public static func transportCommand(for key: KeyboardKey, textInputFocused: Bool, sheetOpen: Bool) -> TransportCommand? {
        if case .transport(let command) = decision(for: key, textInputFocused: textInputFocused, sheetOpen: sheetOpen) {
            return command
        }
        return nil
    }
}
