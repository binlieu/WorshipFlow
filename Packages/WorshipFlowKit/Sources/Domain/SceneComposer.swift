// OUT-002 / OUT-003: one live state, a different composition per screen. Foundation only.
import Foundation

/// Default look of each role and the single source of the built-in themes (`Theme.fullScreen`, `Theme.lowerThird`).
public struct SceneStyles: Sendable, Equatable {
    public var fontName = "Helvetica Neue"

    // Audience
    public var audienceBackground = ColorRGBA(red: 0.04, green: 0.06, blue: 0.14)
    public var audiencePrimary = TextStyle(fontName: "Helvetica Neue", fontSize: 84, color: .white,
                                           outlineWidth: 4, outlineColor: .black)
    public var audienceSecondary = TextStyle(fontName: "Helvetica Neue", fontSize: 64,
                                             color: ColorRGBA(red: 1, green: 0.86, blue: 0.4),
                                             outlineWidth: 3, outlineColor: .black)
    public var audiencePrimaryFrame = NormalizedRect(x: 0.06, y: 0.18, width: 0.88, height: 0.32)
    public var audienceSecondaryFrame = NormalizedRect(x: 0.06, y: 0.52, width: 0.88, height: 0.28)

    // Stage
    public var stageBackground = ColorRGBA(red: 0.02, green: 0.02, blue: 0.02)
    public var stageCurrent = TextStyle(fontName: "Helvetica Neue", fontSize: 96, color: .white)
    public var stageNext = TextStyle(fontName: "Helvetica Neue", fontSize: 56,
                                     color: ColorRGBA(red: 0.35, green: 0.85, blue: 0.55))
    public var stageClock = TextStyle(fontName: "Helvetica Neue", fontSize: 44,
                                      color: ColorRGBA(red: 0.8, green: 0.8, blue: 0.8))
    public var stageCurrentFrame = NormalizedRect(x: 0.04, y: 0.08, width: 0.92, height: 0.50)
    public var stageNextFrame = NormalizedRect(x: 0.04, y: 0.64, width: 0.92, height: 0.30)
    public var stageClockFrame = NormalizedRect(x: 0.74, y: 0.01, width: 0.22, height: 0.07)

    // Broadcast lower third (transparent background)
    public var broadcastPrimary = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white,
                                            outlineWidth: 3, outlineColor: .black)
    public var broadcastSecondary = TextStyle(fontName: "Helvetica Neue", fontSize: 44,
                                              color: ColorRGBA(red: 1, green: 0.86, blue: 0.4),
                                              outlineWidth: 2, outlineColor: .black)
    public var broadcastPrimaryFrame = NormalizedRect(x: 0.08, y: 0.70, width: 0.84, height: 0.14)
    public var broadcastSecondaryFrame = NormalizedRect(x: 0.08, y: 0.85, width: 0.84, height: 0.11)

    public init() {}

    public static let standard = SceneStyles()
}

public enum SceneComposer {
    /// The earlier entry point: the role's default theme from `styles`, the standard Look, no props.
    public static func scene(for role: ScreenRole, state: ShowState, clockText: String? = nil,
                             styles: SceneStyles = .standard) -> SceneDescription {
        switch role {
        case .audience:
            return themed(state, theme: Theme.makeFullScreen(styles: styles), look: .standard, props: [], media: nil, isBroadcast: false)
        case .stage:
            return stage(state, styles, clockText)
        case .broadcast:
            return themed(state, theme: Theme.makeLowerThird(styles: styles), look: .standard, props: [], media: nil, isBroadcast: true)
        }
    }

    /// Composes one screen. The stage layout ignores the theme, Look and props. Props are not drawn while stopped.
    /// `media` (MEDIA-002) adds the chosen background and foreground media. The stage never shows media.
    public static func scene(for role: ScreenRole, state: ShowState, theme: Theme, look: ScreenLook, props: [Prop],
                             media: MediaLayers? = nil, clockText: String? = nil) -> SceneDescription {
        switch role {
        case .stage: return stage(state, .standard, clockText)
        case .audience: return themed(state, theme: theme, look: look, props: props, media: media, isBroadcast: false)
        case .broadcast: return themed(state, theme: theme, look: look, props: props, media: media, isBroadcast: true)
        }
    }

