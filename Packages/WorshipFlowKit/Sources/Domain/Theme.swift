// OUT-003 / SLIDE-002: themes (PRES-06, SCRN-09). A theme owns a background and the text blocks; slides own only text.
// Foundation only. Built-in themes are derived from `SceneStyles.standard`, the single source of the default look.
import Foundation

/// Style and placement of one language's text.
public struct TextBlock: Sendable, Equatable, Codable, Hashable {
    public var style: TextStyle
    public var frame: NormalizedRect
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment

    public init(style: TextStyle, frame: NormalizedRect, alignment: TextAlignment = .center,
                verticalAlignment: VerticalAlignment = .center) {
        self.style = style
        self.frame = frame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }
}

public enum ThemeBackground: Sendable, Equatable, Codable, Hashable {
    /// The shared background video, over `Theme.mediaFallbackColor`.
    case media
    case color(ColorRGBA)
    case image(path: String)
    /// Alpha 0, for a broadcast overlay.
    case transparent
}

public struct Theme: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var background: ThemeBackground
    public var primary: TextBlock
    /// Nil hides the second language.
    public var secondary: TextBlock?

    public init(id: UUID, name: String, background: ThemeBackground, primary: TextBlock, secondary: TextBlock?) {
        self.id = id
        self.name = name
        self.background = background
        self.primary = primary
        self.secondary = secondary
    }

    /// Colour under the background video (and behind it while no video is loaded).
    public static let mediaFallbackColor = SceneStyles.standard.audienceBackground

    // Fixed identifiers so stored references survive relaunches.
    public static let fullScreenID = UUID(uuid: (0x57, 0x46, 0x54, 0x48, 0x45, 0x4D, 0x45, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    public static let lowerThirdID = UUID(uuid: (0x57, 0x46, 0x54, 0x48, 0x45, 0x4D, 0x45, 0x02, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02))

    /// Built from role styles; also used by the legacy `SceneComposer` entry point that takes custom `SceneStyles`.
    static func makeFullScreen(styles s: SceneStyles) -> Theme {
        Theme(id: fullScreenID, name: "Full screen", background: .media,
              primary: TextBlock(style: s.audiencePrimary, frame: s.audiencePrimaryFrame, alignment: .center, verticalAlignment: .bottom),
              secondary: TextBlock(style: s.audienceSecondary, frame: s.audienceSecondaryFrame, alignment: .center, verticalAlignment: .top))
    }

    static func makeLowerThird(styles s: SceneStyles) -> Theme {
        Theme(id: lowerThirdID, name: "Lower third", background: .transparent,
              primary: TextBlock(style: s.broadcastPrimary, frame: s.broadcastPrimaryFrame, alignment: .center, verticalAlignment: .bottom),
              secondary: TextBlock(style: s.broadcastSecondary, frame: s.broadcastSecondaryFrame, alignment: .center, verticalAlignment: .top))
    }

    public static let fullScreen = makeFullScreen(styles: .standard)
    public static let lowerThird = makeLowerThird(styles: .standard)
    public static let builtIn: [Theme] = [fullScreen, lowerThird]
}

public enum ThemeResolver {
    /// The screen's Look theme, else (audience only) the presentation's theme, else the role default.
    /// An id that is not in `themes` is skipped. The stage layout ignores themes, so it gets full screen here.
    public static func theme(for role: ScreenRole, lookThemeID: UUID?, presentationThemeID: UUID?, themes: [Theme]) -> Theme {
        func find(_ id: UUID?) -> Theme? { id.flatMap { id in themes.first { $0.id == id } } }
        if let t = find(lookThemeID) { return t }
        switch role {
        case .audience:
            return find(presentationThemeID) ?? .fullScreen
        case .broadcast:
            return .lowerThird
        case .stage:
            return .fullScreen
        }
    }
}
