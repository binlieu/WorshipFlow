// FIX-J item 7 (UI-005h): how much of a passage one slide holds comes from the theme's own metrics (its line height, the measured advance of
// its font and weight), and a passage is split so that every slide fits at the theme's design size, not only at the floor.
import Testing
import Foundation
import Domain
import RenderEngine
@testable import ScriptureEngine
@testable import OperatorCore

@Suite struct FIXJ_ScriptureLimitsTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    /// Invented prose (no scripture), long enough to split into many slides.
    static let prose = String(repeating: "The river keeps singing its quiet song to the hills, and the evening answers with a gentle light that rests on every roof. Bright morning comes slowly over the valley; the farmers rise and the birds begin their work. ", count: 12)

    func limit(_ theme: Theme, bilingual: Bool = false) throws -> Int {
        try #require(ScriptureSlideLimits.options(theme: theme, bilingual: bilingual, versesPerSlide: 1).maxCharacters)
    }

    func themed(lineHeight: Double?, weight: Int?) -> Theme {
        var t = Theme.fullScreen
        t.primary.style.lineHeight = lineHeight
        t.primary.style.weight = weight
        return t
    }

    @Test func aTallerLineHeightHoldsFewerCharacters() throws {
        let tight = try limit(themed(lineHeight: 1.0, weight: 600))
        let loose = try limit(themed(lineHeight: 1.6, weight: 600))
        #expect(loose < tight, "line height 1.6 holds \(loose), 1.0 holds \(tight)")
    }

    @Test func aHeavierWeightOfTheSameFontHoldsFewerCharacters() throws {
        let light = try limit(themed(lineHeight: 1.2, weight: 300))
        let black = try limit(themed(lineHeight: 1.2, weight: 900))
        #expect(black < light, "weight 900 holds \(black), 300 holds \(light)")
    }

    @Test func theEarlierThemesKeepTheirEarlierLimits() throws {
        // No line height: the estimate the earlier looks were built with (1.15 lines, 0.48 of the size per letter, 92 % filled, a line for the reference).
        func old(_ block: TextBlock) -> Int {
            let size = max(block.style.fontSize, 1)
            let lines = Int((block.frame.height * 1080) / (size * 1.15))
            let perLine = max(Int((block.frame.width * 1920) / (size * 0.48)), 1)
            return max(Int(Double(max(lines - 1, 1) * perLine) * 0.92), 20)
        }
        for theme in [Theme.classicFullScreen] + UI005hFixtures.userThemes where theme.primary.style.lineHeight == nil {
            #expect(try limit(theme) == old(theme.primary), "\(theme.name)")
        }
    }

    @Test func everySlideOfAPassageFitsAtTheDesignSizeOnTheDefaultTheme() throws {
        let theme = Theme.fullScreen
        let parts = TextSplitter.split(Self.prose, maxCharacters: try limit(theme))
        #expect(parts.count > 5)
        let compositor = try Compositor()
        for part in parts {
            let scene = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(SlideContent(primary: part + "\nColossians 3:16a")), theme: theme, look: .standard, props: [])
            let status = try compositor.fitStatus(scene: scene, width: 1920, height: 1080)
            #expect(status.fits && status.factor == 1, "\"\(part)\" (\(part.count) characters) needed factor \(status.factor)")
        }
    }

    @Test func aBilingualPassageFitsAtTheDesignSizeToo() throws {
        let theme = Theme.fullScreen
        let parts = TextSplitter.split(Self.prose, maxCharacters: try limit(theme, bilingual: true))
        let compositor = try Compositor()
        for part in parts {
            let second = String(part.prefix(max(10, part.count * 4 / 5)))
            let scene = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(SlideContent(primary: part + "\nColossians 3:16a", secondary: second + "\nCô-lô-se 3:16a")), theme: theme, look: .standard, props: [])
            let status = try compositor.fitStatus(scene: scene, width: 1920, height: 1080)
            #expect(status.fits && status.factor == 1, "\(part.count) characters needed factor \(status.factor)")
        }
    }

    @Test func aPassageIsSplitAtTheDesignSizeNotAtTheFloor() throws {
        let design = try limit(Theme.fullScreen)
        var atTheFloor = Theme.fullScreen
        atTheFloor.primary.style.fontSize = Theme.fitFloor
        let atFloor = try limit(atTheFloor)
        #expect(design < atFloor, "the limit follows the 119 pt design size (\(design)), not the 56 pt floor (\(atFloor))")
    }
}
