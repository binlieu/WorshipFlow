// OUT-003: image cache behaviour beyond the coordinator's acceptance tests: bounded size, reload when the file
// changes, and background loading that never blocks the live path.
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Domain
import Metal
@testable import RenderEngine

@Suite struct ImageCacheTests {
    func writePNG(to url: URL, r: CGFloat, g: CGFloat, b: CGFloat, size: Int = 8) throws {
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
    }
    func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("wf-cache-\(UUID().uuidString).png") }
    func overlay(_ path: String) -> SceneDescription {
        var scene = SceneDescription(backgroundColor: .clear, textLayers: [])
        scene.overlayImages = [ImageLayer(path: path, frame: .full, opacity: 1, contentMode: .fill)]
        return scene
    }

    @Test func cacheIsBounded() throws {
        let url = tempURL()
        try writePNG(to: url, r: 1, g: 0, b: 0)
        let compositor = try Compositor()
        // The same small file under many distinct paths (symlinks) fills the cache past its limit.
        var links: [String] = []
        for i in 0..<(Compositor.imageCacheLimit + 10) {
            let link = FileManager.default.temporaryDirectory.appendingPathComponent("wf-link-\(UUID().uuidString)-\(i).png")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            links.append(link.path)
        }
        defer { for l in links { try? FileManager.default.removeItem(atPath: l) }; try? FileManager.default.removeItem(at: url) }
        for l in links { _ = try compositor.renderImage(scene: overlay(l), width: 16, height: 16) }
        #expect(compositor.cachedImageCount <= Compositor.imageCacheLimit)
        #expect(compositor.imageDecodeCount == links.count)
    }

    @Test func changedFileIsReloaded() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 1, g: 0, b: 0)
        let compositor = try Compositor()
        #expect(try compositor.renderImage(scene: overlay(url.path), width: 16, height: 16).pixel(x: 8, y: 8).red > 240)
        try writePNG(to: url, r: 0, g: 0, b: 1)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        try await Task.sleep(for: .milliseconds(1200))     // the modification date is re-checked about once a second
        let p = try compositor.renderImage(scene: overlay(url.path), width: 16, height: 16).pixel(x: 8, y: 8)
        #expect(p.blue > 240 && p.red < 15)
        #expect(compositor.imageDecodeCount == 2)
    }

    @Test func missingFileAppearingLaterIsPickedUp() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let compositor = try Compositor()
        #expect(try compositor.renderImage(scene: overlay(url.path), width: 16, height: 16).pixel(x: 8, y: 8).alpha == 0)
        #expect(compositor.unavailableImagePaths.contains(url.path))
        try writePNG(to: url, r: 0, g: 1, b: 0)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(try compositor.renderImage(scene: overlay(url.path), width: 16, height: 16).pixel(x: 8, y: 8).green > 240)
        #expect(compositor.unavailableImagePaths.contains(url.path) == false)
    }

    /// The live path never waits for a decode: the first frames may omit the image, and it appears once decoded.
    @Test func backgroundLoadingEventuallyDraws() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 0, g: 1, b: 0)
        let compositor = try Compositor()
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let target = try #require(compositor.device.makeTexture(descriptor: td))
        var drawn = false
        for _ in 0..<100 where !drawn {
            let cb = try #require(compositor.makeCommandBuffer())
            try compositor.encode(scene: overlay(url.path), into: target, commandBuffer: cb, imageLoading: .background)
            cb.commit(); await cb.completed()
            var px = [UInt8](repeating: 0, count: 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: 64, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0) }
            drawn = px[1] > 240 && px[3] == 255
            if !drawn { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(drawn)
        #expect(compositor.imageDecodeCount == 1)
    }

    @Test func overlayOutsideTheTextClipStillDrawsAfterText() throws {
        // Text sets a scissor rectangle; overlays drawn afterwards must not inherit it.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 0, g: 1, b: 0)
        var scene = SceneDescription(backgroundColor: .black, textLayers: [
            TextLayer(text: "A", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white),
                      frame: NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.2))])
        scene.overlayImages = [ImageLayer(path: url.path, frame: NormalizedRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3), opacity: 1, contentMode: .fill)]
        let p = try Compositor().renderImage(scene: scene, width: 200, height: 200).pixel(x: 150, y: 150)
        #expect(p.green > 240 && p.red < 15)
    }
}
