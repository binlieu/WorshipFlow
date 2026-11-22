// UI-006e: Auto-fit on a stage element, through the real compositor (bundled Inter): long words in a small box are shrunk to fit, never below the
// floor; with Auto-fit off nothing changes. Measures text layout only (no hardware).
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct UI006e_StageAutoFitRenderTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    func scene(autoFit: Bool, fontSize: Double = 116) throws -> SceneDescription {
        var e = StageLayout.standard.elements[0]
        e.frame = NormalizedRect(x: 0.04, y: 0.09, width: 0.4, height: 0.2)
        e.style.fontSize = fontSize
        e.secondLanguage = nil
        e.autoFit = autoFit
        let layout = StageLayout(id: UUID(), name: "t", background: .black, elements: [e])
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "My chains are gone and I have been set free by amazing grace")])))
        state.apply(.trigger(index: 0))
        return StageComposer.scene(layout: layout, context: StageContext(state: state, now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil))
    }

    @Test func longWordsInASmallBoxAreShrunkWithAutoFitAndNotWithout() throws {
        let compositor = try Compositor()
        let off = try compositor.fitStatus(scene: scene(autoFit: false), width: 1920, height: 1080)
        #expect(off == .unchanged)
        let on = try compositor.fitStatus(scene: scene(autoFit: true), width: 1920, height: 1080)
        #expect(on.factor < 1)
        #expect(on.factor >= 64.0 / 116.0 - 1e-9)      // never below the lyric minimum
    }

    @Test func aLyricAlreadySmallerThanTheMinimumIsLeftAsSet() throws {
        let status = try Compositor().fitStatus(scene: scene(autoFit: true, fontSize: 40), width: 1920, height: 1080)
        #expect(status.factor == 1)
    }

    @Test func wordsThatFitAreNotShrunk() throws {
        var e = StageLayout.standard.elements[0]
        e.autoFit = true
        e.secondLanguage = nil
        let layout = StageLayout(id: UUID(), name: "t", background: .black, elements: [e])
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amen")])))
        state.apply(.trigger(index: 0))
        let s = StageComposer.scene(layout: layout, context: StageContext(state: state, now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil))
        #expect(try Compositor().fitStatus(scene: s, width: 1920, height: 1080) == TextFitStatus(factor: 1, fits: true))
    }
}
