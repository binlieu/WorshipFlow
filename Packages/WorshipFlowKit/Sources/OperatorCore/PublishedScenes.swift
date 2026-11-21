// APP-001 / OUT-002 / OUT-003: the single snapshot every output reads, moved here from the app so the rule that
// decides which theme reaches which screen can be tested. One publish updates all outputs on the same frame (NFR-04).
import Foundation
import Domain

/// Immutable: one composed scene per screen profile for one show state, Look, theme choice and prop list.
public struct PublishedScenes: Sendable, Equatable {
    private var scenes: [UUID: SceneDescription]

    /// - Parameter presentationThemeID: the theme of the presentation that is live (PRES-06). `ThemeResolver`
    ///   applies it to audience screens only, after the screen's own Look theme.
    public init(state: ShowState, clockText: String?, profiles: [ScreenProfile] = [], themes: [Theme] = Theme.builtIn,
                look: Look? = nil, props: [Prop] = [], presentationThemeID: UUID? = nil) {
        var composed: [UUID: SceneDescription] = [:]
        for profile in profiles {
            let screenLook = look?.screenLook(for: profile.id) ?? .standard
            let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID,
                                            presentationThemeID: presentationThemeID, themes: themes)
            composed[profile.id] = SceneComposer.scene(for: profile.role, state: state, theme: theme, look: screenLook,
                                                       props: props, clockText: clockText)
        }
        scenes = composed
    }

    /// A screen that is not in the snapshot (for example one added a moment ago) shows black until the next publish.
    public func scene(forScreen id: UUID) -> SceneDescription {
        scenes[id] ?? SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
    }
}
