// R10: decode the images a scene needs before the scene is shown.
import Foundation
import Domain

extension SceneDescription {
    /// Every image file the scene draws, in draw order, without repeats.
    public var imagePaths: [String] {
        var paths: [String] = []
        func add(_ path: String) { if !paths.contains(path) { paths.append(path) } }
        if let background = backgroundImage { add(background.path) }
        for case .image(let image) in objectLayers { add(image.path) }
        for overlay in overlayImages { add(overlay.path) }
        return paths
    }
}

/// Decodes images ahead of time into the store every screen shares (one decode per file, not per screen). The app
/// calls it for the scene that is about to go live (the preview), so that when it is triggered each output finds the
/// pixels ready and draws them in its first frame instead of popping them in a few frames later.
public enum ImageWarmer {
    /// Decodes the image files `scene` draws on a background queue and returns those that could not be read.
    @discardableResult
    public static func warm(scene: SceneDescription) async -> Set<String> {
        await warm(paths: scene.imagePaths)
    }

    /// The same for several scenes (for example every screen's preview).
    @discardableResult
    public static func warm(scenes: [SceneDescription]) async -> Set<String> {
        var paths: [String] = []
        for scene in scenes { for p in scene.imagePaths where !paths.contains(p) { paths.append(p) } }
        return await warm(paths: paths)
    }

    /// The same, on the calling thread (a background queue: never the main thread or the render thread).
    public static func warmNow(scene: SceneDescription) {
        for path in scene.imagePaths { _ = SharedImageStore.shared.load(path, pin: true) }
    }

    private static func warm(paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let missing = MissingPaths()
                DispatchQueue.concurrentPerform(iterations: paths.count) { i in
                    if SharedImageStore.shared.load(paths[i], pin: true).outcome.image == nil { missing.add(paths[i]) }
                }
                continuation.resume(returning: missing.paths)
            }
        }
    }
}

// @unchecked Sendable: `found` is guarded by `lock`.
private final class MissingPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var found: Set<String> = []
    func add(_ path: String) { lock.lock(); found.insert(path); lock.unlock() }
    var paths: Set<String> { lock.lock(); defer { lock.unlock() }; return found }
}
