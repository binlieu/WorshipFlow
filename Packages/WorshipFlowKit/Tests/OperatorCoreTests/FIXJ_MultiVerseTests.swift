// FIX-J item 9 (UI-005h): several verses per slide under the default theme (119 pt Inter), with the real metrics: whole verses pack while they
// fit, and every slide drawn fits its block at the design size (the fit never has to shrink it). Invented verses, no scripture.
import Testing
import Foundation
import CoreText
import Domain
import RenderEngine
@testable import OperatorCore

@MainActor
@Suite struct FIXJ_MultiVerseTests {
    init() {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/Inter/InterVariable.ttf")
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    func fit(_ content: SlideContent) throws -> TextFitStatus {
        let scene = SceneComposer.scene(for: .audience, state: {
            var s = ShowState()
            s.apply(.load(ShowDeck(presentationID: UUID(), slides: [content])))
            s.apply(.trigger(index: 0))
            return s
        }(), theme: .fullScreen, look: .standard, props: [])
        return try Compositor().fitStatus(scene: scene, width: 1920, height: 1080)
    }

    @Test func threeShortVersesPerSlideUnderTheDefaultThemeKeepWholeVersesAndEverySlideFits() async throws {
        let r = try await L4C.rig()                       // default theme: the design's 119 pt
        await r.scripture.setVersesPerSlide(3)
        await r.scripture.show("Psalm 23:1-3")
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.count >= 2 && passage.slides.count <= 3, "slides: \(passage.slides.count)")
        // Verses stay whole and in order; none is lost or repeated.
        var order: [Int] = []
        for slide in passage.slides { for v in slide.verses where order.last != v.verse { order.append(v.verse) } }
        #expect(order == [1, 2, 3])
        for (i, content) in passage.contents.enumerated() {
            let status = try fit(content)
            #expect(status.fits && status.factor == 1, "slide \(i + 1) needed factor \(status.factor): \(content.primary)")
        }
    }

    @Test func aLongVerseUnderTheDefaultThemeSplitsSoEverySlideFitsAtTheDesignSize() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16")
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.count > 1)
        for (i, content) in passage.contents.enumerated() {
            let status = try fit(content)
            #expect(status.fits && status.factor == 1, "slide \(i + 1) needed factor \(status.factor)")
        }
    }
}
