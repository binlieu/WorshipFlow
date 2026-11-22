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

    /// FIX-J: a stored colour is clamped like a constructed one.
    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(red: try c.decode(Double.self, forKey: .red), green: try c.decode(Double.self, forKey: .green),
                  blue: try c.decode(Double.self, forKey: .blue), alpha: try c.decode(Double.self, forKey: .alpha))
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

    /// FIX-J: a stored frame is kept within a hundred screens of the origin: a hostile number cannot overflow a pixel rectangle.
    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func bounded(_ v: Double) -> Double { v.isFinite ? min(100, max(-100, v)) : 0 }
        self.init(x: bounded(try c.decode(Double.self, forKey: .x)), y: bounded(try c.decode(Double.self, forKey: .y)),
                  width: bounded(try c.decode(Double.self, forKey: .width)), height: bounded(try c.decode(Double.self, forKey: .height)))
    }

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
        // FIX-T: total. A frame with an absurd or non-finite value (a hand-edited file) is held to a bound that still leaves `width * height * 4`
        // room in an Int, instead of trapping in the conversion.
        func pixels(_ v: Double) -> Int { Int(saturating: max(-1_073_741_824, min(1_073_741_824, v.isNaN ? 0 : v))) }
        let left = (x * Double(frameWidth)).rounded()
        let top = (y * Double(frameHeight)).rounded()
        let right = ((x + width) * Double(frameWidth)).rounded()
        let bottom = ((y + height) * Double(frameHeight)).rounded()
        let l = pixels(left), t = pixels(top)
        return PixelRect(x: l, y: t, width: pixels(right) - l, height: pixels(bottom) - t)
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
        self.offsetX = offsetX.isFinite ? min(2000, max(-2000, offsetX)) : 0
        self.offsetY = offsetY.isFinite ? min(2000, max(-2000, offsetY)) : 0
        self.blur = blur.isFinite ? min(1000, max(0, blur)) : 0
    }

    /// FIX-J: a stored shadow goes through the initialiser's limits.
    private enum CodingKeys: String, CodingKey { case color, offsetX, offsetY, blur }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(color: try c.decode(ColorRGBA.self, forKey: .color), offsetX: try c.decode(Double.self, forKey: .offsetX),
                  offsetY: try c.decode(Double.self, forKey: .offsetY), blur: try c.decode(Double.self, forKey: .blur))
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
        // FIX-J: sane ranges. A value that cannot be valid (not a number, zero or negative line height or optical size) is dropped.
        self.letterSpacing = letterSpacing.flatMap { $0.isFinite ? min(2, max(-0.5, $0)) : nil }
        self.lineHeight = lineHeight.flatMap { $0.isFinite && $0 > 0 ? min(4, max(0.5, $0)) : nil }
        self.opticalSize = opticalSize.flatMap { $0.isFinite && $0 > 0 ? min(144, max(6, $0)) : nil }
        self.fontFeatures = fontFeatures
    }

    private enum CodingKeys: String, CodingKey {
        case fontName, fontSize, color, outlineWidth, outlineColor, shadow, weight, letterSpacing, lineHeight, opticalSize, fontFeatures
    }

    /// FIX-J: a stored style goes through the initialiser, so a hostile value is clamped as a constructed one is.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fontName: try c.decode(String.self, forKey: .fontName), fontSize: try c.decode(Double.self, forKey: .fontSize),
                  color: try c.decode(ColorRGBA.self, forKey: .color), outlineWidth: try c.decode(Double.self, forKey: .outlineWidth),
                  outlineColor: try c.decode(ColorRGBA.self, forKey: .outlineColor), shadow: try c.decodeIfPresent(TextShadow.self, forKey: .shadow),
                  weight: try c.decodeIfPresent(Int.self, forKey: .weight), letterSpacing: try c.decodeIfPresent(Double.self, forKey: .letterSpacing),
                  lineHeight: try c.decodeIfPresent(Double.self, forKey: .lineHeight), opticalSize: try c.decodeIfPresent(Double.self, forKey: .opticalSize),
                  fontFeatures: try c.decodeIfPresent([String].self, forKey: .fontFeatures))
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
    /// FIX-J: set, the compositor shrinks this layer (with the other layers that have it) until the words fit their block; this is the smallest
    /// size it goes to for the first such layer, in points at 1080 lines. Nil: drawn at its size, as always.
    public var fitFloor: Double?
    /// FIX-J: the text changes every second (the clock, a timer, a countdown). The compositor keeps such bitmaps in a small cache of their own,
    /// so they cannot push the lyrics out of the main one.
    public var ticks: Bool

    public init(text: String, style: TextStyle, frame: NormalizedRect,
                alignment: TextAlignment = .center, verticalAlignment: VerticalAlignment = .center,
                opacity: Double = 1, inPlate: Bool = false, fitFloor: Double? = nil, ticks: Bool = false) {
        self.text = text
        self.style = style
        self.frame = frame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
        self.inPlate = inPlate
        self.fitFloor = fitFloor.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.ticks = ticks
    }

    private enum CodingKeys: String, CodingKey { case text, style, frame, alignment, verticalAlignment, opacity, inPlate, fitFloor, ticks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try c.decode(String.self, forKey: .text), style: try c.decode(TextStyle.self, forKey: .style),
                  frame: try c.decode(NormalizedRect.self, forKey: .frame),
                  alignment: try c.decode(TextAlignment.self, forKey: .alignment),
                  verticalAlignment: try c.decode(VerticalAlignment.self, forKey: .verticalAlignment),
                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
                  inPlate: try c.decodeIfPresent(Bool.self, forKey: .inPlate) ?? false,
                  fitFloor: try c.decodeIfPresent(Double.self, forKey: .fitFloor),
                  ticks: try c.decodeIfPresent(Bool.self, forKey: .ticks) ?? false)
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
        try c.encodeIfPresent(fitFloor, forKey: .fitFloor)
        if ticks { try c.encode(true, forKey: .ticks) }
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
