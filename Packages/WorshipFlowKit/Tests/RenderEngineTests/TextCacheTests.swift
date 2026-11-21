// OUT-001 additional tests (implementer-owned): text texture cache and resolution-independent scaling.
import Testing
import Domain
@testable import RenderEngine

@Suite struct TextCacheTests {
    let style = TextStyle(fontName: "Helvetica Neue", fontSize: 72, color: .white)

    func scene(_ text: String) -> SceneDescription {
        SceneDescription(backgroundColor: .clear, textLayers: [
            TextLayer(text: text, style: style, frame: .full, alignment: .center)])
    }

    @Test func identicalFramesDoNotRerasterise() throws {
        let c = try Compositor()
        _ = try c.renderImage(scene: scene("Grace"), width: 640, height: 360)
        #expect(c.rasterizationCount == 1)
        _ = try c.renderImage(scene: scene("Grace"), width: 640, height: 360)
        _ = try c.renderImage(scene: scene("Grace"), width: 640, height: 360)
        #expect(c.rasterizationCount == 1)
        _ = try c.renderImage(scene: scene("Mercy"), width: 640, height: 360)
        #expect(c.rasterizationCount == 2)
    }

    /// Text is scaled against a 1080-line reference: the same style covers the same fraction of the frame at any size.
    @Test func textScalesWithOutputHeight() throws {
        let c = try Compositor()
        func inkHeightFraction(_ h: Int) throws -> Double {
            let f = try c.renderImage(scene: scene("Hg"), width: h * 16 / 9, height: h)
            var minY = h, maxY = -1
            for y in 0..<h { for x in 0..<(h * 16 / 9) where f.pixel(x: x, y: y).alpha > 0 { minY = min(minY, y); maxY = max(maxY, y) } }
            return Double(maxY - minY + 1) / Double(h)
        }
        let small = try inkHeightFraction(360)
        let large = try inkHeightFraction(1080)
        #expect(abs(small - large) < 0.01)
    }
}
