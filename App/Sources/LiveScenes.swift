// OUT-002 / OUT-003: the single snapshot every output reads. One publish updates all outputs on the same frame (NFR-04).
import Foundation
import Domain
import OperatorCore

/// Written by the operator on the main actor, read by render threads. Render threads never see the observable model.
// @unchecked Sendable: all access to `current` goes through `lock`.
final class SceneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: PublishedScenes

    init(_ initial: PublishedScenes) { current = initial }

    func read() -> PublishedScenes { lock.lock(); defer { lock.unlock() }; return current }
    func publish(_ scenes: PublishedScenes) { lock.lock(); current = scenes; lock.unlock() }
}
