// OUT-003 acceptance tests: image layers in the compositor (MEDIA-08, PRES-01 groundwork).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Domain
@testable import RenderEngine

@Suite struct ImageLayerTests {
    /// Writes a solid-colour PNG and returns its path.
    func png(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-img-\(UUID().uuidString).png")
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url.path
    }
    let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    @Test func overlayImageDrawsInsideItsFrameOnly() throws {
        let path = try png(width: 64, height: 64, r: 0, g: 1, b: 0)
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.overlayImages = [ImageLayer(path: path, frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25), opacity: 1, contentMode: .fill)]
        let frame = try Compositor().renderImage(scene: scene, width: 400, height: 400)
        let inside = frame.pixel(x: 250, y: 250)
        #expect(inside.green > 240 && inside.red < 15 && inside.blue < 15 && inside.alpha == 255)
        #expect(frame.pixel(x: 100, y: 100).alpha == 0)
        #expect(frame.pixel(x: 350, y: 350).alpha == 0)
        #expect(frame.pixel(x: 190, y: 250).alpha == 0)
    }

    @Test func opacityIsAppliedAndStaysPremultiplied() throws {
        let path = try png(width: 32, height: 32, r: 1, g: 1, b: 1)
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.overlayImages = [ImageLayer(path: path, frame: .full, opacity: 0.5, contentMode: .fill)]
        let p = try Compositor().renderImage(scene: scene, width: 64, height: 64).pixel(x: 32, y: 32)
        #expect(abs(Int(p.alpha) - 128) <= 2)
        #expect(p.red <= p.alpha && abs(Int(p.red) - 128) <= 2)
    }

    /// Fit keeps the aspect ratio inside the frame; fill covers the whole frame.
    @Test func fitLetterboxesAndFillCovers() throws {
        let wide = try png(width: 200, height: 100, r: 1, g: 0, b: 0)
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.overlayImages = [ImageLayer(path: wide, frame: .full, opacity: 1, contentMode: .fit)]
        let fit = try Compositor().renderImage(scene: scene, width: 200, height: 200)
        #expect(fit.pixel(x: 100, y: 100).red > 240)        // middle band is drawn
        #expect(fit.pixel(x: 100, y: 20).alpha == 0)        // top band is empty
        #expect(fit.pixel(x: 100, y: 180).alpha == 0)       // bottom band is empty
        scene.overlayImages = [ImageLayer(path: wide, frame: .full, opacity: 1, contentMode: .fill)]
        let fill = try Compositor().renderImage(scene: scene, width: 200, height: 200)
        for (x, y) in [(100, 20), (100, 180), (5, 5), (195, 195)] { #expect(fill.pixel(x: x, y: y).red > 240) }
    }

    /// Order: background colour, background image, text, overlay images.
    @Test func backgroundImageIsUnderTextAndOverlayIsOver() throws {
        let blue = try png(width: 16, height: 16, r: 0, g: 0, b: 1)
        let green = try png(width: 16, height: 16, r: 0, g: 1, b: 0)
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 400, color: .white)
        var scene = SceneDescription(backgroundColor: .black,
                                     textLayers: [TextLayer(text: "█", style: style, frame: .full)])
        scene.backgroundImage = ImageLayer(path: blue, frame: .full, opacity: 1, contentMode: .fill)
        let under = try Compositor().renderImage(scene: scene, width: 320, height: 180)
        #expect(under.pixel(x: 2, y: 2).blue > 240 && under.pixel(x: 2, y: 2).red < 15)   // corner: background image
        let mid = under.pixel(x: 160, y: 90)
        #expect(mid.red > 240 && mid.green > 240 && mid.blue > 240)                        // centre: white text over it
        scene.overlayImages = [ImageLayer(path: green, frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), opacity: 1, contentMode: .fill)]
        let over = try Compositor().renderImage(scene: scene, width: 320, height: 180).pixel(x: 160, y: 90)
        #expect(over.green > 240 && over.red < 15)                                         // overlay covers the text
    }

    /// A missing or unreadable file never stops the frame; the rest of the scene still renders and the path is reported.
    @Test func missingImageDoesNotBreakTheFrame() throws {
        let compositor = try Compositor()
        var scene = SceneDescription(backgroundColor: ColorRGBA(red: 1, green: 0, blue: 0), textLayers: [])
        scene.overlayImages = [ImageLayer(path: "/nonexistent/logo.png", frame: .full, opacity: 1, contentMode: .fit)]
        let frame = try compositor.renderImage(scene: scene, width: 64, height: 64)
        #expect(frame.pixel(x: 32, y: 32).red == 255)
        #expect(compositor.unavailableImagePaths.contains("/nonexistent/logo.png"))
    }

    /// Image decoding happens once per file, not once per frame.
    @Test func imagesAreCached() throws {
        let path = try png(width: 64, height: 64, r: 0, g: 1, b: 0)
        let compositor = try Compositor()
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.overlayImages = [ImageLayer(path: path, frame: .full, opacity: 1, contentMode: .fill)]
        for _ in 0..<5 { _ = try compositor.renderImage(scene: scene, width: 64, height: 64) }
        #expect(compositor.imageDecodeCount == 1)
    }
}
