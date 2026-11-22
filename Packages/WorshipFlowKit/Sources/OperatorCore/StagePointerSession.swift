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
    }

    public private(set) var pressed = false
    public private(set) var drag: StageCanvasEditing.Drag?

    public init() {}

    /// The first event of a press returns true (once); the events after it return false.
    public mutating func press() -> Bool {
        guard !pressed else { return false }
        pressed = true
        return true
    }

    /// What the press picked: a box to move or resize, or nothing.
    public mutating func begin(_ drag: StageCanvasEditing.Drag?) { self.drag = drag }

    public mutating func update(dx: Double, dy: Double) { drag?.update(dx: dx, dy: dy) }

    /// Ends the press. The one write, if the box moved.
    @discardableResult
    public mutating func finish() -> Commit? {
        pressed = false
        defer { drag = nil }
        guard let drag, let change = drag.finish() else { return nil }
        return Commit(elementID: drag.elementID, from: change.from, to: change.to)
    }
}
