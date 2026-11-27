// OUT-002f (REVIEW-5 L17): which scenes the warmer has already prepared, so an output's gate can adopt a scene that is ready on the tick it
// arrives instead of asking the background queue and showing the old scene for a frame. The usual case: the Preview slide was warmed ahead of Go Live.
//
// A note, not a guarantee: the stores the warmer fills are bounded and may have let an entry go since. A scene wrongly taken for prepared is drawn
// with first-use work on the render thread, as it was before OUT-002c. Text that changes every second is left out of the comparison (it is never
// prepared), and a scene is only prepared when every image it names is held by the image store.
import Foundation
import Domain

public enum PreparedScenes {
    private static let limit = 16
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recent: [(scene: SceneDescription, width: Int, height: Int)] = []

    /// Called by the warmer after it prepared `scene` for an output of `width` x `height`.
    static func record(_ scene: SceneDescription, _ width: Int, _ height: Int) {
        let key = scene.withoutTickingText
        lock.lock(); defer { lock.unlock() }
        recent.removeAll { $0.width == width && $0.height == height && $0.scene == key }
        if recent.count >= limit { recent.removeFirst() }
        recent.append((key, width, height))
    }

    /// True when `scene` was prepared for this size and every image it names is in the image store. Takes the lock and compares scenes: call it when a
    /// scene changes, not on every frame.
    public static func isPrepared(_ scene: SceneDescription, _ width: Int, _ height: Int) -> Bool {
        let key = scene.withoutTickingText
        lock.lock()
        let found = recent.contains { $0.width == width && $0.height == height && $0.scene == key }
        lock.unlock()
        return found && scene.imagePaths.allSatisfy { SharedImageStore.shared.peek($0) != nil }
    }

    /// Forgets everything (tests).
    static func removeAll() { lock.lock(); recent.removeAll(); lock.unlock() }
}

extension SceneDescription {
    /// The scene without the text that changes every second.
    var withoutTickingText: SceneDescription {
        var copy = self
        copy.textLayers.removeAll { $0.ticks }
        copy.objectLayers.removeAll { if case .text(let t) = $0 { t.ticks } else { false } }
        return copy
    }
}
