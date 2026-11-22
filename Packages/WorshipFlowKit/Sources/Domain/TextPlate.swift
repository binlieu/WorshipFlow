// UI-005h (OUT, KEY): the pieces a theme and a scene gain for the design's output looks: a radial gradient background, and a plate
// (rounded rectangle with its own fill and opacity, padding and radius) with an accent bar behind lower-third text. Foundation only.
// Sizes that are not fractions are in points at a 1080-line reference height, as text sizes are; the compositor scales them.
import Foundation

/// A radial gradient over the whole frame, an ellipse like CSS `radial-gradient(<rx> <ry> at <x> <y>, ...)`.
public struct GradientBackground: Sendable, Equatable, Codable, Hashable {
    public struct Stop: Sendable, Equatable, Codable, Hashable {
        /// 0...1 along the radius.
        public var position: Double
        public var color: ColorRGBA

        public init(position: Double, color: ColorRGBA) {
            self.position = position.isFinite ? min(1, max(0, position)) : 0
            self.color = color
        }
    }

    /// At least two, in increasing position. Past the last stop the last colour continues.
    public var stops: [Stop]
    /// The centre as fractions of the frame's width and height.
    public var centerX: Double
    public var centerY: Double
    /// The ellipse's radii as multiples of the frame's width and height (1.1 = 110 % of the width).
    public var radiusX: Double
    public var radiusY: Double

    public init(stops: [Stop], centerX: Double, centerY: Double, radiusX: Double, radiusY: Double) {
        self.stops = stops.sorted { $0.position < $1.position }
        self.centerX = centerX.isFinite ? centerX : 0.5
        self.centerY = centerY.isFinite ? centerY : 0.5
        self.radiusX = radiusX.isFinite && radiusX > 0 ? radiusX : 1
        self.radiusY = radiusY.isFinite && radiusY > 0 ? radiusY : 1
    }
}

/// A vertical bar at the left of a plate's text, filled with a gradient from `top` to `bottom`. Its ends are fully rounded.
public struct AccentBar: Sendable, Equatable, Codable, Hashable {
    public var width: Double
    /// Space between the bar and the text, in points.
    public var gap: Double
    public var top: ColorRGBA
    public var bottom: ColorRGBA

    public init(width: Double, gap: Double, top: ColorRGBA, bottom: ColorRGBA) {
        self.width = width.isFinite ? max(0, width) : 0
        self.gap = gap.isFinite ? max(0, gap) : 0
        self.top = top
        self.bottom = bottom
    }
}

/// A rectangle behind text. It is as wide as `width` says, as tall as the plated text plus its padding, and sits `bottomMargin` above
/// the bottom of the frame. `fill`'s alpha is the plate's opacity, and it is the plate's value in the key matte too.
public struct TextPlate: Sendable, Equatable, Codable, Hashable {
    /// Left edge and width as fractions of the frame's width.
    public var x: Double
    public var width: Double
    /// Distance from the plate's bottom edge to the frame's bottom edge, in points.
    public var bottomMargin: Double
    public var fill: ColorRGBA
    public var cornerRadius: Double
    public var paddingX: Double
    public var paddingY: Double
    public var bar: AccentBar?

    public init(x: Double, width: Double, bottomMargin: Double, fill: ColorRGBA, cornerRadius: Double,
                paddingX: Double, paddingY: Double, bar: AccentBar? = nil) {
        func finite(_ v: Double, _ low: Double, _ fallback: Double) -> Double { v.isFinite ? max(low, v) : fallback }
        self.x = x.isFinite ? min(1, max(0, x)) : 0
        self.width = width.isFinite ? min(1, max(0, width)) : 1
        self.bottomMargin = finite(bottomMargin, 0, 0)
        self.fill = fill
        self.cornerRadius = finite(cornerRadius, 0, 0)
        self.paddingX = finite(paddingX, 0, 0)
        self.paddingY = finite(paddingY, 0, 0)
        self.bar = bar
    }
}
