// OUT-002: one live state, a different composition per screen role. Foundation only.
import Foundation

/// Default look of each role. Kept in one place so themes can replace it later (SLIDE-002).
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
    public static func scene(for role: ScreenRole, state: ShowState, clockText: String? = nil,
                             styles: SceneStyles = .standard) -> SceneDescription {
        switch role {
        case .audience: return audience(state, styles)
        case .stage: return stage(state, styles, clockText)
        case .broadcast: return broadcast(state, styles)
        }
    }

    private static func visible(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func audience(_ state: ShowState, _ s: SceneStyles) -> SceneDescription {
        // A stopped show is plain black with no background video; a cleared one keeps its background.
        guard !state.isStopped else { return SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: []) }
        var layers: [TextLayer] = []
        if let slide = state.liveSlide {
            if let p = visible(slide.primary) {
                layers.append(TextLayer(text: p, style: s.audiencePrimary, frame: s.audiencePrimaryFrame,
                                        alignment: .center, verticalAlignment: .bottom))
            }
            if let t = visible(slide.secondary) {
                layers.append(TextLayer(text: t, style: s.audienceSecondary, frame: s.audienceSecondaryFrame,
                                        alignment: .center, verticalAlignment: .top))
            }
        }
        return SceneDescription(backgroundColor: s.audienceBackground, showsVideo: true, textLayers: layers)
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
