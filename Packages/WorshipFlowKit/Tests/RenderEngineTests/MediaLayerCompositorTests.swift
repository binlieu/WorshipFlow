// MEDIA-002: background and foreground media in the compositor, with solid-colour textures standing in for frames.
import Testing
import Metal
import Domain
@testable import RenderEngine

@Suite struct MediaLayerCompositorTests {
    typealias Px = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

    /// A texture of one flat opaque colour (red, green, blue), optionally with a different colour in its left half.
    func solid(_ c: Compositor, _ rgb: (UInt8, UInt8, UInt8), width: Int = 16, height: Int = 16,
               leftHalf: (UInt8, UInt8, UInt8)? = nil) throws -> MTLTexture {
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

    func near(_ p: Px, _ r: Int, _ g: Int, _ b: Int, tolerance: Int = 3) -> Bool {
        abs(Int(p.red) - r) <= tolerance && abs(Int(p.green) - g) <= tolerance && abs(Int(p.blue) - b) <= tolerance && p.alpha == 255
    }

    let backgroundColour = ColorRGBA(red: 0, green: 0, blue: 1)       // blue, to tell it apart from the media
    var scene: SceneDescription { SceneDescription(backgroundColor: backgroundColour, textLayers: []) }

    @Test func backgroundMediaIsDrawnAspectFill() throws {
        let c = try Compositor()
        // A 2:1 picture, red on the left half and green on the right, into a square: the sides are cropped,
        // so the middle of the frame stays split and the corners are still the media's colours.
        let wide = try solid(c, (0, 255, 0), width: 32, height: 16, leftHalf: (255, 0, 0))
        var s = scene
        s.backgroundMedia = .image(UUID())
        let f = try c.renderImage(scene: s, width: 64, height: 64, backgroundMedia: wide)
        #expect(near(f.pixel(x: 2, y: 2), 255, 0, 0) && near(f.pixel(x: 61, y: 61), 0, 255, 0))
        #expect(near(f.pixel(x: 26, y: 32), 255, 0, 0) && near(f.pixel(x: 38, y: 32), 0, 255, 0))
    }

    @Test func aTextureIsIgnoredUnlessTheSceneNamesMedia() throws {
        let c = try Compositor()
        let tex = try solid(c, (255, 0, 0))
        let f = try c.renderImage(scene: scene, width: 32, height: 32, backgroundMedia: tex, foregroundMedia: tex)
        #expect(near(f.pixel(x: 16, y: 16), 0, 0, 255))
    }

    @Test func foregroundIsAspectFitOverBlack() throws {
        let c = try Compositor()
        let wide = try solid(c, (255, 0, 0), width: 32, height: 16)
        var s = scene
        s.foregroundMedia = .video(UUID())
        // 2:1 clip in a 64x64 frame: fills the width, 32 tall, centred; black bars above and below.
        let f = try c.renderImage(scene: s, width: 64, height: 64, foregroundMedia: wide)
        #expect(near(f.pixel(x: 32, y: 32), 255, 0, 0) && near(f.pixel(x: 2, y: 17), 255, 0, 0) && near(f.pixel(x: 61, y: 46), 255, 0, 0))
        #expect(near(f.pixel(x: 32, y: 5), 0, 0, 0) && near(f.pixel(x: 32, y: 58), 0, 0, 0))
    }

    @Test func foregroundCoversEverythingUnderneathButNotTextOrOverlays() throws {
        let c = try Compositor()
        let background = try solid(c, (0, 255, 0))
        let clip = try solid(c, (255, 0, 0), width: 16, height: 16)
        var s = scene
        s.backgroundMedia = .image(UUID())
        s.foregroundMedia = .video(UUID())
        s.textLayers = [TextLayer(text: "WWWW", style: TextStyle(fontName: "Helvetica Neue", fontSize: 400, color: .white),
                                  frame: .full, alignment: .center)]
        let f = try c.renderImage(scene: s, width: 128, height: 72, backgroundMedia: background, foregroundMedia: clip)
        // The 16x16 clip is a 72x72 square in the middle; the bars either side are black, not the green background.
        #expect(near(f.pixel(x: 3, y: 3), 0, 0, 0) && near(f.pixel(x: 124, y: 68), 0, 0, 0))
        var whites = 0
        for y in 0..<72 { for x in 0..<128 where f.pixel(x: x, y: y).green > 240 && f.pixel(x: x, y: y).red > 240 && f.pixel(x: x, y: y).blue > 240 { whites += 1 } }
        #expect(whites > 50)                                   // the text is drawn over the clip
    }

    @Test func foregroundIsOpaqueEvenOnATransparentBroadcastBackground() throws {
        let c = try Compositor()
        let clip = try solid(c, (255, 0, 0), width: 32, height: 16)
        var s = SceneDescription(backgroundColor: .clear, textLayers: [])
        s.foregroundMedia = .video(UUID())
        let f = try c.renderImage(scene: s, width: 64, height: 64, foregroundMedia: clip)
        #expect(f.pixel(x: 32, y: 4).alpha == 255 && f.pixel(x: 32, y: 32).alpha == 255)
        // Without the clip the same scene stays transparent.
        let none = try c.renderImage(scene: SceneDescription(backgroundColor: .clear, textLayers: []), width: 64, height: 64)
        #expect(none.pixel(x: 32, y: 32).alpha == 0)
    }

    @Test func mediaBackgroundReplacesTheSharedVideoAndSitsUnderTheThemeImage() throws {
        let c = try Compositor()
        let shared = try solid(c, (255, 255, 0))
        let media = try solid(c, (0, 255, 0))
        var s = scene
        s.showsVideo = true
        // Shared video alone, as before this slice.
        #expect(near(try c.renderImage(scene: s, width: 16, height: 16, video: shared).pixel(x: 8, y: 8), 255, 255, 0))
        // A chosen media background wins over it...
        s.backgroundMedia = .video(UUID())
        #expect(near(try c.renderImage(scene: s, width: 16, height: 16, video: shared, backgroundMedia: media).pixel(x: 8, y: 8), 0, 255, 0))
        // ...and when its frame is not ready, the background colour shows rather than the theme's loop.
        #expect(near(try c.renderImage(scene: s, width: 16, height: 16, video: shared).pixel(x: 8, y: 8), 0, 0, 255))
    }

    @Test func existingCallsAreUnchanged() throws {
        let c = try Compositor()
        let f = try c.renderImage(scene: scene, width: 8, height: 8)
        #expect(near(f.pixel(x: 4, y: 4), 0, 0, 255))
        #expect(Compositor.fillUV(sourceWidth: 200, sourceHeight: 100, width: 100, height: 100).size == SIMD2<Float>(0.5, 1))
    }
}
