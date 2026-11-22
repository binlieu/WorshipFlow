// FIX-N items 6 and 9: the pointer state of the Stage canvas, held by the view. A press, its moves and its release are one drag; `finish` ends it and
// returns the one write, or nil when nothing moved. The view calls `finish` on the gesture's end and also when the drag was cut short (the window
// resigned key, the view disappeared, the layout changed), so the canvas is never left "pressed". Foundation and Domain only.
import Foundation
import Domain

public struct StagePointerSession: Equatable, Sendable {
    public struct Commit: Equatable, Sendable {
        public let elementID: UUID
        public let from: NormalizedRect
        public let to: NormalizedRect
        /// FIX-P item 3: the layout the drag began on (the view may show another one by the time the drag is cut short).
        public let layoutID: UUID?
    }

    public var pressed: Bool { guardState.pressed }
    public private(set) var drag: StageCanvasEditing.Drag?
    private var guardState = PressGuard()
    private var layoutID: UUID?

    public init() {}

    /// The first event of a press returns true (once); the events after it return false.
    public mutating func press() -> Bool { guardState.event() == .began }

    /// FIX-P item 4: like `press()`, for an event of a gesture that began at (`x`, `y`): false for the later events of the press and for the events of
    /// a press that `interrupt()` ended early, until the gesture's own end (`finish()`).
    public mutating func press(startedAt x: Double, _ y: Double) -> Bool { guardState.event(startedAt: .init(x: x, y: y)) == .began }

    /// Whether an event of this gesture is one to act on (the move events of the press), not one of an interrupted press.
    public mutating func accepts(startedAt x: Double, _ y: Double) -> Bool { guardState.event(startedAt: .init(x: x, y: y)) != .ignored }

    /// What the press picked: a box to move or resize, or nothing. `layoutID` is the layout it picked in.
    public mutating func begin(_ drag: StageCanvasEditing.Drag?, layoutID: UUID? = nil) { self.drag = drag; self.layoutID = layoutID }

    public mutating func update(dx: Double, dy: Double) { drag?.update(dx: dx, dy: dy) }

    /// Ends the press. The one write, if the box moved.
    @discardableResult
    public mutating func finish() -> Commit? {
        guardState.ended()
        return takeCommit()
    }

    /// FIX-P item 4: ends the press because something else cut it short (the window resigned key, the layout changed, the view went). The one write,
    /// if the box moved; the gesture's remaining events are ignored until its own end.
    @discardableResult
    public mutating func interrupt() -> Commit? {
        guardState.interrupt()
        return takeCommit()
    }

    private mutating func takeCommit() -> Commit? {
        defer { drag = nil; layoutID = nil }
        guard let drag, let change = drag.finish() else { return nil }
        return Commit(elementID: drag.elementID, from: change.from, to: change.to, layoutID: layoutID)
    }
}
