// APP-001 / OUT-002 / OUT-003: the single snapshot every output reads, moved here from the app so the rule that
// decides which theme reaches which screen can be tested. One publish updates all outputs on the same frame (NFR-04).
import Foundation
import Domain

/// Immutable: one composed scene per screen profile for one show state, Look, theme choice and prop list.
public struct PublishedScenes: Sendable, Equatable {
    private var scenes: [UUID: SceneDescription]

    /// - Parameter presentationThemeID: the theme of the presentation that is live (PRES-06). `ThemeResolver`
    ///   applies it to audience screens only, after the screen's own Look theme.
    /// - Parameter stageScenes: ready-made scenes (from `StageModel`) for stage screens, which ignore themes and Looks.
    ///   A stage screen without an entry falls back to the built-in stage scene.
    /// - Parameter media: the chosen background and the clip playing in the foreground (MEDIA-001). Audience and
    ///   broadcast screens follow the rules in `SceneComposer`; stage screens never show media.
    public init(state: ShowState, clockText: String?, profiles: [ScreenProfile] = [], themes: [Theme] = Theme.builtIn,
                look: Look? = nil, props: [Prop] = [], presentationThemeID: UUID? = nil,
                stageScenes: [UUID: SceneDescription] = [:], media: MediaLayers? = nil) {
        var composed: [UUID: SceneDescription] = [:]
        for profile in profiles {
            let screenLook = look?.screenLook(for: profile.id, in: profiles) ?? .standard
            if profile.role == .stage, let stage = stageScenes[profile.id] {
                // UI-005b: props targeted to the stage (and shown by its Look) go on top of the stage layout's own scene.
                composed[profile.id] = SceneComposer.addingProps(to: stage, role: .stage, state: state, look: screenLook, props: props)
                continue
            }
            let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID,
                                            presentationThemeID: presentationThemeID, themes: themes)
            composed[profile.id] = SceneComposer.scene(for: profile.role, state: state, theme: theme, look: screenLook,
                                                       props: props, media: media, clockText: clockText)
        }
        scenes = composed
    }

    /// A screen that is not in the snapshot (for example one added a moment ago) shows black until the next publish.
    public func scene(forScreen id: UUID) -> SceneDescription {
        scenes[id] ?? SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
    }
}
