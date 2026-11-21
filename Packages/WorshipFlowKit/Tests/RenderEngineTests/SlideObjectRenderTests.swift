// SLIDE-001a: object drawing beyond the coordinator's acceptance tests: caches, text-box opacity, shadows, draw order.
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Domain
@testable import RenderEngine

@Suite struct SlideObjectRenderTests {
    private let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NormalizedRect { NormalizedRect(x: x, y: y, width: w, height: h) }
    private func fillLayer(_ color: ColorRGBA, _ frame: NormalizedRect, opacity: Double = 1) -> SceneObjectLayer {
        .shape(ShapeLayer(shape: .rectangle, fill: color, frame: frame, opacity: opacity))
    }

    @Test func shapeBitmapsAreCachedAndBounded() throws {
        let compositor = try Compositor()
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [fillLayer(.white, .full)]
        _ = try compositor.renderImage(scene: scene, width: 64, height: 64)
        _ = try compositor.renderImage(scene: scene, width: 64, height: 64)
        #expect(compositor.shapeRasterizationCount == 1)          // second frame reused the bitmap
        for i in 0..<(Compositor.shapeCacheLimit + 20) {            // many distinct sizes
            scene.objectLayers = [fillLayer(.white, rect(0, 0, 0.1 + Double(i) * 0.005, 0.5))]
            _ = try compositor.renderImage(scene: scene, width: 200, height: 100)
        }
        #expect(compositor.cachedShapeCount <= Compositor.shapeCacheLimit)
    }

    @Test func degenerateShapesDrawNothingAndDoNotCrash() throws {
        let compositor = try Compositor()
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [
            .shape(ShapeLayer(shape: .rectangle, fill: nil, frame: .full)),                                     // nothing to draw
            .shape(ShapeLayer(shape: .rectangle, fill: .white, frame: rect(0.5, 0.5, 0, 0))),                  // empty frame
            .shape(ShapeLayer(shape: .rectangle, fill: .white, frame: .full, opacity: 0)),                      // invisible
            .shape(ShapeLayer(shape: .ellipse, fill: .white, frame: rect(0, 0, 100_000, 100_000))),             // absurdly large
            .text(TextLayer(text: "  ", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), frame: .full)),
        ]
        let f = try compositor.renderImage(scene: scene, width: 50, height: 50)
        #expect(f.bgra.allSatisfy { $0 == 0 })
    }

    @Test func textBoxOpacityAppliesToTheWholeText() throws {
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 600, color: .white)
        func peak(_ opacity: Double) throws -> UInt8 {
            var scene = SceneDescription(backgroundColor: clear, textLayers: [])
            scene.objectLayers = [.text(TextLayer(text: "█", style: style, frame: .full, opacity: opacity))]
            let f = try Compositor().renderImage(scene: scene, width: 200, height: 200)
            return f.bgra.enumerated().filter { $0.offset % 4 == 3 }.map(\.element).max() ?? 0
        }
        #expect(try peak(1) >= 250)
        let half = try peak(0.5)
        #expect(half >= 120 && half <= 135)
    }

    @Test func shadowIsPartOfTheTextCacheKey() throws {
        let compositor = try Compositor()
        let plain = TextStyle(fontName: "Helvetica Neue", fontSize: 80, color: .white)
        var shadowed = plain
        shadowed.shadow = TextShadow(color: .black, offsetX: 4, offsetY: 4, blur: 2)
        func render(_ style: TextStyle) throws { _ = try compositor.renderImage(scene: SceneDescription(backgroundColor: clear, textLayers: [TextLayer(text: "Grace", style: style, frame: .full)]), width: 400, height: 200) }
        try render(plain); try render(shadowed)
        #expect(compositor.rasterizationCount == 2)
        try render(plain); try render(shadowed)
        #expect(compositor.rasterizationCount == 2)
    }

    /// Positive offsets move the shadow right and down the screen; a blurred shadow stays inside the bitmap.
    @Test func shadowDirectionAndBlurAreInsideTheBitmap() throws {
        var style = TextStyle(fontName: "Helvetica Neue", fontSize: 120, color: .white)
        style.shadow = TextShadow(color: wf(1, 0, 0), offsetX: 20, offsetY: 20, blur: 0)
        let r = try TextRasterizer().rasterize("I", style: style, maxWidth: 600)
        func redInk(_ x: Int, _ y: Int) -> Bool { let i = (y * r.width + x) * 4; return r.pixels[i + 2] > 200 && r.pixels[i + 1] < 60 }
        var right = 0, left = 0, below = 0, above = 0
        let cx = Int(r.inkBounds.midX), cy = Int(r.inkBounds.midY)
        for y in 0..<r.height { for x in 0..<r.width where redInk(x, y) {
            if x > cx { right += 1 } else { left += 1 }
            if y > cy { below += 1 } else { above += 1 }
        } }
        #expect(right > left && below > above)
        style.shadow = TextShadow(color: .black, offsetX: -30, offsetY: -30, blur: 25)
        let blurred = try TextRasterizer().rasterize("Ân điển", style: style, maxWidth: 1728)
        #expect(blurred.inkBounds.minX >= 1 && blurred.inkBounds.minY >= 1)
        #expect(blurred.inkBounds.maxX <= CGFloat(blurred.width - 1) && blurred.inkBounds.maxY <= CGFloat(blurred.height - 1))
    }

    @Test func imageObjectsDrawBetweenShapesAndLyricText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-obj-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [fillLayer(wf(1, 0, 0), .full),
                              .image(ImageLayer(path: url.path, frame: rect(0, 0, 0.5, 1), opacity: 1, contentMode: .fill)),
                              fillLayer(wf(0, 1, 0), rect(0, 0, 0.5, 0.25))]
        let f = try Compositor().renderImage(scene: scene, width: 100, height: 100)
        #expect(f.pixel(x: 80, y: 50).red == 255)                                   // red alone on the right
        #expect(f.pixel(x: 20, y: 60).blue == 255 && f.pixel(x: 20, y: 60).red == 0)   // image over red
        #expect(f.pixel(x: 20, y: 10).green == 255 && f.pixel(x: 20, y: 10).blue == 0)  // shape above the image
    }

    private func wf(_ r: Double, _ g: Double, _ b: Double) -> ColorRGBA { ColorRGBA(red: r, green: g, blue: b) }
}
