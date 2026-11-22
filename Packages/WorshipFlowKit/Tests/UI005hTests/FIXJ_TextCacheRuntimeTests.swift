// FIX-J item 2 (UI-005h): the text cache gives up its least recently used entry one at a time, and the clock and timers of the stage cannot push
// the lyrics out of it. These use only what existed before the fix, so they could be run red first (the cache was emptied all at once at 64).
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct FIXJ_TextCacheRuntimeTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    func oneLine(_ text: String) -> SceneDescription {
        SceneDescription(backgroundColor: .black, textLayers: [
            TextLayer(text: text, style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), frame: .full)])
    }

    @Test func aFullCacheGivesUpOneEntryAtATimeNotAll() throws {
        let c = try Compositor()
        for i in 0..<64 { _ = try c.renderImage(scene: oneLine("tile number \(i)"), width: 160, height: 90) }      // 64 is the cache's size
        let full = c.rasterizationCount
        #expect(full == 64)
        _ = try c.renderImage(scene: oneLine("one more"), width: 160, height: 90)                                      // evicts the oldest only
        #expect(c.rasterizationCount == full + 1)
        for i in 1..<64 { _ = try c.renderImage(scene: oneLine("tile number \(i)"), width: 160, height: 90) }
        #expect(c.rasterizationCount == full + 1, "tiles 1...63 must still be cached; \(c.rasterizationCount - full - 1) were drawn again")
    }

    @Test func threeHundredTicksOfTheStageClockLeaveTheLyricsCached() throws {
        let c = try Compositor()
        func frame(_ i: Int) throws {
            let ctx = StageContext(state: UI005hFixtures.live(), now: 0, timeOfDayText: "9:\(String(format: "%02d", i / 60)):\(String(format: "%02d", i % 60))",
                                   timers: [], message: nil, notes: nil)
            _ = try c.renderImage(scene: StageComposer.scene(layout: .standard, context: ctx), width: 320, height: 180)
        }
        try frame(0)
        let first = c.rasterizationCount
        for i in 1..<300 { try frame(i) }
        // One raster per tick (the clock's new text) and none for the current slide, its second language, NEXT or the next line.
        #expect(c.rasterizationCount == first + 299, "\(c.rasterizationCount - first - 299) lyric rasters were drawn again")
    }
}
