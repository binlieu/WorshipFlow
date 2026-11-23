// UI-007c (SLIDE): drawing a text box with "Shrink to fit box" (its own factor, the lyric floor) and a video object (a clip's frame inside its own
// frame). Solid-colour textures stand in for decoded frames. The digest test next to this one proves slides without the new values render as before.
import Testing
import Metal
import Domain
@testable import RenderEngine

@Suite struct UI007c_ObjectRenderTests {
    typealias Px = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    private let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NormalizedRect { NormalizedRect(x: x, y: y, width: w, height: h) }

    // MARK: Fit

    private func words(_ text: String, fit: Bool, frame: NormalizedRect, size: Double = 120) -> SceneObjectLayer {
        .text(TextLayer(text: text, style: TextStyle(fontName: "Helvetica Neue", fontSize: size, color: .white), frame: frame,
                        alignment: .center, verticalAlignment: .center, fitFloor: fit ? Theme.fitFloor : nil))
    }

    /// The rows (top, bottom) and columns (left, right) where something is drawn, or nil.
    private func ink(_ f: RenderedFrame) -> (top: Int, bottom: Int, left: Int, right: Int)? {
        var top = Int.max, bottom = -1, left = Int.max, right = -1
        for y in 0..<f.height {
            for x in 0..<f.width where f.bgra[(y * f.width + x) * 4 + 3] > 8 {
                top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
            }
        }
        return bottom < 0 ? nil : (top, bottom, left, right)
    }

    private let long = "Wide words that need to wrap over several lines and shrink"
    private let box = NormalizedRect(x: 0.25, y: 0.4, width: 0.5, height: 0.25)       // 480 x 135 at 960 x 540

    @Test func aFittedTextBoxShrinksInsideItsFrameWhereTheUnfittedOneIsCutAtTheEdge() throws {
        let c = try Compositor()
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [words(long, fit: false, frame: box)]
        let cut = try #require(ink(try c.renderImage(scene: scene, width: 960, height: 540)))
        scene.objectLayers = [words(long, fit: true, frame: box)]
        let fitted = try #require(ink(try c.renderImage(scene: scene, width: 960, height: 540)))
        let frameTop = 216, frameBottom = 351, frameLeft = 240, frameRight = 719
        #expect(cut.top >= frameTop && cut.bottom <= frameBottom, "unfitted words are cut at the frame, not spilling out of it")
        #expect(fitted.top >= frameTop && fitted.bottom <= frameBottom && fitted.left >= frameLeft && fitted.right <= frameRight)
        #expect(fitted.bottom - fitted.top < cut.bottom - cut.top, "the fitted words are smaller")
        #expect(fitted.top > frameTop && fitted.bottom < frameBottom, "and sit inside it, not against its edges")
    }

