// OUT-002f (REVIEW-5 M6, L17, L18, L20): what the preparation gate holds and what it adopts at once. Counts, injected completions and the gate's own
// frame count: no wall clock.
import Testing
import Foundation
import Domain
import RenderEngine
@testable import OutputEngine

private final class ManualPreparer: @unchecked Sendable {
    struct Job { let scene: SceneDescription; let isWanted: @Sendable () -> Bool; let done: @Sendable () -> Void }
    private let lock = NSLock()
    private(set) var jobs: [Job] = []
    var preparer: ScenePreparationGate.Preparer {
        { [self] scene, _, _, wanted, done in lock.lock(); jobs.append(Job(scene: scene, isWanted: wanted, done: done)); lock.unlock() }
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return jobs.count }
    func finish(_ i: Int) { guard i < jobs.count else { Issue.record("no preparation request number \(i) was made"); return }; jobs[i].done() }
}

private let textStyle = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)
private func lyric(_ words: String) -> SceneDescription {
    SceneDescription(backgroundColor: .black, textLayers: [TextLayer(text: words, style: textStyle, frame: NormalizedRect(x: 0.05, y: 0.2, width: 0.9, height: 0.5), fitFloor: 30)])
}
private func box(_ words: String, fit: Bool = false) -> SceneDescription {
    SceneDescription(backgroundColor: .black, textLayers: [], objectLayers: [
        .text(TextLayer(text: words, style: textStyle, frame: NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2), fitFloor: fit ? 20 : nil))])
}
private func shape(_ red: Double) -> SceneDescription {
    SceneDescription(backgroundColor: .black, textLayers: [], objectLayers: [
        .shape(ShapeLayer(shape: .rectangle, fill: ColorRGBA(red: red, green: 0.3, blue: 0.3, alpha: 1), frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3)))])
}

/// A colour value that depends on the tag, so that a shape's bitmap in the process-wide store is this test's own (never another test's).
private func shade(_ tag: String) -> Double {
    var h: UInt64 = 1469598103934665603
    for u in tag.unicodeScalars { h = (h ^ UInt64(u.value)) &* 1099511628211 }
    return Double(h % 100_000) / 100_000
}

private func objectScene() -> SceneDescription {
    let tag = UUID().uuidString
    return SceneDescription(backgroundColor: .black, textLayers: [], objectLayers: [
        .shape(ShapeLayer(shape: .roundedRectangle(cornerRadius: 0.1), fill: ColorRGBA(red: shade(tag), green: 0.4, blue: 0.8, alpha: 1),
                          frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3))),
        .text(TextLayer(text: "Plain box \(tag)", style: textStyle, frame: NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2))),
        .text(TextLayer(text: "Fitted box \(tag), with enough words to need shrinking in a small frame", style: textStyle,
                        frame: NormalizedRect(x: 0.1, y: 0.75, width: 0.4, height: 0.15), fitFloor: 20)),
    ])
}

@Suite struct OUT002f_GateTests {
    let w = 1920, h = 1080

    // MARK: M6

    @Test func aNewTextBoxAShapeOrAFitBoxIsSeenByNeedsWork() {
        let a = box("A \(UUID())")
        #expect(ScenePreparation.needsWork(incoming: box("B \(UUID())"), shown: a), "a new text box")
        #expect(ScenePreparation.needsWork(incoming: box("B \(UUID())", fit: true), shown: a), "a new fit-to-box text box")
        #expect(ScenePreparation.needsWork(incoming: shape(0.5), shown: a), "a new shape")
        #expect(ScenePreparation.needsWork(incoming: shape(0.5), shown: shape(0.6)), "a shape in another colour")
    }

    @Test func objectsAlreadyOnScreenOrOfNoCostAreNotNewWork() {
        let a = box("A \(UUID())"), s = shape(0.5)
        #expect(!ScenePreparation.needsWork(incoming: a, shown: a))
        #expect(!ScenePreparation.needsWork(incoming: s, shown: s))
        #expect(!ScenePreparation.needsWork(incoming: SceneDescription(backgroundColor: .black, textLayers: []), shown: a), "removing objects needs nothing")
        var withLyric = a
        withLyric.textLayers = lyric("L \(UUID())").textLayers
        #expect(ScenePreparation.needsWork(incoming: withLyric, shown: a), "a new lyric next to a kept box still needs work")
    }

