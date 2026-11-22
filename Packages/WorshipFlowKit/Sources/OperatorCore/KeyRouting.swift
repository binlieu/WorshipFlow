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

/// FIX-I item 2: the part of Show the arrow keys act on: the slide grid or the media bin, whichever was clicked last.
public enum KeySection: Sendable, Equatable {
    case slideGrid, mediaBin

    /// What happened that may move the arrows from one section to the other.
    public enum Event: Sendable, Equatable {
        case launch, presentationOpened, clickedSlideGrid, clickedMediaBin
        /// A click in the sidebar, the playlist, the inspector, the toolbar or anywhere else: the arrows stay where they were.
        case clickedElsewhere
    }

    public static func after(_ event: Event, from current: KeySection) -> KeySection {
        switch event {
        case .launch, .presentationOpened, .clickedSlideGrid: .slideGrid
        case .clickedMediaBin: .mediaBin
        case .clickedElsewhere: current
        }
    }
}

/// FIX-I item 2: an arrow key, as a move of the selection.
public enum SelectionMove: Sendable, Equatable {
    case left, right, up, down
}

public enum KeyDecision: Sendable, Equatable {
    /// The key drives the show and is consumed.
    case transport(TransportCommand)
    /// FIX-I item 2: an arrow key moves the selection (Preview) in the keyboard's section. It never changes what is live. Consumed.
    case moveSelection(SelectionMove)
    /// FIX-I item 2: Return with the media bin as the keyboard's section: send the selected bin item live, as a double click does. Consumed.
    case sendBinSelectionLive
    /// Escape in the search field: leave it and put keyboard focus back on the slide grid. Consumed.
    case leaveSearch
    /// SLIDE-001b: Delete with nothing being typed: remove the selected slide object, if there is one. The app lets
    /// the key through when no object is selected.
    case deleteSelectedObject
    /// R1: a transport key that is being held down (auto-repeat). Consumed and ignored: only the first press of a key
    /// moves the show, so holding Space or an arrow never runs the deck forward.
    case ignore
    /// FIX-N item 8: an arrow key nudges the selected canvas box (Stage or Edit) although keyboard focus sits on a button, toggle or checkbox, because the
    /// canvas was the last thing clicked. Consumed.
    case nudgeCanvas(SelectionMove)
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
    /// FIX-N item 1: a canvas that edits boxes (the Stage canvas's key-catching view). It is not a control: it takes only the arrow keys, and only
    /// while a box is selected; every other key is routed as if the slide grid had focus, so the show's keys always work.
    case canvas

    /// True for the controls, which keep their own keys.
    public var isControl: Bool {
        switch self {
        case .toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp: true
        case .none, .slideGrid, .textInput, .searchField, .canvas: false
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
                                section: KeySection = .slideGrid, sheetOpen: Bool, commandModifierDown: Bool = false, shiftDown: Bool = false,
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
        case .returnKey, .keypadEnter: return section == .mediaBin ? .sendBinSelectionLive : .transport(.goLive)
        case .space: return .transport(shiftDown ? .previous : .next)      // FIX-I item 2: Space is Next from either section, Shift-Space is Previous
        case .rightArrow: return .moveSelection(.right)
        case .leftArrow: return .moveSelection(.left)
        case .downArrow: return .moveSelection(.down)
        case .upArrow: return .moveSelection(.up)
        case .escape: return .transport(shiftDown ? .clearAll : .clear)
        case .deleteKey: return .deleteSelectedObject
        case .b: return shiftDown ? .passThrough : .transport(.blackout)
        case .other: return .passThrough
        }
    }

    /// FIX-H item 7: like `decision(for:textInputFocused:...)`, with what actually has focus. A focused control keeps Space, Return and the
    /// arrows (and every other key); only Escape is ours, and it moves focus back to the show. The transport keys drive the show
    /// when nothing, or the slide grid, has focus.
    /// `canvasHasSelection` matters only for `.canvas` focus: with a box selected the canvas keeps the arrow keys (with or without Shift, held or
    /// not: it nudges the box), without one the arrows move the slide selection as they do from the grid.
    /// `canvasLastClicked` (FIX-N item 8): the last mouse click was on a canvas box. With a box selected, a button, toggle or checkbox that has keyboard
    /// focus (they have no use for arrows) no longer takes the arrow keys from the box.
    public static func decision(for key: KeyboardKey, focus: FocusedElement, canvasHasSelection: Bool = false, canvasLastClicked: Bool = false,
                                section: KeySection = .slideGrid, sheetOpen: Bool,
                                commandModifierDown: Bool = false, shiftDown: Bool = false, isRepeat: Bool = false) -> KeyDecision {
        guard !sheetOpen, !commandModifierDown else { return .passThrough }
        switch focus {
        case .canvas:
            if canvasHasSelection, [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(key) { return .passThrough }
            return decision(for: key, textInputFocused: false, section: section, sheetOpen: false, commandModifierDown: false, shiftDown: shiftDown, isRepeat: isRepeat)
        case .none, .slideGrid:
            return decision(for: key, textInputFocused: false, section: section, sheetOpen: false, commandModifierDown: false, shiftDown: shiftDown, isRepeat: isRepeat)
        case .textInput:
            return decision(for: key, textInputFocused: true, sheetOpen: false)
        case .searchField:
            return decision(for: key, textInputFocused: true, searchFieldFocused: true, sheetOpen: false)
        case .toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp:
            if canvasHasSelection, canvasLastClicked, [.toggle, .checkbox, .button].contains(focus), let move = arrowMove(key) { return .nudgeCanvas(move) }
            return key == .escape && !isRepeat ? .focusShow : .passThrough
        }
    }

    private static func arrowMove(_ key: KeyboardKey) -> SelectionMove? {
        switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        case .downArrow: .down
        default: nil
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

/// FIX-N items 1 and 8: whether the mode that is showing has a canvas with a box selected that the arrow keys may nudge. Only Edit and Stage have a canvas.
public enum CanvasArrows {
    public static func hasSelection(mode: WorkspaceMode, editHasSelection: Bool, stageTakesArrows: Bool) -> Bool {
        switch mode {
        case .edit: editHasSelection
        case .stage: stageTakesArrows
        case .show, .media, .cues, .screens: false
        }
    }
}
