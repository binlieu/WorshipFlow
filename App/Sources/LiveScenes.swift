// OUT-002 / OUT-003: the single snapshot every output reads. One publish updates all outputs on the same frame (NFR-04).
import Foundation
import Domain

/// Immutable: one composed scene per screen profile for one show state, Look and prop list.
struct PublishedScenes: Sendable, Equatable {
    private var scenes: [UUID: SceneDescription]

    init(state: ShowState, clockText: String?, profiles: [ScreenProfile] = [], themes: [Theme] = Theme.builtIn,
         look: Look? = nil, props: [Prop] = []) {
        var composed: [UUID: SceneDescription] = [:]
        for profile in profiles {
            let screenLook = look?.screenLook(for: profile.id) ?? .standard
            let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID,
                                            presentationThemeID: nil, themes: themes)
            composed[profile.id] = SceneComposer.scene(for: profile.role, state: state, theme: theme, look: screenLook,
                                                       props: props, clockText: clockText)
        }
        scenes = composed
    }

    /// A screen that is not in the snapshot (for example one added a moment ago) shows black until the next publish.
    func scene(forScreen id: UUID) -> SceneDescription {
        scenes[id] ?? SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
    }
}

/// Written by the operator on the main actor, read by render threads. Render threads never see the observable model.
// @unchecked Sendable: all access to `current` goes through `lock`.
final class SceneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: PublishedScenes

    init(_ initial: PublishedScenes) { current = initial }

    func read() -> PublishedScenes { lock.lock(); defer { lock.unlock() }; return current }
    func publish(_ scenes: PublishedScenes) { lock.lock(); current = scenes; lock.unlock() }
}
