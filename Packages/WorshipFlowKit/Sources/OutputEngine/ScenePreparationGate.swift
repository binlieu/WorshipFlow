// OUT-002c (KI-007): a slide the output has not drawn before costs Core Text layout, a fit measure and an image decode the first time it is
// drawn: about 30 ms of work on the render thread, which is one missed refresh on a 60 Hz display. The gate keeps that work off the render
// thread. When the scene the output is asked to draw brings words or images the screen has not shown, the gate asks a background queue to
// prepare them (into the stores every compositor reads) and keeps returning the scene that is on screen; once the preparation has finished it
// returns the new scene, so the render thread finds everything ready and switches in one frame. The wait is bounded: after `maxHeldFrames`
// frames the new scene is drawn anyway, as it was before this change, so a command is never held back for long and never lost.
//
// The first scene an output draws, Blackout (the stage's too: its one added word is fixed and prepared with any scene), Clear and any scene with no new
// words, objects or images need no preparation and are returned at once. A newer scene cancels the wait for
// an older one that was never shown, and a preparation that finishes after it was replaced is ignored, so scenes are drawn in the order they
// were published (a scene is only ever replaced by a newer one).
//
// OUT-002f. Slide objects count: a new text box, fit-to-box text or shape is prepared (laid out, fitted, rasterised into the shared stores) like
// lyric text. A scene the warmer has already prepared for this output's size (the Preview slide, warmed ahead of Go Live) is returned on the tick it
// arrives and no request is made. A preparation that has run for the whole wait without finishing is taken to be stuck (a stalled file): from then on
// new scenes are returned at once and no request is made, so nothing waits behind it and no thread is added, until some preparation reports done or
// `stallProbeFrames` frames (the gate's own count of calls: nothing ticks while idle) have passed, when one request is tried again.
//
// Limit, not fixed: each output has its own gate and decides alone. Outputs whose scene is already prepared (the usual case, see above) switch on the
// same tick of their own links; for a scene that was not prepared, one output can show it up to `maxHeldFrames` frames before another (three frames, 50 ms
// at 60 Hz), as the links are not locked to each other either. One preparation shared by all outputs would not align their links and is not built.
import Foundation
import Domain
import RenderEngine

enum ScenePreparation {
    /// True when drawing `incoming` after `shown` would do first-use work: a lyric text layer that is not already on screen, or an image that is not.
    /// Text that changes every second (a clock, a timer) is left out: it is drawn when it arrives, as before.
    static func needsWork(incoming: SceneDescription, shown: SceneDescription?) -> Bool {
        let shownLayers = shown?.textLayers ?? []
        if incoming.textLayers.contains(where: { !$0.ticks && !isBlackoutWord($0) && !shownLayers.contains($0) }) { return true }
        // OUT-002f: slide objects that cost work the first time: a text box (with or without a fit), a shape. Images are covered by `imagePaths`.
        let shownObjects = shown?.objectLayers ?? []
        let newObject = incoming.objectLayers.contains { layer in
            switch layer {
            case .text(let text): return !text.ticks && !shownObjects.contains(layer)
            case .shape: return !shownObjects.contains(layer)
            case .image, .video: return false
            }
        }
        if newObject { return true }
        let shownImages = shown?.imagePaths ?? []
        return incoming.imagePaths.contains { !shownImages.contains($0) }
    }

    /// OUT-002f: the one word a stage screen adds when Blackout is on. Its text, frame and style are fixed (only the colour is the layout's own), so it is
    /// prepared with every scene and never makes the gate hold.
    static func isBlackoutWord(_ layer: TextLayer) -> Bool {
        layer == StageComposer.blackoutLayer(warning: layer.style.color)
    }

    /// The preparation itself, on the calling thread (a background queue, never the render thread or the main thread).
    static func warm(_ scene: SceneDescription, _ width: Int, _ height: Int) {
        ImageWarmer.warmNow(scene: scene)
        let blackout = SceneDescription(backgroundColor: .black, textLayers: [StageComposer.blackoutLayer(warning: StageLayout.standard.warningColor)])
        TextWarmer.warmNow(scenes: [(scene, width, height), (blackout, width, height)])
    }
}

/// Called from the render thread only (once per frame), except the two closures it hands to the preparer, which may run on any thread.
// @unchecked Sendable: `shown`, `pending*`, `held` and `nextToken` belong to the render thread; `wantedToken`, `readyToken` and `doneTotal` are guarded by `lock`.
final class ScenePreparationGate: @unchecked Sendable {
    /// Asks for `scene` to be prepared for an output of `width` x `height`. `isWanted` turns false when the scene was replaced or shown; `done`
    /// says the preparation finished (any thread, any time). A preparer may drop a request that is no longer wanted.
    typealias Preparer = @Sendable (_ scene: SceneDescription, _ width: Int, _ height: Int,
                                    _ isWanted: @escaping @Sendable () -> Bool, _ done: @escaping @Sendable () -> Void) -> Void
    /// About three frames: a cold slide's first-use work is about two frames on a 60 Hz display.
    static let defaultMaxHeldFrames = 3
    /// OUT-002f: frames after which a stalled preparation is tried again (10 seconds at 60 Hz).
    static let stallProbeFrames = 600

    private let maxHeldFrames: Int
    private let preparer: Preparer
    private let lock = NSLock()
    private var wantedToken = 0
    private var readyToken = 0
    private var doneTotal = 0
    private var shown: SceneDescription?
    private var pending: SceneDescription?
    private var pendingToken = 0
    private var nextToken = 0
    private var held = 0
    /// OUT-002f: the gate's own clock, one per call (a tick of its output); render thread only.
    private var frame = 0
    private var requestedAt = 0
    private var stalledAt: Int?
    private var doneAtStall = 0
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
        frame += 1
        if let shown, incoming == shown {                      // nothing new (the usual frame): no work and no copy
            if pending != nil { cancelPending() }
            return shown
        }
        // The first scene an output is asked for is drawn at once (there is nothing to keep showing), as is Blackout, Clear and a clock tick.
        guard shown != nil, ScenePreparation.needsWork(incoming: incoming, shown: shown) else { return adopt(incoming) }
        if pending != incoming {
            if let at = stalledAt {
                if frame - at >= Self.stallProbeFrames || finishedCount() != doneAtStall { stalledAt = nil }     // try again
                else { return adopt(incoming) }                                                                  // stuck: nothing waits behind it
            }
            if PreparedScenes.isPrepared(incoming, width, height) { return adopt(incoming) }
            requestedAt = frame
            nextToken += 1
            let token = nextToken
            pending = incoming
            pendingToken = token
            lock.lock(); wantedToken = token; lock.unlock()
            preparer(incoming, width, height,
                     { [weak self] in self?.isWanted(token) ?? false },
                     { [weak self] in self?.finished(token) })
        }
        if isReady(pendingToken) { return adopt(incoming) }
        if held >= maxHeldFrames {
            // Waited the whole time for this very request: the worker is stuck. (A request replaced by a newer one has not waited its own time.)
            if maxHeldFrames > 0, frame - requestedAt >= maxHeldFrames { stalledAt = frame; doneAtStall = finishedCount() }
            return adopt(incoming)
        }
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
    private func finished(_ token: Int) { lock.lock(); doneTotal += 1; if wantedToken == token { readyToken = token }; lock.unlock() }
    private func finishedCount() -> Int { lock.lock(); defer { lock.unlock() }; return doneTotal }
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
