// OUT-001: scene description handed to the compositor. Foundation only.
import Foundation

/// Non-premultiplied colour, components clamped to 0...1.
public struct ColorRGBA: Sendable, Equatable, Codable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ v: Double) -> Double { v.isNaN ? 0 : min(1, max(0, v)) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    public static let white = ColorRGBA(red: 1, green: 1, blue: 1)
    public static let black = ColorRGBA(red: 0, green: 0, blue: 0)
    public static let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Rectangle in 0...1 coordinates with a top-left origin.
public struct NormalizedRect: Sendable, Equatable, Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public struct PixelRect: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// Integer pixel rectangle for a frame of the given size (edges rounded to the nearest pixel).
    public func pixelRect(width frameWidth: Int, height frameHeight: Int) -> PixelRect {
        let left = (x * Double(frameWidth)).rounded()
        let top = (y * Double(frameHeight)).rounded()
        let right = ((x + width) * Double(frameWidth)).rounded()
        let bottom = ((y + height) * Double(frameHeight)).rounded()
        return PixelRect(x: Int(left), y: Int(top), width: Int(right - left), height: Int(bottom - top))
    }
}

public enum TextAlignment: String, Sendable, Equatable, Codable, Hashable {
    case leading, center, trailing
}

public enum VerticalAlignment: String, Sendable, Equatable, Codable, Hashable {
    case top, center, bottom
}

/// A drop shadow behind text (MEDIA-07). Offsets and blur are in points at a 1080-line reference height.
/// A positive `offsetX` moves the shadow right and a positive `offsetY` moves it down the screen.
public struct TextShadow: Sendable, Equatable, Codable, Hashable {
    public var color: ColorRGBA
    public var offsetX: Double
    public var offsetY: Double
    public var blur: Double

    public init(color: ColorRGBA = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.6),
                offsetX: Double = 0, offsetY: Double = 0, blur: Double = 0) {
        self.color = color
        self.offsetX = offsetX.isFinite ? offsetX : 0
        self.offsetY = offsetY.isFinite ? offsetY : 0
        self.blur = blur.isFinite ? max(0, blur) : 0
    }
}

/// Font size, outline width and shadow offsets are in points at a 1080-line reference height.
public struct TextStyle: Sendable, Equatable, Codable, Hashable {
    public var fontName: String
    public var fontSize: Double
    public var color: ColorRGBA
    public var outlineWidth: Double
    public var outlineColor: ColorRGBA
    /// Nil: no shadow. Absent from content saved before shadows existed.
    public var shadow: TextShadow?
    /// UI-005h: the CSS weight, 100 (thin) to 900 (black). Nil is the font's regular face, as every style saved before this field drew it.
    /// A font with a weight axis (Inter) is set to the weight; any other font takes the nearest face of its family.
    public var weight: Int?
    /// UI-005h: space added after every letter, in em (0.08 = 8 % of the font size). Nil: none.
    public var letterSpacing: Double?
    /// UI-005h: the distance between lines as a multiple of the font size (1.2 = 120 %). Nil: the font's own line height. A style with a
    /// line height also places its text block by its line boxes (like a web page) instead of by the padded bitmap; see `Compositor.layoutReport`.
    public var lineHeight: Double?
    /// UI-005h: the optical-size axis of a variable font (Inter: 14 to 32), in points. Nil: set to suit the size when a weight is set (large
    /// text gets the tighter display cut). The design's pictures show Inter's text cut (14) at every size.
    public var opticalSize: Double?
    /// UI-005h: OpenType feature tags switched on (`["cv11"]` is Inter's single-storey a). Nil: the font's defaults.
    public var fontFeatures: [String]?

    public init(fontName: String, fontSize: Double, color: ColorRGBA,
                outlineWidth: Double = 0, outlineColor: ColorRGBA = .black, shadow: TextShadow? = nil,
                weight: Int? = nil, letterSpacing: Double? = nil, lineHeight: Double? = nil,
                opticalSize: Double? = nil, fontFeatures: [String]? = nil) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
        self.shadow = shadow
        self.weight = weight.map { min(900, max(100, $0)) }
        self.letterSpacing = letterSpacing.flatMap { $0.isFinite ? $0 : nil }
        self.lineHeight = lineHeight.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.opticalSize = opticalSize.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.fontFeatures = fontFeatures
    }
}

public struct TextLayer: Sendable, Equatable, Codable, Hashable {
    public var text: String
    public var style: TextStyle
    public var frame: NormalizedRect
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    /// 0...1, applied to the whole text (outline and shadow included). Lyric text is always 1; text boxes use it.
    public var opacity: Double
    /// UI-005h: the text sits on the scene's plate. Its frame is not used: the compositor stacks the plated layers, in order, inside the
    /// plate's padding (and beside its bar), and sizes the plate to them.
    public var inPlate: Bool

