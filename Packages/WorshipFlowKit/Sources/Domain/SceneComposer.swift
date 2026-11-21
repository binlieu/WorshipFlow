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
        case .stage: return addingProps(to: stage(state, .standard, clockText), role: .stage, state: state, look: look, props: props)
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
        // Blackout (UI-001) is the same picture: black, or transparent on broadcast, whatever is live.
        guard !state.isStopped, !state.isBlackedOut else {
            return SceneDescription(backgroundColor: isBroadcast ? .clear : .black, showsVideo: false, textLayers: [])
        }
        var scene = SceneDescription(backgroundColor: isBroadcast ? .clear : .black, showsVideo: false, textLayers: [])
        // MEDIA-010: Clear background hides every kind of background; the words and props stay.
        if look.visibleLayers.contains(.background), !state.isBackgroundCleared {
            // A live override from the bin beats the live slide's own background; either replaces the theme's own.
            let override = media?.background?.selection.sceneMedia
            let own = state.liveSlideAtPlace?.background?.sceneMedia
            switch theme.background {
            case .media:
                scene.backgroundColor = Theme.mediaFallbackColor
                scene.showsVideo = true
                // A chosen background replaces the theme's shared loop; a still must not leave the loop showing.
                if let chosen = override ?? own {
                    scene.backgroundMedia = chosen
                    if case .image = chosen { scene.showsVideo = false }
                }
            case .color(let c):
                scene.backgroundColor = c
                scene.backgroundMedia = override ?? own
            case .image(let path):
                // A background chosen in the bin does not show on a picture theme (the theme's picture is an explicit choice);
                // a slide's own background is an explicit choice too, and beats it.
                if let own {
                    scene.backgroundMedia = own
                    scene.backgroundColor = .black
                } else {
                    scene.backgroundImage = ImageLayer(path: path, frame: .full, opacity: 1, contentMode: .fill)
                    scene.backgroundColor = .black
                }
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
            // Slide objects (SLIDE-001a) follow the slide layer. A keyed (transparent) screen leaves them out, so
            // full-frame artwork cannot cover a lower third.
            if !isBroadcast || theme.background != .transparent {
                scene.objectLayers = slide.objects.map(\.sceneLayer)
            }
        }
        return addingProps(to: scene, role: isBroadcast ? .broadcast : .audience, state: state, look: look, props: props)
    }

    /// UI-005b: adds the props that are on, targeted to `role`, and shown by the screen's Look (its props layer). A picture prop
    /// becomes an overlay image, a text prop a text layer after the slide's own words (the same `TextLayer` the words use). A prop
    /// never reaches a role it is not targeted to, and none is drawn while stopped or blacked out.
    public static func addingProps(to scene: SceneDescription, role: ScreenRole, state: ShowState, look: ScreenLook, props: [Prop]) -> SceneDescription {
        guard !state.isStopped, !state.isBlackedOut, look.visibleLayers.contains(.props) else { return scene }
        let shown = props.filter { $0.isOn && $0.targets.contains(role) }
        var result = scene
        result.overlayImages += shown.filter { $0.kind == .image }.map(\.imageLayer)
        result.textLayers += shown.compactMap(\.textLayer)
        return result
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
        if state.isBlackedOut { layers.append(StageComposer.blackoutLayer(warning: StageLayout.standard.warningColor)) }
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