    @Test func wordsThatAlreadyFitAreDrawnExactlyAsWithoutFit() throws {
        let c = try Compositor()
        let small = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.5)
        var plain = SceneDescription(backgroundColor: .black, textLayers: [])
        plain.objectLayers = [words("Short", fit: false, frame: small, size: 80)]
        var fitted = plain
        fitted.objectLayers = [words("Short", fit: true, frame: small, size: 80)]
        #expect(try c.renderImage(scene: plain, width: 640, height: 360).bgra == (try c.renderImage(scene: fitted, width: 640, height: 360).bgra))
    }

    @Test func theFitIsMeasuredOnceAndKeptNotOncePerFrame() throws {
        let c = try Compositor()
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [words(long, fit: true, frame: box)]
        for _ in 0..<5 { _ = try c.renderImage(scene: scene, width: 960, height: 540) }
        #expect(c.objectFitComputationCount == 1)
        scene.objectLayers = [words(long + " and more", fit: true, frame: box)]
        _ = try c.renderImage(scene: scene, width: 960, height: 540)
        #expect(c.objectFitComputationCount == 2)
        scene.objectLayers = [words(long, fit: false, frame: box)]                  // no fit asked: nothing measured
        _ = try c.renderImage(scene: scene, width: 960, height: 540)
        #expect(c.objectFitComputationCount == 2)
    }

    @Test func theFloorHoldsAndWordsThatCannotFitEvenThereAreCutAtTheFrame() throws {
        let c = try Compositor()
        let tiny = NormalizedRect(x: 0.3, y: 0.4, width: 0.2, height: 0.06)           // 192 x 32 at 960 x 540: far too small for 56 pt words
        var scene = SceneDescription(backgroundColor: clear, textLayers: [])
        scene.objectLayers = [words(long, fit: true, frame: tiny)]
        let f = try c.renderImage(scene: scene, width: 960, height: 540)
        let found = try #require(ink(f))
        #expect(found.top >= 216 && found.bottom <= 216 + 33 && found.left >= 288 && found.right <= 288 + 193)      // cut at its frame, not spilling out
        // Never smaller than the floor: the same words at the floor's size (56 of 120) draw the same ink as the fitted ones.
        var atFloor = SceneDescription(backgroundColor: clear, textLayers: [])
        atFloor.objectLayers = [words(long, fit: false, frame: tiny, size: Theme.fitFloor)]
        #expect(f.bgra == (try c.renderImage(scene: atFloor, width: 960, height: 540).bgra))
    }

    @Test func aTextBoxFitsAloneAndDoesNotChangeTheLyricsFit() throws {
        let c = try Compositor()
        let lyricStyle = TextStyle(fontName: "Helvetica Neue", fontSize: 80, color: .white)
        let lyric = TextLayer(text: "Short lyric", style: lyricStyle, frame: rect(0.1, 0.05, 0.8, 0.2), fitFloor: Theme.fitFloor)
        let onlyLyric = SceneDescription(backgroundColor: clear, textLayers: [lyric])
        var both = onlyLyric
        both.objectLayers = [words(long, fit: true, frame: box)]
        let a = try c.renderImage(scene: onlyLyric, width: 960, height: 540)
        let b = try c.renderImage(scene: both, width: 960, height: 540)
        // The lyric rows (the top fifth) are identical with and without the shrunk text box below them.
        #expect(Array(a.bgra[0..<(960 * 4 * 135)]) == Array(b.bgra[0..<(960 * 4 * 135)]))
    }

    // MARK: Video object

    /// A texture of one flat opaque colour, optionally another colour in its left half.
    private func solid(_ c: Compositor, _ rgb: (UInt8, UInt8, UInt8), width: Int = 16, height: Int = 16, leftHalf: (UInt8, UInt8, UInt8)? = nil) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = .shaderRead
        td.storageMode = .shared
        let tex = try #require(c.device.makeTexture(descriptor: td))
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = (x < width / 2 ? leftHalf : nil) ?? rgb
                let i = (y * width + x) * 4
                bytes[i] = v.2; bytes[i + 1] = v.1; bytes[i + 2] = v.0
            }
        }
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        return tex
    }

    private func near(_ p: Px, _ r: Int, _ g: Int, _ b: Int, tolerance: Int = 3) -> Bool {
        abs(Int(p.red) - r) <= tolerance && abs(Int(p.green) - g) <= tolerance && abs(Int(p.blue) - b) <= tolerance && p.alpha == 255
    }

    private let blue = ColorRGBA(red: 0, green: 0, blue: 1)
    private func scene(_ layers: [SceneObjectLayer]) -> SceneDescription {
        var s = SceneDescription(backgroundColor: blue, textLayers: [])
        s.objectLayers = layers
        return s
    }

    @Test func aClipsFrameFillsItsObjectsFrameCroppedAndNothingOutsideIt() throws {
        let c = try Compositor()
        let id = UUID()
        // A 2:1 frame, red left and green right, into a square object frame (x 16...48 of 64): the sides are cropped, the middle stays split.
        let wide = try solid(c, (0, 255, 0), width: 32, height: 16, leftHalf: (255, 0, 0))
        let f = try c.renderImage(scene: scene([.video(VideoLayer(mediaID: id, frame: rect(0.25, 0.25, 0.5, 0.5)))]), width: 64, height: 64, objectMedia: [id: wide])
        #expect(near(f.pixel(x: 18, y: 32), 255, 0, 0) && near(f.pixel(x: 45, y: 32), 0, 255, 0))
        #expect(near(f.pixel(x: 30, y: 32), 255, 0, 0) && near(f.pixel(x: 34, y: 32), 0, 255, 0))
        #expect(near(f.pixel(x: 8, y: 32), 0, 0, 255) && near(f.pixel(x: 56, y: 32), 0, 0, 255), "outside the frame is the slide")
        #expect(near(f.pixel(x: 32, y: 8), 0, 0, 255) && near(f.pixel(x: 32, y: 56), 0, 0, 255))
        #expect(near(f.pixel(x: 16, y: 16), 255, 0, 0) && near(f.pixel(x: 47, y: 47), 0, 255, 0), "the corners of the frame are the clip's")
    }

    @Test func theObjectsOpacityBlendsTheClipWithWhatIsBehindIt() throws {
        let c = try Compositor()
        let id = UUID()
        let red = try solid(c, (255, 0, 0))
        let f = try c.renderImage(scene: scene([.video(VideoLayer(mediaID: id, frame: .full, opacity: 0.5))]), width: 32, height: 32, objectMedia: [id: red])
        let p = f.pixel(x: 16, y: 16)
        #expect(abs(Int(p.red) - 128) <= 3 && abs(Int(p.blue) - 128) <= 3 && p.green <= 3)
    }

    @Test func aClipWithNoFrameYetDrawsNothingAndAFrameForAnotherClipIsNotUsed() throws {
        let c = try Compositor()
        let id = UUID()
        let green = try solid(c, (0, 255, 0))
        let layer = SceneObjectLayer.video(VideoLayer(mediaID: id, frame: .full))
        #expect(near(try c.renderImage(scene: scene([layer]), width: 16, height: 16).pixel(x: 8, y: 8), 0, 0, 255))
        #expect(near(try c.renderImage(scene: scene([layer]), width: 16, height: 16, objectMedia: [UUID(): green]).pixel(x: 8, y: 8), 0, 0, 255))
        #expect(near(try c.renderImage(scene: scene([layer]), width: 16, height: 16, objectMedia: [id: green]).pixel(x: 8, y: 8), 0, 255, 0))
    }

    @Test func twoClipsEachFillTheirOwnFrameAndTheStackOrderHolds() throws {
        let c = try Compositor()
        let a = UUID(), b = UUID()
        let red = try solid(c, (255, 0, 0)), green = try solid(c, (0, 255, 0))
        let layers: [SceneObjectLayer] = [
            .video(VideoLayer(mediaID: a, frame: rect(0, 0, 0.5, 1))),
            .video(VideoLayer(mediaID: b, frame: rect(0.5, 0, 0.5, 1))),
            .shape(ShapeLayer(shape: .rectangle, fill: .white, frame: rect(0.4, 0.4, 0.2, 0.2))),      // over both clips
        ]
        let f = try c.renderImage(scene: scene(layers), width: 64, height: 64, objectMedia: [a: red, b: green])
        #expect(near(f.pixel(x: 8, y: 8), 255, 0, 0) && near(f.pixel(x: 56, y: 8), 0, 255, 0))
        #expect(near(f.pixel(x: 32, y: 32), 255, 255, 255))
        let under = scene([.shape(ShapeLayer(shape: .rectangle, fill: .white, frame: .full)), .video(VideoLayer(mediaID: a, frame: rect(0, 0, 0.5, 1)))])
        let g = try c.renderImage(scene: under, width: 64, height: 64, objectMedia: [a: red])
        #expect(near(g.pixel(x: 8, y: 8), 255, 0, 0) && near(g.pixel(x: 56, y: 8), 255, 255, 255), "a clip over a shape covers it")
    }

    @Test func aDegenerateVideoFrameOrOpacityDrawsNothingAndDoesNotCrash() throws {
        let c = try Compositor()
        let id = UUID()
        let red = try solid(c, (255, 0, 0))
        let layers: [SceneObjectLayer] = [
            .video(VideoLayer(mediaID: id, frame: rect(0.5, 0.5, 0, 0))),
            .video(VideoLayer(mediaID: id, frame: .full, opacity: 0)),
            .video(VideoLayer(mediaID: id, frame: rect(5, 5, 1, 1))),            // off the slide
        ]
        let f = try c.renderImage(scene: scene(layers), width: 16, height: 16, objectMedia: [id: red])
        #expect(near(f.pixel(x: 8, y: 8), 0, 0, 255))
    }
}