    private static func visible(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func layer(_ text: String, _ block: TextBlock) -> TextLayer {
        TextLayer(text: text, style: block.style, frame: block.frame, alignment: block.alignment,
                  verticalAlignment: block.verticalAlignment)
    }

    private static func themed(_ state: ShowState, theme: Theme, look: ScreenLook, props: [Prop], media: MediaLayers?,
                                isBroadcast: Bool) -> SceneDescription {
        // A stopped show is empty: black (audience) or transparent (broadcast), no video, no text, no props.
        guard !state.isStopped else {
            return SceneDescription(backgroundColor: isBroadcast ? .clear : .black, showsVideo: false, textLayers: [])
        }
        var scene = SceneDescription(backgroundColor: isBroadcast ? .clear : .black, showsVideo: false, textLayers: [])
        if look.visibleLayers.contains(.background) {
            switch theme.background {
            case .media:
                scene.backgroundColor = Theme.mediaFallbackColor
                scene.showsVideo = true
                // A chosen background replaces the theme's shared loop; a still must not leave the loop showing.
                if let chosen = media?.background?.selection.sceneMedia {
                    scene.backgroundMedia = chosen
                    if case .image = chosen { scene.showsVideo = false }
                }
            case .color(let c):
                scene.backgroundColor = c
            case .image(let path):
                scene.backgroundImage = ImageLayer(path: path, frame: .full, opacity: 1, contentMode: .fill)
                scene.backgroundColor = .black
            case .transparent:
                scene.backgroundColor = .clear
            }
        }
        // A foreground clip replaces the slide text, so it follows the slide layer of the Look. Props stay on top.
        let foreground = look.visibleLayers.contains(.slide) ? media?.foreground?.selection.sceneMedia : nil
        scene.foregroundMedia = foreground
        if foreground == nil, look.visibleLayers.contains(.slide), let slide = state.liveSlide {
            if let p = visible(slide.primary) { scene.textLayers.append(layer(p, theme.primary)) }
            if let block = theme.secondary, let t = visible(slide.secondary) { scene.textLayers.append(layer(t, block)) }
        }
        if look.visibleLayers.contains(.props) {
            scene.overlayImages = props.filter(\.isOn).map(\.imageLayer)
        }
        return scene
    }

    private static func stage(_ state: ShowState, _ s: SceneStyles, _ clock: String?) -> SceneDescription {
        var layers: [TextLayer] = []
        if let slide = state.liveSlide, let p = visible(slide.primary) {
            var text = p
            if let t = visible(slide.secondary) { text += "\n" + t }
            layers.append(TextLayer(text: text, style: s.stageCurrent, frame: s.stageCurrentFrame,
                                    alignment: .leading, verticalAlignment: .top))
        }
        if let next = state.nextSlide, let p = visible(next.primary) {
            layers.append(TextLayer(text: p, style: s.stageNext, frame: s.stageNextFrame,
                                    alignment: .leading, verticalAlignment: .top))
        }
        if let clock = visible(clock) {
            layers.append(TextLayer(text: clock, style: s.stageClock, frame: s.stageClockFrame,
                                    alignment: .trailing, verticalAlignment: .top))
        }
        return SceneDescription(backgroundColor: s.stageBackground, showsVideo: false, textLayers: layers)
    }

    private static func broadcast(_ state: ShowState, _ s: SceneStyles) -> SceneDescription {
        var layers: [TextLayer] = []
        if let slide = state.liveSlide {
            if let p = visible(slide.primary) {
                layers.append(TextLayer(text: p, style: s.broadcastPrimary, frame: s.broadcastPrimaryFrame,
                                        alignment: .center, verticalAlignment: .bottom))
            }
            if let t = visible(slide.secondary) {
                layers.append(TextLayer(text: t, style: s.broadcastSecondary, frame: s.broadcastSecondaryFrame,
                                        alignment: .center, verticalAlignment: .top))
            }
        }
        return SceneDescription(backgroundColor: .clear, showsVideo: false, textLayers: layers)
    }
}
