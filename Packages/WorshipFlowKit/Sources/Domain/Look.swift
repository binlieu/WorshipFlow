// OUT-003: Looks (SCRN-08) and props (MEDIA-08). Foundation only.
import Foundation

public enum LayerKind: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case background, slide, props
}

/// What one screen shows under a Look.
public struct ScreenLook: Sendable, Equatable, Codable, Hashable {
    /// Nil: use the presentation's theme or the role default.
    public var themeID: UUID?
    public var visibleLayers: Set<LayerKind>

    public init(themeID: UUID? = nil, visibleLayers: Set<LayerKind> = Set(LayerKind.allCases)) {
        self.themeID = themeID
        self.visibleLayers = visibleLayers
    }

    public static let standard = ScreenLook(themeID: nil, visibleLayers: Set(LayerKind.allCases))
}

/// A named set of per-screen settings, keyed by screen profile id. Switching Look changes every screen at once.
public struct Look: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var screens: [UUID: ScreenLook]

    public init(id: UUID, name: String, screens: [UUID: ScreenLook] = [:]) {
        self.id = id
        self.name = name
        self.screens = screens
    }

    /// A screen the Look does not mention shows everything.
    public func screenLook(for screenID: UUID) -> ScreenLook { screens[screenID] ?? .standard }
}

/// An image that stays above the slide across slide changes and Clear, until switched off or Stop.
/// UI-005b: what a prop draws. A picture is the original kind; a text prop (a service title strap, a speaker name) draws words.
public enum PropKind: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case image, text
}

/// UI-005b: where on the picture a text prop sits: a 3 by 3 grid of anchors. The anchor gives the box and how the words are
/// aligned in it, so a strap at the bottom left starts at the left edge and a speaker name at the top right ends at the right edge.
public enum PropAnchor: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight

    public var horizontal: TextAlignment {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: .leading
        case .topCenter, .center, .bottomCenter: .center
        case .topRight, .middleRight, .bottomRight: .trailing
        }
    }
    public var vertical: VerticalAlignment {
        switch self {
        case .topLeft, .topCenter, .topRight: .top
        case .middleLeft, .center, .middleRight: .center
        case .bottomLeft, .bottomCenter, .bottomRight: .bottom
        }
    }
    /// The box the words are laid out in: 60 % wide, 14 % high, 4 % in from the edges.
    public var frame: NormalizedRect {
        let width = 0.6, height = 0.14, margin = 0.04
        let x: Double
        switch horizontal {
        case .leading: x = margin
        case .center: x = (1 - width) / 2
        case .trailing: x = 1 - margin - width
        }
        let y: Double
        switch vertical {
        case .top: y = margin
        case .center: y = (1 - height) / 2
        case .bottom: y = 1 - margin - height
        }
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }
    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top centre"
        case .topRight: "Top right"
        case .middleLeft: "Middle left"
        case .center: "Centre"
        case .middleRight: "Middle right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom centre"
        case .bottomRight: "Bottom right"
        }
    }
}

/// UI-005b: the words of a text prop and how they are drawn. They go through the same text path as lyrics (a `TextLayer`).
public struct TextPropSpec: Sendable, Equatable, Codable, Hashable {
    public static let fontSizes: ClosedRange<Double> = 12...200

    public var text: String
    /// In points on a 1080-line picture, like the theme's lyric sizes (the compositor scales it to the output).
    public var fontSize: Double
    /// "#RRGGBB".
    public var colorHex: String
    public var anchor: PropAnchor

    public init(text: String, fontSize: Double = 48, colorHex: String = "#FFFFFF", anchor: PropAnchor = .bottomLeft) {
        self.text = text
        self.fontSize = fontSize.isFinite ? min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, fontSize)) : 48
        self.colorHex = colorHex
        self.anchor = anchor
    }

    /// White when the text is not a six-digit colour.
    public var color: ColorRGBA {
        let hex = colorHex.hasPrefix("#") ? String(colorHex.dropFirst()) : colorHex
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return .white }
        return ColorRGBA(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

public struct Prop: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var imagePath: String
    public var frame: NormalizedRect
    public var opacity: Double
    public var isOn: Bool
    /// UI-005b: the roles this prop may appear on. A prop never appears on a role it is not targeted to, whatever the Look says.
    /// Props made before v12 have audience and broadcast, which is where they were drawn: nothing disappears, and nothing new
    /// appears on a stage screen.
    public static let defaultTargets: Set<ScreenRole> = [.audience, .broadcast]
    public var targets: Set<ScreenRole>
    public var kind: PropKind
    /// Set for a text prop.
    public var text: TextPropSpec?

    public init(id: UUID = UUID(), name: String, imagePath: String, frame: NormalizedRect, opacity: Double = 1, isOn: Bool = true,
                targets: Set<ScreenRole> = Prop.defaultTargets, kind: PropKind = .image, text: TextPropSpec? = nil) {
        self.id = id
        self.name = name
        self.imagePath = imagePath
        self.frame = frame
        self.opacity = opacity
        self.isOn = isOn
        self.targets = targets
        self.kind = kind
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case id, name, imagePath, frame, opacity, isOn, targets, kind, text }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  imagePath: try c.decode(String.self, forKey: .imagePath), frame: try c.decode(NormalizedRect.self, forKey: .frame),
                  opacity: try c.decode(Double.self, forKey: .opacity), isOn: try c.decode(Bool.self, forKey: .isOn),
                  targets: try c.decodeIfPresent(Set<ScreenRole>.self, forKey: .targets) ?? Prop.defaultTargets,
                  kind: try c.decodeIfPresent(PropKind.self, forKey: .kind) ?? .image,
                  text: try c.decodeIfPresent(TextPropSpec.self, forKey: .text))
    }

    /// A picture prop's layer (a text prop has no picture).
    public var imageLayer: ImageLayer { ImageLayer(path: imagePath, frame: frame, opacity: opacity, contentMode: .fit) }

    /// A text prop's layer: the same `TextLayer` the slides' words use, so it is drawn by the same text path (fonts, Vietnamese
    /// marks, shadow). Nil for a picture prop or a text prop with no words.
    public var textLayer: TextLayer? {
        guard kind == .text, let spec = text, !spec.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: spec.fontSize, color: spec.color,
                              shadow: TextShadow(offsetX: 0, offsetY: 2, blur: 6))
        return TextLayer(text: spec.text, style: style, frame: spec.anchor.frame, alignment: spec.anchor.horizontal,
                         verticalAlignment: spec.anchor.vertical, opacity: opacity)
    }
}
