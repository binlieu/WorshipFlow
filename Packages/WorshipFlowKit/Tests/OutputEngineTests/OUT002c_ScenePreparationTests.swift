// OUT-002c (KI-007): a slide the output has not drawn before is prepared off the render thread; the output keeps showing the previous scene until it
// is ready (bounded to a few frames), then switches in one frame. Counts and injected completions only: no wall clock.
import Testing
import Foundation
import Domain
import RenderEngine
@testable import OutputEngine

/// Stands in for the background preparation: records requests and finishes them when the test says so.
private final class ManualPreparer: @unchecked Sendable {
    struct Job { let scene: SceneDescription; let width: Int; let height: Int; let isWanted: @Sendable () -> Bool; let done: @Sendable () -> Void }
    private let lock = NSLock()
    private(set) var jobs: [Job] = []
    var preparer: ScenePreparationGate.Preparer {
        { [self] scene, w, h, wanted, done in lock.lock(); jobs.append(Job(scene: scene, width: w, height: h, isWanted: wanted, done: done)); lock.unlock() }
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return jobs.count }
    func finish(_ i: Int) { guard i < jobs.count else { Issue.record("no preparation request number \(i) was made"); return }; jobs[i].done() }
}

private func slide(_ words: String, ticking: String? = nil) -> SceneDescription {
    let style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)
    var layers = [TextLayer(text: words, style: style, frame: NormalizedRect(x: 0.05, y: 0.2, width: 0.9, height: 0.5), fitFloor: 30)]
    if let ticking { layers.append(TextLayer(text: ticking, style: style, frame: NormalizedRect(x: 0.7, y: 0.9, width: 0.3, height: 0.1), ticks: true)) }
    return SceneDescription(backgroundColor: .black, textLayers: layers)
}
private let blackout = SceneDescription(backgroundColor: .black, textLayers: [])

@Suite struct OUT002c_ScenePreparationTests {
    let w = 1920, h = 1080

