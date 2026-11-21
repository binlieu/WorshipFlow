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
public struct Prop: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var imagePath: String
    public var frame: NormalizedRect
    public var opacity: Double
    public var isOn: Bool

    public init(id: UUID = UUID(), name: String, imagePath: String, frame: NormalizedRect, opacity: Double = 1, isOn: Bool = true) {
        self.id = id
        self.name = name
        self.imagePath = imagePath
        self.frame = frame
        self.opacity = opacity
        self.isOn = isOn
    }

    public var imageLayer: ImageLayer { ImageLayer(path: imagePath, frame: frame, opacity: opacity, contentMode: .fit) }
}
