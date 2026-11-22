// FIX-J item 2 (UI-005h): per-second text has its own small cache, and the selected slide's text is rasterised ahead of Go Live.
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct FIXJ_TextCacheTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    func oneLine(_ text: String) -> SceneDescription {
        SceneDescription(backgroundColor: .black, textLayers: [
            TextLayer(text: text, style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), frame: .full)])
    }

    @Test func theClockTheTimersAndTheCountdownAreMarkedAsTicking() {
        let timer = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 632))
        let ctx = StageContext(state: UI005hFixtures.live(), now: 0, timeOfDayText: "9:14", timers: [timer], message: nil, notes: nil)
        let layers = StageComposer.scene(layout: .standard, context: ctx).textLayers
        #expect(layers.filter(\.ticks).map(\.text).sorted() == ["10:32", "9:14"])
        #expect(layers.filter { !$0.ticks }.count == layers.count - 2)
    }

    @Test func aLayerEncodesTheFlagOnlyWhenItIsSet() throws {
        var l = TextLayer(text: "x", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), frame: .full)
        #expect(!String(decoding: try JSONEncoder().encode(l), as: UTF8.self).contains("ticks"))
        l.ticks = true
        let json = try JSONEncoder().encode(l)
        #expect(String(decoding: json, as: UTF8.self).contains("ticks"))
        #expect(try JSONDecoder().decode(TextLayer.self, from: json).ticks)
    }

    @Test func tickingTextHasItsOwnSmallCacheAndNeverEvictsALyric() throws {
        let c = try Compositor()
        let lyric = oneLine("the lyric that must stay")
        _ = try c.renderImage(scene: lyric, width: 160, height: 90)
        let base = c.rasterizationCount
        for i in 0..<500 {
            var s = oneLine("tick \(i)")
            s.textLayers[0].ticks = true
            _ = try c.renderImage(scene: s, width: 160, height: 90)
        }
        #expect(c.rasterizationCount == base + 500)
        #expect(c.tickingCacheCount <= Compositor.tickingCacheLimit)
        _ = try c.renderImage(scene: lyric, width: 160, height: 90)
        #expect(c.rasterizationCount == base + 500, "the lyric was rasterised again")
    }

    @Test func theCacheNeverGivesUpMoreThanOneEntryPerInsert() throws {
        let c = try Compositor()
        var last = 0
        for i in 0..<(Compositor.lyricCacheLimit + 40) {
            _ = try c.renderImage(scene: oneLine("distinct \(i)"), width: 160, height: 90)
            #expect(c.textCacheCount >= last && c.textCacheCount <= Compositor.lyricCacheLimit, "count fell from \(last) to \(c.textCacheCount)")
            last = c.textCacheCount
        }
        #expect(c.textCacheCount == Compositor.lyricCacheLimit)
    }

    @Test func theLeastRecentlyUsedEntryGoesFirstNotTheOldest() throws {
        let c = try Compositor()
        let keep = oneLine("kept in use")
        _ = try c.renderImage(scene: keep, width: 160, height: 90)
        for i in 0..<(Compositor.lyricCacheLimit * 2) {
            _ = try c.renderImage(scene: oneLine("other \(i)"), width: 160, height: 90)
            _ = try c.renderImage(scene: keep, width: 160, height: 90)      // used every frame, so never the least recently used
        }
        let n = c.rasterizationCount
        _ = try c.renderImage(scene: keep, width: 160, height: 90)
        #expect(c.rasterizationCount == n)
    }

    // MARK: Ahead of Go Live

    @Test func theSelectedSlidesTextIsRasterisedAheadSoTheFirstLiveFrameDrawsNone() async throws {
        let unique = UUID().uuidString.prefix(8)
        let slide = SlideContent(primary: "Warm \(unique) morning light\nwarm \(unique) evening light", secondary: "\u{00C1}nh s\u{00E1}ng \(unique)")
        var roles: [(ScreenRole, Theme)] = [(.audience, .fullScreen), (.broadcast, .lowerThird)]
        roles.append((.audience, UI005hFixtures.userThemes[0]))
        var scenes: [SceneDescription] = []
        for (role, theme) in roles {
            scenes.append(SceneComposer.scene(for: role, state: UI005hFixtures.live(slide), theme: theme, look: .standard, props: []))
        }
        await TextWarmer.warm(scenes: scenes.map { ($0, 1920, 1080) })
        for s in scenes {
            let c = try Compositor()
            _ = try c.renderImage(scene: s, width: 1920, height: 1080)
            #expect(c.rasterizationCount == 0, "the first frame rasterised \(c.rasterizationCount) text bitmaps")
            #expect(c.fitComputationCount == 0)
        }
    }

    @Test func warmedTextDrawsTheSamePixelsAsTextRasterisedOnTheFirstFrame() async throws {
        let unique = UUID().uuidString.prefix(8)
        let slide = SlideContent(primary: "Same \(unique) pixels\nwarm or cold", secondary: "Gi\u{1ED1}ng nhau \(unique)")
        let scene = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(slide), theme: .fullScreen, look: .standard, props: [])
        let cold = try Compositor().renderImage(scene: scene, width: 1280, height: 720)
        await TextWarmer.warm(scenes: [(scene, 1280, 720)])
        let warm = try Compositor().renderImage(scene: scene, width: 1280, height: 720)
        #expect(cold.bgra == warm.bgra)
    }

    @Test func aWarmedSceneAtAnotherSizeIsNotMistakenForThisOne() async throws {
        let unique = UUID().uuidString.prefix(8)
        let scene = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(SlideContent(primary: "Size \(unique)")), theme: .fullScreen, look: .standard, props: [])
        await TextWarmer.warm(scenes: [(scene, 1280, 720)])
        let c = try Compositor()
        _ = try c.renderImage(scene: scene, width: 1920, height: 1080)
        #expect(c.rasterizationCount == 1)
    }
}
