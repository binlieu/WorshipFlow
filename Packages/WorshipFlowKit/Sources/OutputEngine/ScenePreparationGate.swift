// OUT-002c (KI-007): a slide the output has not drawn before costs Core Text layout, a fit measure and an image decode the first time it is
// drawn: about 30 ms of work on the render thread, which is one missed refresh on a 60 Hz display. The gate keeps that work off the render
// thread. When the scene the output is asked to draw brings words or images the screen has not shown, the gate asks a background queue to
// prepare them (into the stores every compositor reads) and keeps returning the scene that is on screen; once the preparation has finished it
// returns the new scene, so the render thread finds everything ready and switches in one frame. The wait is bounded: after `maxHeldFrames`
// frames the new scene is drawn anyway, as it was before this change, so a command is never held back for long and never lost.
//
// The first scene an output draws, Blackout, Clear and any scene with no new words or images need no preparation and are returned at once. A newer scene cancels the wait for
// an older one that was never shown, and a preparation that finishes after it was replaced is ignored, so scenes are drawn in the order they
// were published (a scene is only ever replaced by a newer one).
import Foundation
import Domain
import RenderEngine

enum ScenePreparation {
    /// True when drawing `incoming` after `shown` would do first-use work: a lyric text layer that is not already on screen, or an image that is not.
    /// Text that changes every second (a clock, a timer) is left out: it is drawn when it arrives, as before.
    static func needsWork(incoming: SceneDescription, shown: SceneDescription?) -> Bool {
        let shownLayers = shown?.textLayers ?? []
        if incoming.textLayers.contains(where: { !$0.ticks && !shownLayers.contains($0) }) { return true }
        let shownImages = shown?.imagePaths ?? []
        return incoming.imagePaths.contains { !shownImages.contains($0) }
    }

    /// The preparation itself, on the calling thread (a background queue, never the render thread or the main thread).
    static func warm(_ scene: SceneDescription, _ width: Int, _ height: Int) {
        ImageWarmer.warmNow(scene: scene)
        TextWarmer.warmNow(scenes: [(scene, width, height)])
    }
}

/// Called from the render thread only (once per frame), except the two closures it hands to the preparer, which may run on any thread.
// @unchecked Sendable: `shown`, `pending*`, `held` and `nextToken` belong to the render thread; `wantedToken` and `readyToken` are guarded by `lock`.
final class ScenePreparationGate: @unchecked Sendable {
    /// Asks for `scene` to be prepared for an output of `width` x `height`. `isWanted` turns false when the scene was replaced or shown; `done`
    /// says the preparation finished (any thread, any time). A preparer may drop a request that is no longer wanted.
    typealias Preparer = @Sendable (_ scene: SceneDescription, _ width: Int, _ height: Int,
                                    _ isWanted: @escaping @Sendable () -> Bool, _ done: @escaping @Sendable () -> Void) -> Void
    /// About three frames: a cold slide's first-use work is about two frames on a 60 Hz display.
    static let defaultMaxHeldFrames = 3

    private let maxHeldFrames: Int
    private let preparer: Preparer
    private let lock = NSLock()
    private var wantedToken = 0
    private var readyToken = 0
    private var shown: SceneDescription?
    private var pending: SceneDescription?
    private var pendingToken = 0
    private var nextToken = 0
    private var held = 0
    /// OUT-002d (reporting only): true when the last `sceneToDraw` returned a scene different from the one before it. Render thread only.
    private(set) var adoptedOnLastCall = false
    /// OUT-002d: true while the gate is keeping the scene on screen and waiting for a preparation. Render thread only.
    var isHolding: Bool { pending != nil }

    init(maxHeldFrames: Int = ScenePreparationGate.defaultMaxHeldFrames, preparer: @escaping Preparer) {
        self.maxHeldFrames = max(0, maxHeldFrames)
        self.preparer = preparer
    }

    /// The scene to draw this frame, given the one the output was asked for.
    func sceneToDraw(_ incoming: SceneDescription, width: Int, height: Int) -> SceneDescription {
        adoptedOnLastCall = false
        if let shown, incoming == shown {                      // nothing new (the usual frame): no work and no copy
            if pending != nil { cancelPending() }
            return shown
        }
        // The first scene an output is asked for is drawn at once (there is nothing to keep showing), as is Blackout, Clear and a clock tick.
        guard shown != nil, ScenePreparation.needsWork(incoming: incoming, shown: shown) else { return adopt(incoming) }
        if pending != incoming {
            nextToken += 1
            let token = nextToken
            pending = incoming
            pendingToken = token
            lock.lock(); wantedToken = token; lock.unlock()
            preparer(incoming, width, height,
                     { [weak self] in self?.isWanted(token) ?? false },
                     { [weak self] in self?.finished(token) })
        }
        if isReady(pendingToken) || held >= maxHeldFrames { return adopt(incoming) }
        held += 1
        return shown ?? incoming
    }

    private func adopt(_ scene: SceneDescription) -> SceneDescription {
        adoptedOnLastCall = true
        shown = scene
        cancelPending()
        return scene
    }

    private func cancelPending() {
        pending = nil
        held = 0
        lock.lock(); wantedToken = 0; lock.unlock()
    }

    private func isWanted(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return wantedToken == token }
    private func isReady(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return readyToken == token }
    /// A preparation that finishes after its scene was replaced or shown changes nothing.
    private func finished(_ token: Int) { lock.lock(); if wantedToken == token { readyToken = token }; lock.unlock() }
}

/// Runs preparations one at a time on a background queue and keeps only the newest request: however many scenes are published while one is being
/// prepared, one request waits, so the queue never grows. A request that is no longer wanted when its turn comes is skipped.
// @unchecked Sendable: `latest` and `workerScheduled` are guarded by `lock`.
final class BackgroundScenePreparer: @unchecked Sendable {
    private struct Request {
        let scene: SceneDescription
        let width: Int
        let height: Int
        let isWanted: @Sendable () -> Bool
        let done: @Sendable () -> Void
    }
    private let lock = NSLock()
    private var latest: Request?
    private var workerScheduled = false
    private let run: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let warm: @Sendable (SceneDescription, Int, Int) -> Void

    init(run: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
         warm: @escaping @Sendable (SceneDescription, Int, Int) -> Void = { ScenePreparation.warm($0, $1, $2) }) {
        self.run = run
        self.warm = warm
    }

    func prepare(_ scene: SceneDescription, _ width: Int, _ height: Int,
                 isWanted: @escaping @Sendable () -> Bool, done: @escaping @Sendable () -> Void) {
        lock.lock()
        latest = Request(scene: scene, width: width, height: height, isWanted: isWanted, done: done)
        let start = !workerScheduled
        workerScheduled = true
        lock.unlock()
        if start { run { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let request = latest else { workerScheduled = false; lock.unlock(); return }
            latest = nil
            lock.unlock()
            guard request.isWanted() else { continue }
            warm(request.scene, request.width, request.height)
            request.done()
        }
    }
}
