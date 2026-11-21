// OUT-002: the single snapshot every output reads. One publish updates all outputs on the same frame (NFR-04).
import Foundation
import Domain

/// Immutable: the three composed scenes for one show state.
struct PublishedScenes: Sendable, Equatable {
    var audience: SceneDescription
    var stage: SceneDescription
    var broadcast: SceneDescription

    init(state: ShowState, clockText: String?) {
        audience = SceneComposer.scene(for: .audience, state: state, clockText: clockText)
        stage = SceneComposer.scene(for: .stage, state: state, clockText: clockText)
        broadcast = SceneComposer.scene(for: .broadcast, state: state, clockText: clockText)
    }

    func scene(for role: ScreenRole) -> SceneDescription {
        switch role {
        case .audience: audience
        case .stage: stage
        case .broadcast: broadcast
        }
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
