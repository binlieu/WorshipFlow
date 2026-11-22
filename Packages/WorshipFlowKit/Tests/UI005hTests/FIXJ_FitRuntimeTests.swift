// FIX-J item 1 (UI-005h): lyrics must fit the block they are drawn in. These tests use only what existed before the fix, so they could be run
// red first: on the default audience theme a bilingual slide that wraps ran off the top of the screen.
import Testing
import Foundation
import Domain
@testable import RenderEngine

enum FIXJFixtures {
    /// Invented words (no scripture): a long first-language line and a Vietnamese second language that wraps to two lines at 79 pt.
    static let bilingualLong = SlideContent(
        primary: "Every morning brings a song of new beginnings and a hope that never fades away, and we sing it again together",
        secondary: "M\u{1ED7}i s\u{00E1}ng mai l\u{00E0} m\u{1ED9}t b\u{00E0}i ca m\u{1EDB}i v\u{00E0} m\u{1ED9}t ni\u{1EC1}m hy v\u{1ECD}ng kh\u{00F4}ng bao gi\u{1EDD} t\u{1EAF}t")
    static let twoLines = SlideContent(primary: "Light of the morning\nLight of the evening",
                                       secondary: "\u{00C1}nh s\u{00E1}ng ban mai\n\u{00C1}nh s\u{00E1}ng chi\u{1EC1}u t\u{00E0}")

    static func px(_ f: NormalizedRect, _ w: Double = 1920, _ h: Double = 1080) -> (x: Double, y: Double, w: Double, h: Double) {
        (f.x * w, f.y * h, f.width * w, f.height * h)
    }

    static func audienceReport(_ slide: SlideContent, theme: Theme, width: Int = 1920, height: Int = 1080) throws -> SceneLayoutReport {
        let scene = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(slide), theme: theme, look: .standard, props: [])
        return try Compositor().layoutReport(scene: scene, width: width, height: height)
    }
}

@Suite struct FIXJ_FitRuntimeTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    @Test func aBilingualSlideThatWrapsStaysInsideBothBlocksOnTheDefaultAudienceTheme() throws {
        let theme = Theme.fullScreen
        let r = try FIXJFixtures.audienceReport(FIXJFixtures.bilingualLong, theme: theme)
        try #require(r.texts.count == 2)
        let pf = FIXJFixtures.px(theme.primary.frame), sf = FIXJFixtures.px(try #require(theme.secondary).frame)
        let p = r.texts[0].box, s = r.texts[1].box
        #expect(p.y >= pf.y - 0.5 && p.y + p.height <= pf.y + pf.h + 0.5, "primary \(p) in frame \(pf)")
        #expect(p.width <= pf.w + 0.5)
        #expect(s.y >= sf.y - 0.5 && s.y + s.height <= sf.y + sf.h + 0.5, "secondary \(s) in frame \(sf)")
        #expect(s.width <= sf.w + 0.5)
    }

    @Test func aFourLineSlideStaysInsideItsBlocksToo() throws {
        let theme = Theme.fullScreen
        let slide = SlideContent(primary: String(repeating: "Praise the Lord with all your heart ", count: 3), secondary: "Ng\u{1EE3}i khen Ch\u{00FA}a")
        let r = try FIXJFixtures.audienceReport(slide, theme: theme)
        let pf = FIXJFixtures.px(theme.primary.frame)
        let p = try #require(r.texts.first).box
        #expect(p.y >= pf.y - 0.5, "primary top \(p.y) above frame top \(pf.y)")
    }

    @Test func aSlideThatFitsAtTheDesignSizeIsDrawnAtTheDesignSize() throws {
        let r = try FIXJFixtures.audienceReport(FIXJFixtures.twoLines, theme: .fullScreen)
        #expect(abs(r.texts[0].fontSize - 119.04) < 0.001 && abs(r.texts[1].fontSize - 78.72) < 0.001)
    }

    @Test func theClassicThemesAndAUserThemeKeepTheirOwnSizeEvenWhenTheWordsDoNotFit() throws {
        let long = SlideContent(primary: String(repeating: "Praise the Lord with all your heart ", count: 6), secondary: "Ng\u{1EE3}i khen Ch\u{00FA}a")
        let classic = try FIXJFixtures.audienceReport(long, theme: .classicFullScreen)
        #expect(abs(classic.texts[0].fontSize - 84) < 0.001)
        let user = try FIXJFixtures.audienceReport(long, theme: UI005hFixtures.userThemes[0])
        #expect(abs(user.texts[0].fontSize - 90) < 0.001)
    }
}
