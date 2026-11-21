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

/// Font size and outline width are in points at a 1080-line reference height.
public struct TextStyle: Sendable, Equatable, Codable, Hashable {
    public var fontName: String
    public var fontSize: Double
    public var color: ColorRGBA
    public var outlineWidth: Double
    public var outlineColor: ColorRGBA

    public init(fontName: String, fontSize: Double, color: ColorRGBA,
                outlineWidth: Double = 0, outlineColor: ColorRGBA = .black) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
    }
}

public struct TextLayer: Sendable, Equatable, Codable, Hashable {
    public var text: String
    public var style: TextStyle
    public var frame: NormalizedRect
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment

    public init(text: String, style: TextStyle, frame: NormalizedRect,
                alignment: TextAlignment = .center, verticalAlignment: VerticalAlignment = .center) {
        self.text = text
        self.style = style
        self.frame = frame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }
}

public struct SceneDescription: Sendable, Equatable, Codable, Hashable {
    public var backgroundColor: ColorRGBA
    /// When true and a video frame is supplied, it is drawn aspect-fill over the background colour.
    public var showsVideo: Bool
    public var textLayers: [TextLayer]

    public init(backgroundColor: ColorRGBA, showsVideo: Bool = false, textLayers: [TextLayer]) {
        self.backgroundColor = backgroundColor
        self.showsVideo = showsVideo
        self.textLayers = textLayers
    }
}

public enum ScreenRole: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case audience, stage, broadcast
}
