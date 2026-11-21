// OUT-001 acceptance tests (ARCH-03, ARCH-20..23, G-6). Owned by the coordinator: do not modify.
import Testing
import CoreGraphics
import Domain
@testable import RenderEngine

@Suite struct TextRasterizerTests {
    let style = TextStyle(fontName: "Helvetica Neue", fontSize: 96,
                          color: ColorRGBA(red: 1, green: 1, blue: 1, alpha: 1),
                          outlineWidth: 4, outlineColor: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 1))

    /// ARCH-21: stacked Vietnamese diacritics must not be clipped by the bitmap.
    @Test func vietnameseStackedMarksAreNotClipped() throws {
        let raster = try TextRasterizer().rasterize("Ân điển lạ lùng thay — Ễ Ậ Ở Ỗ Ẵ ỷ ự",
                                                    style: style, maxWidth: 1728)
        #expect(raster.width > 0 && raster.height > 0)
        // Ink must sit strictly inside the bitmap, with at least one clear pixel on every side.
        #expect(raster.inkBounds.minX >= 1)
        #expect(raster.inkBounds.minY >= 1)
        #expect(raster.inkBounds.maxX <= CGFloat(raster.width - 1))
        #expect(raster.inkBounds.maxY <= CGFloat(raster.height - 1))
        #expect(raster.inkBounds.width > 100)
    }

    /// ARCH-21: a capital with two stacked marks is taller than a bare capital.
    @Test func stackedMarksAddHeight() throws {
        let plain = try TextRasterizer().rasterize("A", style: style, maxWidth: 1728)
        let stacked = try TextRasterizer().rasterize("Ẵ", style: style, maxWidth: 1728)
        #expect(stacked.inkBounds.height > plain.inkBounds.height)
    }

    /// ARCH-22: a font without the glyph falls back; it never draws nothing.
    @Test func missingGlyphFallsBack() throws {
        var s = style
        s.fontName = "Courier"   // falls back for many Vietnamese precomposed forms
        let raster = try TextRasterizer().rasterize("ễ ậ ở", style: s, maxWidth: 1728)
        #expect(raster.inkBounds.width > 20)
    }

    @Test func longTextWrapsWithinMaxWidth() throws {
        let long = String(repeating: "Amazing grace how sweet the sound ", count: 6)
        let raster = try TextRasterizer().rasterize(long, style: style, maxWidth: 800)
        #expect(raster.width <= 800)
        #expect(raster.lineCount > 1)
    }
}

@Suite struct CompositorTests {
    let white = ColorRGBA(red: 1, green: 1, blue: 1, alpha: 1)

    func textLayer(_ text: String, frame: NormalizedRect) -> TextLayer {
        TextLayer(text: text,
                  style: TextStyle(fontName: "Helvetica Neue", fontSize: 72, color: white,
                                   outlineWidth: 0, outlineColor: white),
                  frame: frame, alignment: .center)
    }

    /// Every shader compiles (ADR-0001).
    @Test func compositorInitialises() throws {
        _ = try Compositor()
    }

    @Test func solidBackgroundFillsFrame() throws {
        let scene = SceneDescription(backgroundColor: ColorRGBA(red: 1, green: 0, blue: 0, alpha: 1), textLayers: [])
        let frame = try Compositor().renderImage(scene: scene, width: 320, height: 180)
        #expect(frame.width == 320 && frame.height == 180)
        for (x, y) in [(0, 0), (319, 0), (0, 179), (319, 179), (160, 90)] {
            let p = frame.pixel(x: x, y: y)
            #expect(p.red == 255 && p.green == 0 && p.blue == 0 && p.alpha == 255)
        }
    }

    /// KEY groundwork: a transparent background stays transparent. Black is not transparency.
    @Test func clearBackgroundHasZeroAlpha() throws {
        let scene = SceneDescription(backgroundColor: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0),
                                     textLayers: [textLayer("Lower third", frame: NormalizedRect(x: 0.05, y: 0.75, width: 0.9, height: 0.2))])
        let frame = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        #expect(frame.pixel(x: 5, y: 5).alpha == 0)          // top-left: nothing drawn
        #expect(frame.pixel(x: 320, y: 60).alpha == 0)       // upper middle: nothing drawn
        // Somewhere inside the lower-third frame there is opaque text.
        var opaque = 0
        for y in 270..<342 { for x in 32..<608 where frame.pixel(x: x, y: y).alpha == 255 { opaque += 1 } }
        #expect(opaque > 50)
    }

    @Test func textStaysInsideItsFrame() throws {
        let scene = SceneDescription(backgroundColor: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0),
                                     textLayers: [textLayer("Ân điển lạ lùng thay", frame: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))])
        let frame = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        var outside = 0, inside = 0
        for y in 0..<360 { for x in 0..<640 where frame.pixel(x: x, y: y).alpha > 0 {
            if x >= 160 && x < 480 && y >= 90 && y < 270 { inside += 1 } else { outside += 1 }
        } }
        #expect(inside > 50)
        #expect(outside == 0)
    }

    /// SCRN-09 groundwork: the same content rendered with two frames lands in two places.
    @Test func sameTextDifferentPlacement() throws {
        let c = try Compositor()
        let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)
        let centred = try c.renderImage(scene: SceneDescription(backgroundColor: clear, textLayers: [textLayer("Grace", frame: NormalizedRect(x: 0, y: 0, width: 1, height: 0.5))]), width: 320, height: 180)
        let lower = try c.renderImage(scene: SceneDescription(backgroundColor: clear, textLayers: [textLayer("Grace", frame: NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5))]), width: 320, height: 180)
        func ink(_ f: RenderedFrame, rows: Range<Int>) -> Int {
            var n = 0
            for y in rows { for x in 0..<320 where f.pixel(x: x, y: y).alpha > 0 { n += 1 } }
            return n
        }
        #expect(ink(centred, rows: 0..<90) > 0 && ink(centred, rows: 90..<180) == 0)
        #expect(ink(lower, rows: 90..<180) > 0 && ink(lower, rows: 0..<90) == 0)
    }

    /// Output is premultiplied: no colour channel exceeds alpha.
    @Test func outputIsPremultiplied() throws {
        let scene = SceneDescription(backgroundColor: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0),
                                     textLayers: [textLayer("Edge", frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1))])
        let frame = try Compositor().renderImage(scene: scene, width: 320, height: 180)
        for y in 0..<180 { for x in 0..<320 {
            let p = frame.pixel(x: x, y: y)
            #expect(p.red <= p.alpha && p.green <= p.alpha && p.blue <= p.alpha)
        } }
    }
}
