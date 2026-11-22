// FIX-J item 1 (UI-005h): fit text to its block. Real Inter metrics (the bundled font, registered like the app does).
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct FIXJ_FitTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    func scene(_ role: ScreenRole, _ slide: SlideContent, theme: Theme) -> SceneDescription {
        SceneComposer.scene(for: role, state: UI005hFixtures.live(slide), theme: theme, look: .standard, props: [])
    }

    /// The same theme without its shadow, so the ink is the glyphs alone.
    func unshadowed(_ theme: Theme) -> Theme {
        var t = theme
        t.primary.style.shadow = nil
        t.secondary?.style.shadow = nil
        return t
    }

    /// Bounds of the pixels with any alpha, on a transparent frame (so the picture is the words alone).
    func inkBounds(_ s: SceneDescription, width: Int = 1920, height: Int = 1080) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var s = s
        s.backgroundColor = .clear
        s.backgroundGradient = nil
        s.showsVideo = false
        let f = try Compositor().renderImage(scene: s, width: width, height: height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where f.bgra[(y * width + x) * 4 + 3] != 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    // MARK: The switch

    @Test func builtInLooksFitAndClassicAndUserThemesDoNot() {
        #expect(Theme.fullScreen.fitsText && Theme.lowerThird.fitsText)
        #expect(!Theme.classicFullScreen.fitsText && !Theme.classicLowerThird.fitsText)
        #expect(UI005hFixtures.userThemes.allSatisfy { !$0.fitsText })
    }

    @Test func theSwitchIsWrittenOnlyWhenOnSoAUserThemeEncodesAsBefore() throws {
        let theme = UI005hFixtures.userThemes[0]
        let json = try JSONEncoder().encode(theme)
        #expect(!String(decoding: json, as: UTF8.self).contains("fitsText"))
        #expect(try JSONDecoder().decode(Theme.self, from: json) == theme)
        var on = theme
        on.fitsText = true
        let onJSON = try JSONEncoder().encode(on)
        #expect(String(decoding: onJSON, as: UTF8.self).contains("fitsText"))
        #expect(try JSONDecoder().decode(Theme.self, from: onJSON).fitsText)
    }

    @Test func aLayerCarriesTheFloorOnlyWhenItsThemeFits() {
        let slide = FIXJFixtures.twoLines
        #expect(scene(.audience, slide, theme: .fullScreen).textLayers.allSatisfy { $0.fitFloor == 56 })
        #expect(scene(.audience, slide, theme: .classicFullScreen).textLayers.allSatisfy { $0.fitFloor == nil })
        #expect(scene(.broadcast, FIXJFixtures.twoLines, theme: .lowerThird).textLayers.allSatisfy { $0.fitFloor == 56 })
    }

    // MARK: Fitting

    @Test func aBilingualVietnameseSlideFitsInsideBothBlocksByShrinkingTogether() throws {
        let theme = Theme.fullScreen
        let s = scene(.audience, FIXJFixtures.bilingualLong, theme: theme)
        let c = try Compositor()
        let status = try c.fitStatus(scene: s, width: 1920, height: 1080)
        #expect(status.fits)
        #expect(status.factor < 1 && status.factor >= 56 / 119.04 - 1e-9, "factor \(status.factor)")
        let r = try c.layoutReport(scene: s, width: 1920, height: 1080)
        let pf = FIXJFixtures.px(theme.primary.frame), sf = FIXJFixtures.px(try #require(theme.secondary).frame)
        let p = r.texts[0], q = r.texts[1]
        #expect(p.box.y >= pf.y - 0.5 && p.box.y + p.box.height <= pf.y + pf.h + 0.5, "primary \(p.box)")
        #expect(q.box.y >= sf.y - 0.5 && q.box.y + q.box.height <= sf.y + sf.h + 0.5, "secondary \(q.box)")
        // The two languages keep their ratio.
        #expect(abs(q.fontSize / p.fontSize - 78.72 / 119.04) < 1e-6)
        #expect(abs(p.fontSize - 119.04 * status.factor) < 1e-6)
    }

    @Test func everyLinesInkIsInsideTheBlockItBelongsTo() throws {
        let theme = unshadowed(.fullScreen)
        let s = scene(.audience, FIXJFixtures.bilingualLong, theme: theme)
        let ink = try #require(try inkBounds(s))
        let pf = FIXJFixtures.px(theme.primary.frame), sf = FIXJFixtures.px(try #require(theme.secondary).frame)
        // A little room above for stacked Vietnamese marks, which may rise past the line box.
        let marks = 0.15 * 119.04
        #expect(Double(ink.minY) >= pf.y - marks, "ink top \(ink.minY)")
        #expect(Double(ink.maxY) <= sf.y + sf.h + 1)
        #expect(Double(ink.minX) >= pf.x - 1 && Double(ink.maxX) <= pf.x + pf.w + 1)
    }

    @Test func aVeryLongLineIsDrawnAtTheFloorAndFlagged() throws {
        let theme = unshadowed(.fullScreen)
        let slide = SlideContent(primary: String(repeating: "Praise the Lord with all your heart and soul ", count: 14), secondary: "Ng\u{1EE3}i khen Ch\u{00FA}a")
        let s = scene(.audience, slide, theme: theme)
        let c = try Compositor()
        let status = try c.fitStatus(scene: s, width: 1920, height: 1080)
        #expect(!status.fits)
        #expect(abs(status.factor - 56 / 119.04) < 1e-9)
        let r = try c.layoutReport(scene: s, width: 1920, height: 1080)
        #expect(abs(r.texts[0].fontSize - 56) < 1e-6)
        // Drawn clipped to the title-safe frame: nothing outside it.
        let ink = try #require(try inkBounds(s))
        #expect(Double(ink.minY) >= 0.05 * 1080 - 1 && Double(ink.maxY) <= 0.95 * 1080 + 1)
        #expect(Double(ink.minX) >= 0.05 * 1920 - 1 && Double(ink.maxX) <= 0.95 * 1920 + 1)
    }

    @Test func aSlideThatFitsIsNotShrunkAndNotFlagged() throws {
        let c = try Compositor()
        let status = try c.fitStatus(scene: scene(.audience, FIXJFixtures.twoLines, theme: .fullScreen), width: 1920, height: 1080)
        #expect(status.fits && status.factor == 1)
    }

    @Test func aThemeWithoutTheSwitchIsNotAnalysed() throws {
        let c = try Compositor()
        let long = SlideContent(primary: String(repeating: "Praise the Lord with all your heart ", count: 12))
        let status = try c.fitStatus(scene: scene(.audience, long, theme: .classicFullScreen), width: 1920, height: 1080)
        #expect(status.fits && status.factor == 1)
    }

    @Test func theFactorIsTheSameAtThumbnailSizeAndAtOutputSize() throws {
        let s = scene(.audience, FIXJFixtures.bilingualLong, theme: .fullScreen)
        let c = try Compositor()
        let big = try c.fitStatus(scene: s, width: 1920, height: 1080)
        let small = try c.fitStatus(scene: s, width: 320, height: 180)
        let hd = try c.fitStatus(scene: s, width: 1280, height: 720)
        #expect(big == small && big == hd)
    }

    @Test func fittingIsComputedOncePerSlideAndThemeAndNotPerFrame() throws {
        let s = scene(.audience, FIXJFixtures.bilingualLong, theme: .fullScreen)
        let c = try Compositor()
        _ = try c.renderImage(scene: s, width: 640, height: 360)
        let after1 = c.fitComputationCount, rasters1 = c.rasterizationCount
        for _ in 0..<5 { _ = try c.renderImage(scene: s, width: 640, height: 360) }
        #expect(after1 == 1)
        #expect(c.fitComputationCount == 1 && c.rasterizationCount == rasters1)
        // A frame at another size of the same slide reuses the one computation.
        _ = try c.renderImage(scene: s, width: 320, height: 180)
        #expect(c.fitComputationCount == 1)
    }

    @Test func aUserThemeThatSwitchesFitOnShrinksTooAndOneWithoutItDoesNot() throws {
        var t = UI005hFixtures.userThemes[0]
        t.fitsText = true
        let slide = SlideContent(primary: String(repeating: "Praise the Lord with all your heart ", count: 6), secondary: "Ng\u{1EE3}i khen Ch\u{00FA}a")
        let c = try Compositor()
        let on = try c.layoutReport(scene: scene(.audience, slide, theme: t), width: 1920, height: 1080)
        #expect(on.texts[0].fontSize < 90)
        let off = try c.layoutReport(scene: scene(.audience, slide, theme: UI005hFixtures.userThemes[0]), width: 1920, height: 1080)
        #expect(abs(off.texts[0].fontSize - 90) < 1e-9)
    }

    // MARK: Lower third

    @Test func theLowerThirdKeepsTwoLinesAtDesignSizeAndShrinksBeyondThat() throws {
        let c = try Compositor()
        let two = try c.layoutReport(scene: scene(.broadcast, UI005hFixtures.lowerThirdSlide, theme: .lowerThird), width: 1920, height: 1080)
        #expect(abs(two.texts[0].fontSize - 67.2) < 1e-9)
        let long = SlideContent(primary: String(repeating: "Praise the Lord with all your heart and soul ", count: 5), secondary: "Ng\u{1EE3}i khen Ch\u{00FA}a")
        let s = scene(.broadcast, long, theme: .lowerThird)
        let status = try c.fitStatus(scene: s, width: 1920, height: 1080)
        let r = try c.layoutReport(scene: s, width: 1920, height: 1080)
        #expect(r.texts[0].fontSize < 67.2)
        #expect(status.fits ? r.texts[0].lineCount <= 2 : abs(r.texts[0].fontSize - 56) < 1e-6)
        let plate = try #require(r.plate)
        if status.fits { #expect(plate.y >= 0.05 * 1080 - 0.5, "plate \(plate)") }
    }

    @Test func aLowerThirdThatCannotFitIsFlaggedAndClippedToTheTitleSafeFrame() throws {
        let long = SlideContent(primary: String(repeating: "Praise the Lord with all your heart and soul ", count: 40), secondary: "x")
        let s = scene(.broadcast, long, theme: unshadowed(.lowerThird))
        let status = try Compositor().fitStatus(scene: s, width: 1920, height: 1080)
        #expect(!status.fits)
        let ink = try #require(try inkBounds(s))
        #expect(Double(ink.minY) >= 0.05 * 1080 - 1)
    }
}
