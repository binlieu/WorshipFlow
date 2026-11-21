// SLIDE-001a: objects on a slide (PRES-01, MEDIA-07): text boxes, shapes and images, back to front. Foundation only.
import Foundation

public struct TextObject: Sendable, Equatable, Codable, Hashable {
    public var text: String
    public var style: TextStyle
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment

    public init(text: String, style: TextStyle, alignment: TextAlignment = .center,
                verticalAlignment: VerticalAlignment = .center) {
        self.text = text
        self.style = style
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }
}

public struct ShapeObject: Sendable, Equatable, Codable, Hashable {
    public enum Shape: Sendable, Equatable, Codable, Hashable {
        case rectangle
        case ellipse
        /// `cornerRadius` is a fraction of the shorter side, 0...0.5.
        case roundedRectangle(cornerRadius: Double)
    }

    public var shape: Shape
    /// Nil: no fill.
    public var fill: ColorRGBA?
    /// Nil or a zero width: no stroke.
    public var strokeColor: ColorRGBA?
    /// Points at a 1080-line reference height, drawn inside the frame edge.
    public var strokeWidth: Double

    public init(shape: Shape, fill: ColorRGBA?, strokeColor: ColorRGBA? = nil, strokeWidth: Double = 0) {
        self.shape = shape
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth.isFinite ? max(0, strokeWidth) : 0
    }
}

public struct ImageObject: Sendable, Equatable, Codable, Hashable {
    public var path: String
    public var contentMode: ImageContentMode

    public init(path: String, contentMode: ImageContentMode = .fit) {
        self.path = path
        self.contentMode = contentMode
    }
}

public struct SlideObject: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Content: Sendable, Equatable, Codable, Hashable {
        case text(TextObject)
        case shape(ShapeObject)
        case image(ImageObject)
    }

    /// Smallest width or height an object can be given, as a fraction of the slide.
    public static let minimumSize = 0.02

    public var id: UUID
    public var frame: NormalizedRect
    /// 0...1; values outside are clamped.
    public var opacity: Double {
        didSet { opacity = Self.clamp(opacity) }
    }
    public var content: Content

    public init(id: UUID = UUID(), frame: NormalizedRect, opacity: Double = 1, content: Content) {
        self.id = id
        self.frame = frame
        self.opacity = Self.clamp(opacity)
        self.content = content
    }

    private static func clamp(_ v: Double) -> Double { v.isNaN ? 1 : min(1, max(0, v)) }

    private enum CodingKeys: String, CodingKey { case id, frame, opacity, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), frame: try c.decode(NormalizedRect.self, forKey: .frame),
                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
                  content: try c.decode(Content.self, forKey: .content))
    }

    /// Moves the frame, keeping it on the slide.
    public mutating func move(dx: Double, dy: Double) {
        let nx = frame.x + (dx.isFinite ? dx : 0), ny = frame.y + (dy.isFinite ? dy : 0)
        frame.x = max(0, min(1 - frame.width, nx))
        frame.y = max(0, min(1 - frame.height, ny))
    }

    /// Sets the size, keeping the top-left corner where it is when it can and the frame on the slide.
    /// Never smaller than `minimumSize`; if that no longer fits to the right or below, the frame slides back.
    public mutating func resize(width: Double, height: Double) {
        let minimum = Self.minimumSize
        var w = width.isNaN ? minimum : min(width, 1 - frame.x)
        var h = height.isNaN ? minimum : min(height, 1 - frame.y)
        if w < minimum { w = minimum; frame.x = 1 - minimum }
        if h < minimum { h = minimum; frame.y = 1 - minimum }
        frame.width = w
        frame.height = h
    }
}

// MARK: Scene layers

/// A shape ready to draw. Stroke width is in points at a 1080-line reference height.
public struct ShapeLayer: Sendable, Equatable, Codable, Hashable {
    public var shape: ShapeObject.Shape
    public var fill: ColorRGBA?
    public var strokeColor: ColorRGBA?
    public var strokeWidth: Double
    public var frame: NormalizedRect
    public var opacity: Double

    public init(shape: ShapeObject.Shape, fill: ColorRGBA?, strokeColor: ColorRGBA? = nil, strokeWidth: Double = 0,
                frame: NormalizedRect, opacity: Double = 1) {
        self.shape = shape
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth.isFinite ? max(0, strokeWidth) : 0
        self.frame = frame
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
    }
}

/// One drawable slide object. A scene lists them back to front.
public enum SceneObjectLayer: Sendable, Equatable, Codable, Hashable {
    case shape(ShapeLayer)
    case text(TextLayer)
    case image(ImageLayer)
}

extension SlideObject {
    /// The drawable form of this object.
    public var sceneLayer: SceneObjectLayer {
        switch content {
        case .shape(let s):
            return .shape(ShapeLayer(shape: s.shape, fill: s.fill, strokeColor: s.strokeColor, strokeWidth: s.strokeWidth,
                                     frame: frame, opacity: opacity))
        case .text(let t):
            return .text(TextLayer(text: t.text, style: t.style, frame: frame, alignment: t.alignment,
                                   verticalAlignment: t.verticalAlignment, opacity: opacity))
        case .image(let i):
            return .image(ImageLayer(path: i.path, frame: frame, opacity: opacity, contentMode: i.contentMode))
        }
    }
}
