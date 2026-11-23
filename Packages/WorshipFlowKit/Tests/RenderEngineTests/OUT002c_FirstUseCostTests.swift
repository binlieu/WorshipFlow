// OUT-002c (KI-007): what an output's compositor does the first time it draws a slide it has not drawn before.
// Counts only (Core Text rasterisations, fit computations); the time is printed for the report, never asserted.
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct OUT002c_FirstUseCostTests {
    /// Two lines like the soak's slides (English and Vietnamese with stacked marks), the lyric fit on, at 1080p.
    static func slide(_ tag: String) -> SceneDescription {
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 72, color: .white)
        return SceneDescription(backgroundColor: .black, textLayers: [
            TextLayer(text: "Amazing grace \(tag), how sweet the sound", style: style, frame: NormalizedRect(x: 0.05, y: 0.15, width: 0.9, height: 0.35), fitFloor: 40),
            TextLayer(text: "Ân điển lạ lùng \(tag), ễ ậ ở ỗ ẵ ỷ ự", style: style, frame: NormalizedRect(x: 0.05, y: 0.55, width: 0.9, height: 0.35), fitFloor: 40),
        ])
    }

    @Test func anUnseenSlideCostsCoreTextAndAFitOnItsFirstFrameOnly() throws {
        let c = try Compositor()
        let scene = Self.slide("cold-\(UUID().uuidString)")
        let t0 = Date()
        _ = try c.renderImage(scene: scene, width: 1920, height: 1080)
        let first = Date().timeIntervalSince(t0)
        #expect(c.rasterizationCount == 2, "the first frame rasterised both lines with Core Text")
        #expect(c.fitComputationCount == 1, "the first frame computed the fit")
        let (r, f) = (c.rasterizationCount, c.fitComputationCount)
        let t1 = Date()
        _ = try c.renderImage(scene: scene, width: 1920, height: 1080)
        let second = Date().timeIntervalSince(t1)
        #expect(c.rasterizationCount == r && c.fitComputationCount == f, "the second frame did none of it")
        print("OUT002c evidence: first frame \(Int(first * 1000)) ms (rasterisations \(r), fits \(f)); second frame \(Int(second * 1000)) ms")
    }

    @Test func warmedAheadOfTimeTheFirstFrameDoesNoCoreTextAndNoFit() throws {
        let scene = Self.slide("warm-\(UUID().uuidString)")
        TextWarmer.warmNow(scenes: [(scene, 1920, 1080)])
        let c = try Compositor()
        _ = try c.renderImage(scene: scene, width: 1920, height: 1080)
        #expect(c.rasterizationCount == 0)
        #expect(c.fitComputationCount == 0)
    }
}
