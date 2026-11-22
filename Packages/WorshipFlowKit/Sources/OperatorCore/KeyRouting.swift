// APP-001 / KI-021: which keys drive the show. The decision is a pure function so it can be tested; the app's key
// monitor only reads the window state, calls it, and acts on the answer. Foundation only.
import Foundation

public enum TransportCommand: Sendable, Equatable {
    case goLive, next, previous, clear
    /// UI-001: the B key. Toggles Blackout.
    case blackout
    /// Shift-Escape (R8): hides the words like `clear` and also stops the clip playing over the slide.
    case clearAll
}

/// The keys the operator window cares about. `init(keyCode:)` maps macOS virtual key codes.
public enum KeyboardKey: Sendable, Equatable {
    case returnKey, keypadEnter, space, leftArrow, rightArrow, upArrow, downArrow, escape, deleteKey, b, other

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
        case 11: self = .b
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
    /// R1: a transport key that is being held down (auto-repeat). Consumed and ignored: only the first press of a key
    /// moves the show, so holding Space or an arrow never runs the deck forward.
    case ignore
    /// FIX-H item 7: Escape on a focused control (a toggle, a slider, a button...): put keyboard focus back on the show (the slide grid), so
    /// the transport keys work again. Consumed.
    case focusShow
    /// The key is not ours: let the focused control, menu or system have it.
    case passThrough
}

/// FIX-H item 7: what has keyboard focus in the operator window, as far as the transport keys care.
public enum FocusedElement: Sendable, Equatable {
    /// Nothing in particular (the window, or a list the transport keys have always worked over).
    case none
    /// The slide grid: the show's own place.
    case slideGrid
    /// A text field or text editor (the search field excepted: `searchField`).
    case textInput
    case searchField
    /// A control that is not a text field. Space and Return act on it; arrows act on a slider or a segmented control.
    case toggle, checkbox, segmented, tab, slider, button, popUp

    /// True for the controls, which keep their own keys.
    public var isControl: Bool {
        switch self {
        case .toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp: true
        case .none, .slideGrid, .textInput, .searchField: false
        }
    }

    /// The kinds of AppKit view the key monitor can find as the first responder, so the mapping is testable without AppKit.
    public enum AppKitKind: Sendable, Equatable {
        case checkbox, switchButton, pushButton, radioButton, segmentedControl, slider, popUpButton, tabView, textInput, other
    }

    public static func appKit(_ kind: AppKitKind) -> FocusedElement {
        switch kind {
        case .checkbox: .checkbox
        case .switchButton: .toggle
        case .pushButton, .radioButton: .button
        case .segmentedControl: .segmented
        case .slider: .slider
        case .popUpButton: .popUp
        case .tabView: .tab
        case .textInput: .textInput
        case .other: .none
        }
    }
}

public enum KeyRouting {
    /// - Parameters:
    ///   - textInputFocused: a text field or text editor is being edited (includes the search field).
    ///   - searchFieldFocused: the search field is the one being edited.
    ///   - sheetOpen: a sheet, popover or dialog is open over the workspace.
    ///   - commandModifierDown: Command, Control or Option is held; those are menu shortcuts, never transport keys.
    ///   - shiftDown: Shift is held (Shift-Escape is Clear all).
    ///   - isRepeat: the event is an auto-repeat of a key that is still held (`NSEvent.isARepeat`).
    public static func decision(for key: KeyboardKey, textInputFocused: Bool, searchFieldFocused: Bool = false,
                                sheetOpen: Bool, commandModifierDown: Bool = false, shiftDown: Bool = false,
                                isRepeat: Bool = false) -> KeyDecision {
        guard !sheetOpen, !commandModifierDown else { return .passThrough }
        if textInputFocused {
            return searchFieldFocused && key == .escape ? .leaveSearch : .passThrough
        }
        if isRepeat {
            switch key {
            case .deleteKey, .other: return .passThrough
            default: return .ignore
            }
        }
        switch key {
        case .returnKey, .keypadEnter: return .transport(.goLive)
        case .space, .rightArrow, .downArrow: return .transport(.next)
        case .leftArrow, .upArrow: return .transport(.previous)
        case .escape: return .transport(shiftDown ? .clearAll : .clear)
        case .deleteKey: return .deleteSelectedObject
        case .b: return shiftDown ? .passThrough : .transport(.blackout)
        case .other: return .passThrough
        }
    }

    /// FIX-H item 7: like `decision(for:textInputFocused:...)`, with what actually has focus. A focused control keeps Space, Return and the
    /// arrows (and every other key); only Escape is ours, and it moves focus back to the show. The transport keys drive the show
    /// when nothing, or the slide grid, has focus.
    public static func decision(for key: KeyboardKey, focus: FocusedElement, sheetOpen: Bool, commandModifierDown: Bool = false,
                                shiftDown: Bool = false, isRepeat: Bool = false) -> KeyDecision {
        guard !sheetOpen, !commandModifierDown else { return .passThrough }
        switch focus {
        case .none, .slideGrid:
            return decision(for: key, textInputFocused: false, sheetOpen: false, commandModifierDown: false, shiftDown: shiftDown, isRepeat: isRepeat)
        case .textInput:
            return decision(for: key, textInputFocused: true, sheetOpen: false)
        case .searchField:
            return decision(for: key, textInputFocused: true, searchFieldFocused: true, sheetOpen: false)
        case .toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp:
            return key == .escape && !isRepeat ? .focusShow : .passThrough
        }
    }

    /// The show command for a key, or nil if the key is not for the transport right now.
    public static func transportCommand(for key: KeyboardKey, textInputFocused: Bool, sheetOpen: Bool,
                                        isRepeat: Bool = false) -> TransportCommand? {
        if case .transport(let command) = decision(for: key, textInputFocused: textInputFocused, sheetOpen: sheetOpen,
                                                    isRepeat: isRepeat) {
            return command
        }
        return nil
    }
}

// FIX-D S15: the transport keys (Space, Return, the arrows, B, Escape) drive the show, so they must not be active while the
// Hardware Test is what the person is looking at: they would move the hidden show and could open screens on the card under
// test. The decision is pure; the app's key monitor passes the window it was given and the launch mode.
extension KeyRouting {
    /// True for the Hardware Test window, by its title or by the identifier SwiftUI gives a window made with `id: "hardware-test"`.
    public static func isHardwareTestWindow(title: String?, identifier: String?) -> Bool {
        if let title, title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Hardware Test") == .orderedSame { return true }
        if let identifier, identifier.lowercased().contains("hardware-test") { return true }
        return false
    }

    /// UI-004: true for the About window (title "About WorshipFlow", or the identifier of the window made with `id: "about"`).
    public static func isAboutWindow(title: String?, identifier: String?) -> Bool {
        if let title, title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("About WorshipFlow") == .orderedSame { return true }
        if let identifier, identifier.lowercased().hasPrefix("about") { return true }
        return false
    }

    /// Whether the transport key monitor may act on a key pressed in `window`. Off in the Hardware Test window and, when the app
    /// was started with `--hardware-test`, everywhere: that session is a test of the card, not a service.
    public static func transportKeysActive(windowTitle: String?, windowIdentifier: String?, launchedWithHardwareTest: Bool) -> Bool {
        if launchedWithHardwareTest { return false }
        return !isHardwareTestWindow(title: windowTitle, identifier: windowIdentifier) && !isAboutWindow(title: windowTitle, identifier: windowIdentifier)
    }
}
