// UI-005h: where the compositor puts text, the plate and the accent bar, in output pixels, for measuring a composition against the design
// (scripts and tests compare these with the mockup's rectangles). Measurement only: the live path does not call it.
import Foundation
import Domain

public struct LayoutBox: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct TextLayoutItem: Sendable, Equatable {
    public var text: String
    /// The text block's line boxes: the widest line wide, the lines' pitch times their count tall.
    public var box: LayoutBox
    /// Font size in output pixels.
    public var fontSize: Double
    /// The CSS weight (400 when the style has none).
    public var weight: Int
    public var lineCount: Int
    public var inPlate: Bool
}

public struct SceneLayoutReport: Sendable, Equatable {
    public var texts: [TextLayoutItem] = []
    public var plate: LayoutBox?
    public var bar: LayoutBox?
}
