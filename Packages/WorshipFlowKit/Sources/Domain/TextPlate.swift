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

        private enum CodingKeys: String, CodingKey { case position, color }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(position: try c.decode(Double.self, forKey: .position), color: try c.decode(ColorRGBA.self, forKey: .color))
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
        // FIX-J: at least two stops in increasing position (none: black; one: that colour to the end), a centre within a few frames of the
        // picture and radii that are neither zero nor huge, whether the gradient is built or read from a stored row.
        var sorted = stops.sorted { $0.position < $1.position }
        if sorted.isEmpty { sorted = [Stop(position: 0, color: .black), Stop(position: 1, color: .black)] }
        if sorted.count == 1, let only = sorted.first { sorted.append(Stop(position: 1, color: only.color)) }
        self.stops = sorted
        self.centerX = centerX.isFinite ? min(8, max(-8, centerX)) : 0.5
        self.centerY = centerY.isFinite ? min(8, max(-8, centerY)) : 0.5
        self.radiusX = radiusX.isFinite && radiusX > 0 ? min(16, radiusX) : 1
        self.radiusY = radiusY.isFinite && radiusY > 0 ? min(16, radiusY) : 1
    }

    private enum CodingKeys: String, CodingKey { case stops, centerX, centerY, radiusX, radiusY }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stops: try c.decode([Stop].self, forKey: .stops), centerX: try c.decode(Double.self, forKey: .centerX),
                  centerY: try c.decode(Double.self, forKey: .centerY), radiusX: try c.decode(Double.self, forKey: .radiusX),
                  radiusY: try c.decode(Double.self, forKey: .radiusY))
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
        self.width = width.isFinite ? min(1000, max(0, width)) : 0
        self.gap = gap.isFinite ? min(1000, max(0, gap)) : 0
        self.top = top
        self.bottom = bottom
    }

    private enum CodingKeys: String, CodingKey { case width, gap, top, bottom }
    /// FIX-J: a stored bar goes through the initialiser.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(width: try c.decode(Double.self, forKey: .width), gap: try c.decode(Double.self, forKey: .gap),
                  top: try c.decode(ColorRGBA.self, forKey: .top), bottom: try c.decode(ColorRGBA.self, forKey: .bottom))
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
        func finite(_ v: Double, _ high: Double) -> Double { v.isFinite ? min(high, max(0, v)) : 0 }
        self.x = x.isFinite ? min(1, max(0, x)) : 0
        self.width = width.isFinite ? min(1, max(0, width)) : 1
        self.bottomMargin = finite(bottomMargin, 2000)
        self.fill = fill
        self.cornerRadius = finite(cornerRadius, 1000)
        self.paddingX = finite(paddingX, 1000)
        self.paddingY = finite(paddingY, 1000)
        self.bar = bar
    }

    private enum CodingKeys: String, CodingKey { case x, width, bottomMargin, fill, cornerRadius, paddingX, paddingY, bar }
    /// FIX-J: a stored plate goes through the initialiser, so its radius, padding, margin and opacity are clamped as a constructed one's are.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try c.decode(Double.self, forKey: .x), width: try c.decode(Double.self, forKey: .width),
                  bottomMargin: try c.decode(Double.self, forKey: .bottomMargin), fill: try c.decode(ColorRGBA.self, forKey: .fill),
                  cornerRadius: try c.decode(Double.self, forKey: .cornerRadius), paddingX: try c.decode(Double.self, forKey: .paddingX),
                  paddingY: try c.decode(Double.self, forKey: .paddingY), bar: try c.decodeIfPresent(AccentBar.self, forKey: .bar))
    }
}