    @Test func aSceneWithANewTextBoxIsHeldUntilItIsPrepared() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = box("A \(UUID())"), b = box("B \(UUID())")
        #expect(gate.sceneToDraw(a, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a, "the new box is prepared first")
        #expect(m.count == 1)
        m.finish(0)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b)
    }

    @Test func throughTheGateNoTextBoxShapeOrFitBoxCostsAnythingOnTheRenderCall() throws {
        let gate = ScenePreparationGate(preparer: { scene, w, h, wanted, done in if wanted() { ScenePreparation.warm(scene, w, h) }; done() })
        let c = try Compositor()
        _ = gate.sceneToDraw(SceneDescription(backgroundColor: .black, textLayers: []), width: 1920, height: 1080)
        let scene = objectScene()
        let drawn = gate.sceneToDraw(scene, width: 1920, height: 1080)
        #expect(drawn == scene)
        _ = try c.renderImage(scene: drawn, width: 1920, height: 1080)
        #expect(c.rasterizationCount == 0)
        #expect(c.objectFitComputationCount == 0)
        #expect(c.shapeRasterizationCount == 0)
    }

    // MARK: L17

    @Test func aScenePreparedBeforeGoLiveIsAdoptedOnTheSameTickWithNoRequest() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = lyric("A \(UUID())"), b = lyric("B \(UUID())")
        TextWarmer.warmNow(scenes: [(b, w, h)])                       // the Preview slide was warmed ahead of Go Live
        #expect(gate.sceneToDraw(a, width: w, height: h) == a)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b, "everything it needs is in the stores: no frame is lost")
        #expect(m.count == 0, "and no request is made")
    }

    @Test func aPreparedSceneWithAChangedClockIsStillAdoptedAtOnce() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        func withClock(_ s: SceneDescription, _ t: String) -> SceneDescription {
            var s = s
            s.textLayers.append(TextLayer(text: t, style: textStyle, frame: NormalizedRect(x: 0.7, y: 0.9, width: 0.3, height: 0.1), ticks: true))
            return s
        }
        let a = lyric("A \(UUID())"), b = lyric("B \(UUID())")
        TextWarmer.warmNow(scenes: [(b, w, h)])
        _ = gate.sceneToDraw(withClock(a, "9:00:01"), width: w, height: h)
        let incoming = withClock(b, "9:00:02")
        #expect(gate.sceneToDraw(incoming, width: w, height: h) == incoming)
        #expect(m.count == 0)
    }

    @Test func aSceneWarmedForAnotherSizeIsNotPrepared() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        let a = lyric("A \(UUID())"), b = lyric("B \(UUID())")
        TextWarmer.warmNow(scenes: [(b, 1280, 720)])
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a, "the stores hold it for 1280x720 only")
        #expect(m.count == 1)
    }

    @Test func aSceneWhoseImageIsNotInTheStoreIsNotPrepared() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        var b = lyric("B \(UUID())")
        b.backgroundImage = ImageLayer(path: "/nonexistent/\(UUID()).png", frame: .full)
        let a = lyric("A \(UUID())")
        TextWarmer.warmNow(scenes: [(b, w, h)])                        // the words are warm, the image could not be read
        _ = gate.sceneToDraw(a, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == a)
        #expect(m.count == 1)
    }

    // MARK: L18

    @Test func theStageBlackoutSceneIsAdoptedOnTheTickItArrives() {
        let deck = ShowDeck(presentationID: UUID(), slides: ["First \(UUID())", "Second \(UUID())"].map { SlideContent(primary: $0) })
        var state = ShowState()
        state.apply(.load(deck)); state.apply(.trigger(index: 0))
        let live = SceneComposer.scene(for: .stage, state: state, clockText: "10:00")
        state.apply(.blackout)
        let dark = SceneComposer.scene(for: .stage, state: state, clockText: "10:00")
        #expect(dark.textLayers.contains { $0.text == "BLACKOUT" }, "the composer's own Blackout scene, with its BLACKOUT layer")
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        _ = gate.sceneToDraw(live, width: w, height: h)
        #expect(gate.sceneToDraw(dark, width: w, height: h) == dark, "Blackout never waits, on the stage screen too")
        #expect(m.count == 0)
    }

    @Test func liftingTheStageBlackoutIsDrawnAtOnceToo() {
        let deck = ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Only \(UUID())")])
        var state = ShowState()
        state.apply(.load(deck)); state.apply(.trigger(index: 0))
        let live = SceneComposer.scene(for: .stage, state: state, clockText: "10:00")
        state.apply(.blackout)
        let dark = SceneComposer.scene(for: .stage, state: state, clockText: "10:00")
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        _ = gate.sceneToDraw(live, width: w, height: h)
        _ = gate.sceneToDraw(dark, width: w, height: h)
        #expect(gate.sceneToDraw(live, width: w, height: h) == live)
        #expect(m.count == 0)
    }

    @Test func aStageBlackoutOnAScreenThatShowsNothingYetNeedsNoPreparation() {
        let blank = SceneDescription(backgroundColor: .black, textLayers: [])
        var dark = blank
        dark.textLayers = [StageComposer.blackoutLayer(warning: StageLayout.standard.warningColor)]
        #expect(!ScenePreparation.needsWork(incoming: dark, shown: blank))
    }

    @Test func theBlackoutWordIsWarmedWithAnySceneThatIsPreparedForAnOutput() throws {
        ScenePreparation.warm(lyric("Any \(UUID())"), w, h)
        let c = try Compositor()
        var dark = SceneDescription(backgroundColor: .black, textLayers: [])
        dark.textLayers = [StageComposer.blackoutLayer(warning: StageLayout.standard.warningColor)]
        _ = try c.renderImage(scene: dark, width: w, height: h)
        #expect(c.rasterizationCount == 0, "the BLACKOUT word is in the store: no Core Text on the render call")
    }

    @Test func audienceClearIsNotHeldEither() {
        let deck = ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Words \(UUID())")])
        var state = ShowState()
        state.apply(.load(deck)); state.apply(.trigger(index: 0))
        let live = SceneComposer.scene(for: .audience, state: state)
        state.apply(.clearBackground)
        let cleared = SceneComposer.scene(for: .audience, state: state)
        let m = ManualPreparer()
        let gate = ScenePreparationGate(preparer: m.preparer)
        _ = gate.sceneToDraw(live, width: w, height: h)
        #expect(gate.sceneToDraw(cleared, width: w, height: h) == cleared)
        #expect(m.count == 0)
    }

    // MARK: L20

    /// A preparer that never returns: the worker is stuck on a stalled read. After the first scene it had to abandon, new scenes are not held.
    @Test func aPreparationThatNeverReturnsStopsCostingLaterScenes() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 3, preparer: m.preparer)
        let a = lyric("A \(UUID())")
        _ = gate.sceneToDraw(a, width: w, height: h)
        let b = lyric("B \(UUID())")
        for _ in 0..<3 { #expect(gate.sceneToDraw(b, width: w, height: h) == a) }
        #expect(gate.sceneToDraw(b, width: w, height: h) == b, "the first one waits the full hold and is drawn anyway")
        for i in 0..<20 {
            let next = lyric("later \(i) \(UUID())")
            #expect(gate.sceneToDraw(next, width: w, height: h) == next, "while a preparation is stuck, new scenes are adopted at once")
        }
        #expect(m.count == 1, "and no further request is made, so no further work waits behind the stuck one")
    }

    @Test func holdingResumesWhenAnyPreparationReportsDone() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 2, preparer: m.preparer)
        _ = gate.sceneToDraw(lyric("A \(UUID())"), width: w, height: h)
        let b = lyric("B \(UUID())")
        _ = gate.sceneToDraw(b, width: w, height: h); _ = gate.sceneToDraw(b, width: w, height: h)
        #expect(gate.sceneToDraw(b, width: w, height: h) == b)
        let c = lyric("C \(UUID())")
        #expect(gate.sceneToDraw(c, width: w, height: h) == c)
        m.finish(0)                                                    // the stuck worker came back
        let d = lyric("D \(UUID())")
        #expect(gate.sceneToDraw(d, width: w, height: h) == c, "the gate holds again: the preparation works")
        #expect(m.count == 2)
    }

    @Test func holdingResumesAfterTheProbeLimitEvenIfNothingEverReturns() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 2, preparer: m.preparer)
        _ = gate.sceneToDraw(lyric("A \(UUID())"), width: w, height: h)
        let b = lyric("B \(UUID())")
        _ = gate.sceneToDraw(b, width: w, height: h); _ = gate.sceneToDraw(b, width: w, height: h)
        _ = gate.sceneToDraw(b, width: w, height: h)                    // stuck: abandoned
        var last = b
        for i in 0..<(ScenePreparationGate.stallProbeFrames - 1) {
            last = lyric("fast \(i) \(UUID())")
            #expect(gate.sceneToDraw(last, width: w, height: h) == last, "frame \(i) of the stall")
        }
        let probe = lyric("probe \(UUID())")
        #expect(gate.sceneToDraw(probe, width: w, height: h) == last, "after the limit one request is tried again, and held")
        #expect(m.count == 2)
    }

    @Test func aSlowButFinishingPreparationNeverStartsAStall() {
        let m = ManualPreparer()
        let gate = ScenePreparationGate(maxHeldFrames: 3, preparer: m.preparer)
        var shown = lyric("A \(UUID())")
        _ = gate.sceneToDraw(shown, width: w, height: h)
        for i in 0..<5 {
            let next = lyric("slide \(i) \(UUID())")
            #expect(gate.sceneToDraw(next, width: w, height: h) == shown)
            m.finish(i)
            #expect(gate.sceneToDraw(next, width: w, height: h) == next)
            shown = next
        }
        #expect(m.count == 5)
    }

    @Test func oneWorkerAndOneWaitingRequestHoweverManyScenesArriveBehindABlockedPreparation() {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock(); private var n = 0
            func add() { lock.lock(); n += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let started = Counter(), runs = Counter()
        let release = DispatchSemaphore(value: 0)
        let preparer = BackgroundScenePreparer(run: { work in runs.add(); DispatchQueue.global().async(execute: work) },
                                               warm: { _, _, _ in started.add(); release.wait() })
        for i in 0..<200 { preparer.prepare(lyric("blocked \(i)"), 1920, 1080, isWanted: { true }, done: {}) }
        #expect(runs.value == 1, "one worker thread for the preparer, however many requests")
        release.signal(); release.signal()                             // lets the blocked one and the single waiting one finish
    }
}
