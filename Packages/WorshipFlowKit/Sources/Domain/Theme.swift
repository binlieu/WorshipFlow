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
    /// UI-005h: a radial gradient. A slide's own background or a bin choice still covers it, as for a colour.
    case gradient(GradientBackground)
}

public struct Theme: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var background: ThemeBackground
    public var primary: TextBlock
    /// Nil hides the second language.
    public var secondary: TextBlock?
    /// UI-005h: for a `.media` background, the gradient drawn under the shared loop (and left showing while no loop plays). Nil: the flat
    /// `mediaFallbackColor`, as every theme saved before this field drew it.
    public var mediaFallback: GradientBackground?
    /// UI-005h: a plate behind the text, with its accent bar. Nil: none, as before. With a plate the text blocks' frames are not used: the
    /// plated lines are stacked inside the plate, which is sized to them (their alignment, style and order still come from the blocks).
    public var plate: TextPlate?
    /// FIX-J: when on, the slide's words are shrunk, both languages by the same factor, until they fit the theme's text blocks (never below
    /// `fitFloor`). On for the built-in looks; off for the Classic themes and for every theme saved before this field, so none of them changes.
    public var fitsText: Bool

    /// FIX-J item 6: the font the built-in output looks name (the bundled Inter, which the app registers at launch).
    public static let outputFontName = OutputLooks.font

    /// FIX-J: the smallest first-language size fitting will go to, in points at 1080 lines (the design's "never below 56 px").
    public static let fitFloor = 56.0

    public init(id: UUID, name: String, background: ThemeBackground, primary: TextBlock, secondary: TextBlock?,
                mediaFallback: GradientBackground? = nil, plate: TextPlate? = nil, fitsText: Bool = false) {
        self.id = id
        self.name = name
        self.background = background
        self.primary = primary
        self.secondary = secondary
        self.mediaFallback = mediaFallback
        self.plate = plate
        self.fitsText = fitsText
    }

    private enum CodingKeys: String, CodingKey { case id, name, background, primary, secondary, mediaFallback, plate, fitsText }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  background: try c.decode(ThemeBackground.self, forKey: .background),
                  primary: try c.decode(TextBlock.self, forKey: .primary), secondary: try c.decodeIfPresent(TextBlock.self, forKey: .secondary),
                  mediaFallback: try c.decodeIfPresent(GradientBackground.self, forKey: .mediaFallback),
                  plate: try c.decodeIfPresent(TextPlate.self, forKey: .plate),
                  fitsText: try c.decodeIfPresent(Bool.self, forKey: .fitsText) ?? false)
    }

    /// `fitsText` is written only when it is on, so a theme that does not fit its text encodes as it did before.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(background, forKey: .background)
        try c.encode(primary, forKey: .primary)
        try c.encodeIfPresent(secondary, forKey: .secondary)
        try c.encodeIfPresent(mediaFallback, forKey: .mediaFallback)
        try c.encodeIfPresent(plate, forKey: .plate)
        if fitsText { try c.encode(true, forKey: .fitsText) }
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

    /// UI-005h: the design's looks (`OutputLooks`). `makeFullScreen` and `makeLowerThird` still build the earlier looks from `SceneStyles`.
    public static let fullScreen = OutputLooks.audienceTheme()
    public static let lowerThird = OutputLooks.lowerThirdTheme()
    public static let builtIn: [Theme] = [fullScreen, lowerThird]

    // UI-005h: the two built-in looks as they were before the design's looks replaced them. They are not built in: migration v13 stores them
    // in a library that already has content, as ordinary themes the church may rename, edit or delete, so it can go back.
    public static let classicFullScreenID = UUID(uuid: (0x57, 0x46, 0x54, 0x48, 0x45, 0x4D, 0x45, 0x03, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03))
    public static let classicLowerThirdID = UUID(uuid: (0x57, 0x46, 0x54, 0x48, 0x45, 0x4D, 0x45, 0x04, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04))

    public static let classicFullScreen: Theme = {
        var t = makeFullScreen(styles: .standard)
        t.id = classicFullScreenID
        t.name = "Classic full screen"
        return t
    }()

    public static let classicLowerThird: Theme = {
        var t = makeLowerThird(styles: .standard)
        t.id = classicLowerThirdID
        t.name = "Classic lower third"
        return t
    }()

    public static let classic: [Theme] = [classicFullScreen, classicLowerThird]

    /// The design's audience gradient, for a theme that chooses the Gradient background.
    public static let designGradient = OutputLooks.audienceGradient
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
