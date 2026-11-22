// FIX-K item 7: dragging a column's resize strip. Measured in build 115 with 200 slides and 100 bin items, every drag event laid out the whole Show window again
// (55 to 70 ms per event). The strip now follows the pointer with a guide line only; the layout changes once, when the pointer is released. Foundation only.
import Foundation

public struct ColumnDrag: Equatable, Sendable {
    public let range: ClosedRange<Double>
    /// +1 when dragging right widens the column (the sidebar), -1 when dragging left widens it (the inspector).
    public let grows: Double
    private var start: Double?
    /// Where the column would be if the pointer were released now. The layout is not changed to this width until `end()`.
    public private(set) var proposed: Double?

    public init(range: ClosedRange<Double>, grows: Double) {
        self.range = range
        self.grows = grows
    }

    public var isDragging: Bool { start != nil }

    /// A pointer event of the drag: `translation` is the pointer's travel so far in points, `width` the column's committed width.
    public mutating func change(translation: Double, from width: Double) {
        if start == nil { start = width }
        proposed = min(max((start ?? width) + grows * translation, range.lowerBound), range.upperBound)
    }

    /// The pointer is released: the one width to apply, or nil when the strip was only pressed.
    public mutating func end() -> Double? {
        defer { start = nil; proposed = nil }
        return proposed
    }
}
