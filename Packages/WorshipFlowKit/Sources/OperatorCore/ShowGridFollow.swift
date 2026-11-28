// FIX-AB: which slide cell the Show grid brings into view after a change of the live place or of the selection.
import Foundation

public enum ShowGridFollow {
    /// What the grid follows: the live slide (only while the live presentation is the open one) and the selected slide.
    public struct Place: Equatable, Sendable {
        public var live: Int?
        public var selected: Int
        public init(live: Int?, selected: Int) { self.live = live; self.selected = selected }
    }

    /// The cell to reveal after `old` became `new`, nil for none. A live move wins over a selection move made in the same step. A cell that
    /// is not among the `count` slides is never named. Which scroll that takes (the smallest that shows the cell) is the view's.
    public static func target(from old: Place, to new: Place, count: Int) -> Int? {
        if new.live != old.live, let live = new.live, (0..<count).contains(live) { return live }
        if new.selected != old.selected, (0..<count).contains(new.selected) { return new.selected }
        return nil
    }
}