    @Test func theFirstSceneAnOutputDrawsIsDrawnAtOnceAndBlackoutNeedsNoPreparation() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())")
        #expect(gate.sceneToDraw(a, width: w, height: h) == a, "nothing else to keep showing: drawn as before")
        #expect(gate.sceneToDraw(blackout, width: w, height: h) == blackout)
        #expect(m.count == 0)
    }

    @Test func aNewSlideKeepsThePreviousSceneOnScreenUntilItIsPrepared() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())"), b = slide("B \(UUID())")
        #expect(gate.sceneToDraw(a, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(m.count == 1 && m.jobs.first?.scene == b && m.jobs.first?.width == w && m.jobs.first?.height == h, "one request per new scene, not one per frame")
        m.finish(0)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b)
    }

    @Test func aSceneAlreadyShownIsNeverPreparedAgain() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())")
        for _ in 0..<100 { #expect(gate.sceneToDraw(a, width: w, height: h) == a) }
        #expect(m.count == 0)
    }

    @Test func aTickingClockOrAnyChangeWithNoNewWordsIsNotHeldBack() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())", ticking: "9:00:01")
        _ = gate.sceneToDraw(a, width: w, height: h)
        let later = slide(a.textLayers[0].text, ticking: "9:00:02")
        #expect(gate.sceneToDraw(later, width: w, height: h) == later, "a new clock text is drawn at once")
        #expect(gate.sceneToDraw(blackout, width: w, height: h) == blackout)
        #expect(m.count == 0)
    }

    @Test func blackoutAndClearNeverWaitAndAnOldPreparationCannotBringTheSlideBack() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())"), b = slide("B \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)        // B pending
        #expect(gate.sceneToDraw(blackout, width: w, height: h) == blackout, "Blackout is drawn on the first frame it is seen")
        m.finish(0)                                                   // B's preparation finishes after the blackout
        #expect(gate.sceneToDraw(blackout, width: w, height: h) == blackout)
        #expect(m.jobs.count == 1 && m.jobs[0].isWanted() == false)
    }

    @Test func aNewerSceneCancelsTheWaitForAnOlderOneThatWasNeverShown() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())"), b = slide("B \(UUID())"), c = slide("C \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(gate.sceneToDraw(c, width: w, height: h) == a)
        #expect(m.jobs.count == 2 && m.jobs[0].isWanted() == false && m.jobs[1].isWanted() == true)
        m.finish(1)
        #expect(gate.sceneToDraw(c, width: w, height: h) == c)
        m.finish(0)                                                   // B finishes late: it must never be drawn
        #expect(gate.sceneToDraw(c, width: w, height: h) == c)
    }

    @Test func scenesAreDrawnInThePublishedOrderEvenWhenAnEarlierPreparationFinishesLater() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())"), b = slide("B \(UUID())"), c = slide("C \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        _ = gate.sceneToDraw(b, width: w, height: h)                  // B pending (job 0)
        m.finish(0)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b)        // B shown
        #expect(gate.sceneToDraw(c, width: w, height: h) == b)        // C pending (job 1), B still shown
        m.finish(0)                                                   // B's job completes again late: harmless
        #expect(gate.sceneToDraw(c, width: w, height: h) == b)
        m.finish(1)
        #expect(gate.sceneToDraw(c, width: w, height: h) == c)
    }

    @Test func theWaitIsBoundedAndTheSceneIsThenDrawnAsBefore() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 3, preparer: m.preparer)
        let a = slide("A \(UUID())"), b = slide("B \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)        // three frames held, never finished
        #expect(gate.sceneToDraw(b, width: w, height: h) == b, "after the limit it switches anyway: never held back, never lost")
        m.finish(0)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b)
    }

    @Test func aNewSceneEveryFrameCannotKeepTheOldOneOnScreenPastTheLimit() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 3, preparer: m.preparer)
        let a = slide("A \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        var drawn: [SceneDescription] = [], published: [SceneDescription] = []
        for i in 0..<4 { let s = slide("fast \(i) \(UUID())"); published.append(s); drawn.append(gate.sceneToDraw(s, width: w, height: h)) }
        #expect(drawn.prefix(3).allSatisfy { $0 == a })
        #expect(drawn[3] == published[3], "on the fourth frame the output draws what is published")
    }

    @Test func aResizeDoesNotGateTheSameScene() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = slide("A \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(a, width: 1280, height: 720) == a)
        #expect(m.count == 0)
    }

    @Test func theFirstFrameOfAPreparedSceneDoesNoCoreTextAndNoFit() throws {
        let gate = ScenePreparationGate(preparer: { scene, w, h, wanted, done in
            if wanted() { ScenePreparation.warm(scene, w, h) }
            done()
        })
        _ = gate.sceneToDraw(blackout, width: 1920, height: 1080)      // something is on screen already
        let scene = slide("first use \(UUID().uuidString)")
        let drawn = gate.sceneToDraw(scene, width: 1920, height: 1080)
        #expect(drawn == scene)
        let compositor = try Compositor()                              // an output's own compositor, never warmed itself
        _ = try compositor.renderImage(scene: drawn, width: 1920, height: 1080)
        #expect(compositor.rasterizationCount == 0, "no Core Text on the render call")
        #expect(compositor.fitComputationCount == 0, "no fit computed on the render call")
    }

    @Test func aSettledSceneIsDrawnWithTheSameBytesAsWithoutTheGate() throws {
        let gate = ScenePreparationGate(preparer: { _, _, _, _, done in done() })
        _ = gate.sceneToDraw(blackout, width: 640, height: 360)
        let scene = slide("same bytes \(UUID().uuidString)")
        let drawn = gate.sceneToDraw(scene, width: 640, height: 360)
        #expect(drawn == scene)
        let direct = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        let gated = try Compositor().renderImage(scene: drawn, width: 640, height: 360)
        #expect(direct.bgra == gated.bgra)
    }

    @Test func whatNeedsWorkIsNewWordsOrNewImagesOnly() {
        let a = slide("A \(UUID())")
        #expect(ScenePreparation.needsWork(incoming: a, shown: nil))
        #expect(!ScenePreparation.needsWork(incoming: a, shown: a))
        #expect(!ScenePreparation.needsWork(incoming: blackout, shown: a))
        #expect(!ScenePreparation.needsWork(incoming: slide(a.textLayers[0].text, ticking: "1"), shown: slide(a.textLayers[0].text, ticking: "2")))
        var withImage = a
        withImage.backgroundImage = ImageLayer(path: "/nonexistent/\(UUID()).png", frame: .full)
        #expect(ScenePreparation.needsWork(incoming: withImage, shown: a))
    }

    // MARK: the background half

    @Test func theBackgroundQueueHoldsOnlyTheNewestRequestAndSkipsTheCancelledOnes() {
        let queue = ClosureQueue()
        let warmed = OUT002cLog()
        let preparer = BackgroundScenePreparer(run: { queue.add($0) }, warm: { scene, _, _ in warmed.add(scene.textLayers[0].text) })
        let finished = OUT002cLog()
        for i in 0..<500 {
            preparer.prepare(slide("job \(i)"), 1920, 1080, isWanted: { true }, done: { finished.add("done \(i)") })
        }
        #expect(queue.count == 1, "one worker, however many scenes were published")
        queue.runAll()
        #expect(warmed.items == ["job 499"], "the older 499 were dropped, not prepared")
        #expect(finished.items == ["done 499"])
    }

    @Test func aRequestNoLongerWantedIsNotPrepared() {
        let queue = ClosureQueue()
        let warmed = OUT002cLog()
        let preparer = BackgroundScenePreparer(run: { queue.add($0) }, warm: { scene, _, _ in warmed.add(scene.textLayers[0].text) })
        preparer.prepare(slide("stale"), 1920, 1080, isWanted: { false }, done: { warmed.add("done") })
        queue.runAll()
        #expect(warmed.items.isEmpty)
    }
}

private final class ClosureQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var work: [@Sendable () -> Void] = []
    func add(_ w: @escaping @Sendable () -> Void) { lock.lock(); work.append(w); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return work.count }
    func runAll() { while true { lock.lock(); let next = work.isEmpty ? nil : work.removeFirst(); lock.unlock(); guard let next else { return }; next() } }
}
private final class OUT002cLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ s: String) { lock.lock(); stored.append(s); lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}
