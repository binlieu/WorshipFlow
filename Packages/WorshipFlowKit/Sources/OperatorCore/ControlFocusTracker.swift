// FIX-I item 1: which control, if any, owns the keyboard. Each control the app draws reports its own SwiftUI focus under its own identity.
// SwiftUI's `isFocused` environment value is inherited by every view under a focused `.focusable()` container, so while the slide grid
// itself has focus the controls in its container (the media dock's pop-up and buttons) all report true. Those reports are not a control
// having focus and are ignored while the grid has it. Foundation only.
import Foundation

public struct ControlFocusTracker: Sendable, Equatable {
    private struct Entry: Sendable, Equatable { let id: UUID; let kind: FocusedElement }
    private var entries: [Entry] = []      // oldest first

    public init() {}

    /// A control gained or lost focus (as far as SwiftUI says).
    public mutating func report(id: UUID, kind: FocusedElement, focused: Bool) {
        entries.removeAll { $0.id == id }
        if focused { entries.append(Entry(id: id, kind: kind)) }
    }

    /// The control left the screen.
    public mutating func remove(id: UUID) { entries.removeAll { $0.id == id } }

    /// Escape: keyboard focus goes back to the show.
    public mutating func clear() { entries.removeAll() }

    /// The control that owns the keys now: the newest report, unless the slide grid itself has focus (then the reports are inherited).
    public func current(gridHasFocus: Bool) -> FocusedElement? {
        gridHasFocus ? nil : entries.last?.kind
    }
}