    public init(text: String, style: TextStyle, frame: NormalizedRect,
                alignment: TextAlignment = .center, verticalAlignment: VerticalAlignment = .center,
                opacity: Double = 1, inPlate: Bool = false) {
        self.text = text
        self.style = style
        self.frame = frame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
        self.inPlate = inPlate
    }

    private enum CodingKeys: String, CodingKey { case text, style, frame, alignment, verticalAlignment, opacity, inPlate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try c.decode(String.self, forKey: .text), style: try c.decode(TextStyle.self, forKey: .style),
                  frame: try c.decode(NormalizedRect.self, forKey: .frame),
                  alignment: try c.decode(TextAlignment.self, forKey: .alignment),
                  verticalAlignment: try c.decode(VerticalAlignment.self, forKey: .verticalAlignment),
                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
                  inPlate: try c.decodeIfPresent(Bool.self, forKey: .inPlate) ?? false)
    }

    /// `inPlate` is written only when it is set, so a layer that is not on a plate encodes as it did before.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(style, forKey: .style)
        try c.encode(frame, forKey: .frame)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(verticalAlignment, forKey: .verticalAlignment)
        try c.encode(opacity, forKey: .opacity)
        if inPlate { try c.encode(true, forKey: .inPlate) }
    }
}

/// Which media layer a frame belongs to.
public enum MediaLayerSlot: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case background, foreground
}

/// A media-bin item a scene asks its output to draw (MEDIA-002). The output resolves the id to a frame.
public enum SceneMedia: Sendable, Equatable, Codable, Hashable {
    case video(UUID)
    case image(UUID)

    public var assetID: UUID {
        switch self {
        case .video(let id), .image(let id): return id
        }
    }
}

public struct SceneDescription: Sendable, Equatable, Codable, Hashable {
    public var backgroundColor: ColorRGBA
    /// When true and a video frame is supplied, it is drawn aspect-fill over the background colour.
    public var showsVideo: Bool
    public var textLayers: [TextLayer]
    /// Drawn after the video and before the text (OUT-003).
    public var backgroundImage: ImageLayer?
    /// Drawn after the text (OUT-003).
    public var overlayImages: [ImageLayer]
    /// Media chosen as the background, drawn aspect-fill after the background colour (MEDIA-02).
    public var backgroundMedia: SceneMedia?
    /// Media playing over the slide, drawn aspect-fit over black before the text (MEDIA-03).
    public var foregroundMedia: SceneMedia?
    /// Slide objects (SLIDE-001a), back to front. Drawn after the foreground media and before the lyric text.
    public var objectLayers: [SceneObjectLayer]
    /// UI-005h: a gradient drawn over the background colour and under everything else, in the whole frame.
    public var backgroundGradient: GradientBackground?
    /// UI-005h: a plate (and accent bar) drawn after the slide objects and before the text; the text layers marked `inPlate` sit on it.
    public var plate: TextPlate?

    public init(backgroundColor: ColorRGBA, showsVideo: Bool = false, textLayers: [TextLayer],
                backgroundImage: ImageLayer? = nil, overlayImages: [ImageLayer] = [],
                backgroundMedia: SceneMedia? = nil, foregroundMedia: SceneMedia? = nil,
                objectLayers: [SceneObjectLayer] = [], backgroundGradient: GradientBackground? = nil, plate: TextPlate? = nil) {
        self.backgroundColor = backgroundColor
        self.showsVideo = showsVideo
        self.textLayers = textLayers
        self.backgroundImage = backgroundImage
        self.overlayImages = overlayImages
        self.backgroundMedia = backgroundMedia
        self.foregroundMedia = foregroundMedia
        self.objectLayers = objectLayers
        self.backgroundGradient = backgroundGradient
        self.plate = plate
    }

    private enum CodingKeys: String, CodingKey {
        case backgroundColor, showsVideo, textLayers, backgroundImage, overlayImages, backgroundMedia, foregroundMedia, objectLayers
        case backgroundGradient, plate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(backgroundColor: try c.decode(ColorRGBA.self, forKey: .backgroundColor),
                  showsVideo: try c.decode(Bool.self, forKey: .showsVideo),
                  textLayers: try c.decode([TextLayer].self, forKey: .textLayers),
                  backgroundImage: try c.decodeIfPresent(ImageLayer.self, forKey: .backgroundImage),
                  overlayImages: try c.decode([ImageLayer].self, forKey: .overlayImages),
                  backgroundMedia: try c.decodeIfPresent(SceneMedia.self, forKey: .backgroundMedia),
                  foregroundMedia: try c.decodeIfPresent(SceneMedia.self, forKey: .foregroundMedia),
                  objectLayers: try c.decodeIfPresent([SceneObjectLayer].self, forKey: .objectLayers) ?? [],
                  backgroundGradient: try c.decodeIfPresent(GradientBackground.self, forKey: .backgroundGradient),
                  plate: try c.decodeIfPresent(TextPlate.self, forKey: .plate))
    }
}

public enum ScreenRole: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case audience, stage, broadcast
}
