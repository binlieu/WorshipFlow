// FIX-A (review findings R2, R7, R10, R16): one failing test per defect, written before the fix.
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Metal
import Domain
@testable import RenderEngine

private func writePNG(to url: URL, r: CGFloat, g: CGFloat, b: CGFloat, size: Int = 8) throws {
    let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))
}

private func tempPNG() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixa-\(UUID().uuidString).png") }

private func imageScene(_ path: String) -> SceneDescription {
    var scene = SceneDescription(backgroundColor: .clear, textLayers: [])
    scene.overlayImages = [ImageLayer(path: path, frame: .full, opacity: 1, contentMode: .fill)]
    return scene
}

private func texture(_ device: MTLDevice, width: Int = 16, height: Int = 16) throws -> MTLTexture {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .shared
    return try #require(device.makeTexture(descriptor: td))
}

private func read(_ t: MTLTexture, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    var px = [UInt8](repeating: 0, count: 4)
    t.getBytes(&px, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
    return (px[2], px[1], px[0], px[3])
}

private let encodingMarker = "wf.fixa.encoding"

/// Encodes one frame in live (background-loading) mode and waits for the GPU.
@discardableResult
private func liveFrame(_ compositor: Compositor, _ scene: SceneDescription, into target: MTLTexture) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let cb = try #require(compositor.makeCommandBuffer())
    Thread.current.threadDictionary[encodingMarker] = true        // stands in for "this is a render thread"
    defer { Thread.current.threadDictionary[encodingMarker] = nil }
    try compositor.encode(scene: scene, into: target, commandBuffer: cb, imageLoading: .background)
    cb.commit()
    cb.waitUntilCompleted()
    return read(target, x: target.width / 2, y: target.height / 2)
}

// MARK: R2

@Suite struct UnrenderableLayerTests {
    private let red = ColorRGBA(red: 1, green: 0, blue: 0, alpha: 1)
    private func normalShape() -> SceneObjectLayer {
        .shape(ShapeLayer(shape: .rectangle, fill: red, frame: NormalizedRect(x: 0, y: 0, width: 0.25, height: 0.25)))
    }
    private func brokenStyleLayer() -> TextLayer {
        var style = TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white)
        style.fontSize = 0                                      // cannot be laid out
        return TextLayer(text: "never drawn", style: style, frame: .full)
    }
    private func tallLayer(lines: Int = 150) -> TextLayer {
        let text = (0..<lines).map { _ in "Hg" }.joined(separator: "\n")
        return TextLayer(text: text, style: TextStyle(fontName: "Helvetica Neue", fontSize: 1000, color: .white), frame: .full)
    }

    @Test func zeroSizeTextLayerIsSkippedAndTheRestPresents() throws {
        var scene = SceneDescription(backgroundColor: .black, textLayers: [brokenStyleLayer()])
        scene.objectLayers = [normalShape()]
        let f = try Compositor().renderImage(scene: scene, width: 160, height: 90)
        let p = f.pixel(x: 4, y: 4)
        #expect(p.red == 255 && p.green == 0 && p.blue == 0)     // the normal layer is there
    }

    @Test func textBoxObjectThatCannotBeLaidOutIsSkippedToo() throws {
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.objectLayers = [.text(brokenStyleLayer()), normalShape()]
        let f = try Compositor().renderImage(scene: scene, width: 160, height: 90)
        #expect(f.pixel(x: 4, y: 4).red == 255)
    }

    @Test func textTallerThanTheLimitIsClippedNotThrown() throws {
        var scene = SceneDescription(backgroundColor: .black, textLayers: [tallLayer()])
        scene.objectLayers = [normalShape()]
        let f = try Compositor().renderImage(scene: scene, width: 320, height: 180)
        #expect(f.pixel(x: 2, y: 2).red == 255)                    // the rest of the scene presented
        let ink = f.bgra.enumerated().contains { $0.offset % 4 == 2 && $0.element > 0 && $0.offset / 4 % 320 > 40 }
        #expect(ink)                                               // and the text is drawn, clipped
    }

    @Test func rasteriserClipsAtTheLimitInsteadOfThrowing() throws {
        let tall = (0..<30).map { _ in "Hg" }.joined(separator: "\n")
        let r = try TextRasterizer().rasterize(tall, style: TextStyle(fontName: "Helvetica Neue", fontSize: 1000, color: .white),
                                               maxWidth: 800, alignment: .center)
        #expect(r.height == 16384)
        #expect(r.pixels.count == r.width * r.height * 4)
    }

    @Test func problemsAreReportedDeduplicatedAndClearedWhenTheyGoAway() throws {
        let compositor = try Compositor()
        var bad = SceneDescription(backgroundColor: .black, textLayers: [brokenStyleLayer()])
        bad.objectLayers = [.text(brokenStyleLayer())]          // the same problem twice in one frame
        for _ in 0..<3 { _ = try compositor.renderImage(scene: bad, width: 160, height: 90) }
        #expect(compositor.renderProblems.count == 1)
        #expect(compositor.renderProblems.first?.contains("never drawn") == true)

        var tall = SceneDescription(backgroundColor: .black, textLayers: [tallLayer()])
        tall.objectLayers = []
        _ = try compositor.renderImage(scene: tall, width: 320, height: 180)
        #expect(compositor.renderProblems.count == 1)           // clipping is reported as a problem of its own

        _ = try compositor.renderImage(scene: SceneDescription(backgroundColor: .black, textLayers: []), width: 160, height: 90)
        #expect(compositor.renderProblems.isEmpty)
    }
}

// MARK: R7

@Suite(.serialized) struct ImageReloadOffTheRenderThreadTests {
    /// A frame in steady state, long after the image loaded, must not ask the file system anything on the render thread.
    ///
    /// KI-060: this used to run frames for 2.6 s of wall-clock time and expect red to appear within that window, which
    /// a loaded machine can starve (the first load runs on a low-priority background thread). Nothing here depends on
    /// wall-clock time now: the first load is done up front, the compositor's clock is injected and moved by hand past
    /// three re-check intervals, and the test waits for each background re-check to be reported instead of sleeping.
    @Test(.timeLimit(.minutes(1))) func renderThreadNeverStatsTheFile() async throws {
        let url = tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 1, g: 0, b: 0)
        let compositor = try Compositor()
        let uptime = ManualUptime()
        compositor.uptime = { uptime.now }
        let target = try texture(compositor.device)
        let scene = imageScene(url.path)
        #expect(compositor.prepare(scene: scene).isEmpty)           // the first load, done here, so the frames below are steady state

        let log = ThreadLog()
        ImageDecoder.statProbe = { path in if path == url.path { log.note(Thread.current.threadDictionary[encodingMarker] != nil) } }
        ImageDecoder.backgroundLoadFinishedProbe = { path in if path == url.path { log.noteFinished() } }
        defer {
            ImageDecoder.statProbe = nil
            ImageDecoder.backgroundLoadFinishedProbe = nil
        }

        #expect(try liveFrame(compositor, scene, into: target).r > 240)      // red is on screen from the first frame
        for round in 1...3 {
            uptime.advance(by: 1.1)                                          // past one re-check interval
            try liveFrame(compositor, scene, into: target)                   // asks the background loader to re-check
            await log.waitForFinished(round)
            #expect(try liveFrame(compositor, scene, into: target).r > 240)  // takes the answer in; still red, no file system call here
        }
        #expect(log.callsOnRenderThread == 0)
        #expect(log.callsOffRenderThread == 3, "each of the three re-checks happened, on a thread that is not the render thread")
    }

    /// KI-060: like the test above, nothing waits on wall-clock time. The first load is done up front, the clock is moved
    /// by hand past a re-check interval, and the test waits for the background load to report that it finished.
    @Test(.timeLimit(.minutes(1))) func changedFileIsStillReloadedInTheBackground() async throws {
        let url = tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 1, g: 0, b: 0)
        let compositor = try Compositor()
        let uptime = ManualUptime()
        compositor.uptime = { uptime.now }
        let target = try texture(compositor.device)
        let scene = imageScene(url.path)
        #expect(compositor.prepare(scene: scene).isEmpty)
        #expect(try liveFrame(compositor, scene, into: target).r > 240)
        let log = ThreadLog()
        ImageDecoder.backgroundLoadFinishedProbe = { path in if path == url.path { log.noteFinished() } }
        defer { ImageDecoder.backgroundLoadFinishedProbe = nil }

        try writePNG(to: url, r: 0, g: 0, b: 1)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: url.path)
        uptime.advance(by: 1.1)
        try liveFrame(compositor, scene, into: target)                   // the re-check is asked for here and done in the background
        await log.waitForFinished(1)
        #expect(try liveFrame(compositor, scene, into: target).b > 240)   // the new picture is taken in
    }

    @Test(.timeLimit(.minutes(1))) func failedReloadKeepsThePreviousTextureAndReportsTheProblem() async throws {
        let url = tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 1, g: 0, b: 0)
        let compositor = try Compositor()
        let uptime = ManualUptime()
        compositor.uptime = { uptime.now }
        let target = try texture(compositor.device)
        let scene = imageScene(url.path)
        #expect(compositor.prepare(scene: scene).isEmpty)
        #expect(try liveFrame(compositor, scene, into: target).r > 240)
        let log = ThreadLog()
        ImageDecoder.backgroundLoadFinishedProbe = { path in if path == url.path { log.noteFinished() } }
        defer { ImageDecoder.backgroundLoadFinishedProbe = nil }

        try Data("this is not an image".utf8).write(to: url)       // a momentary read failure: same path, unreadable content
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: url.path)
        uptime.advance(by: 1.1)
        try liveFrame(compositor, scene, into: target)
        await log.waitForFinished(1)
        #expect(try liveFrame(compositor, scene, into: target).r > 240)     // the old picture is still on screen
        #expect(compositor.unavailableImagePaths.contains(url.path))        // and the problem is reported
    }
}

// MARK: R10

@Suite struct ImageSharingAndWarmingTests {
    /// Two screens showing the same file: the file is decoded once, and the second screen's first frame already has it.
    @Test func secondScreenReusesTheDecodeAndDrawsOnItsFirstFrame() async throws {
        let url = tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 0, g: 1, b: 0)
        let first = try Compositor()
        let t1 = try texture(first.device)
        let scene = imageScene(url.path)
        #expect(first.prepare(scene: scene).isEmpty)               // KI-060: the first screen's load is done up front, not raced against a timeout
        #expect(try liveFrame(first, scene, into: t1).g > 240)

        let second = try Compositor(device: first.device)
        let t2 = try texture(first.device)
        let firstFrame = try liveFrame(second, scene, into: t2)
        #expect(firstFrame.g > 240)                                 // no pop-in on the second screen
        #expect(first.imageDecodeCount + second.imageDecodeCount == 1)
    }

    @Test func warmedImageIsInTheVeryFirstFrame() async throws {
        let url = tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url, r: 0, g: 0, b: 1)
        let scene = imageScene(url.path)
        let unavailable = await ImageWarmer.warm(scene: scene)
        #expect(unavailable.isEmpty)
        let compositor = try Compositor()
        let target = try texture(compositor.device)
        #expect(try liveFrame(compositor, scene, into: target).b > 240)
    }

    @Test func warmingReportsAFileItCannotRead() async {
        let missing = "/nonexistent/wf-fixa-\(UUID().uuidString).png"
        let unavailable = await ImageWarmer.warm(scene: imageScene(missing))
        #expect(unavailable == [missing])
    }

    @Test func prepareSceneLoadsEveryImageKindIntoThisCompositor() throws {
        let a = tempPNG(), b = tempPNG(), c = tempPNG()
        defer { for u in [a, b, c] { try? FileManager.default.removeItem(at: u) } }
        try writePNG(to: a, r: 1, g: 0, b: 0)
        try writePNG(to: b, r: 0, g: 1, b: 0)
        try writePNG(to: c, r: 0, g: 0, b: 1)
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.backgroundImage = ImageLayer(path: a.path, frame: .full)
        scene.overlayImages = [ImageLayer(path: b.path, frame: .full)]
        scene.objectLayers = [.image(ImageLayer(path: c.path, frame: .full))]
        let compositor = try Compositor()
        let missing = compositor.prepare(scene: scene)
        #expect(missing.isEmpty)
        #expect(compositor.cachedImageCount == 3)
    }
}

// MARK: R16

@Suite struct ShaderSharingTests {
    @Test func openingManyCompositorsCompilesTheShadersOnce() throws {
        let coldStart = DispatchTime.now().uptimeNanoseconds
        let first = try Compositor()                                // may be the one that compiles
        let coldMs = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000
        print(String(format: "R16 TIMING first compositor in this process: %.1f ms (compiles only if nothing ran before it)", coldMs))
        let before = Compositor.shaderCompileCount
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<4 { _ = try Compositor(device: first.device) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print(String(format: "R16 TIMING four more compositors on a warm process: %.1f ms, shader compilations %d",
                     ms, Compositor.shaderCompileCount - before))
        #expect(Compositor.shaderCompileCount == before)
    }

    @Test func warmUpIsSafeToCallFromABackgroundThreadAndRepeatedly() async throws {
        await Task.detached { Compositor.warmUp() }.value
        await Task.detached { Compositor.warmUp() }.value
        let c = try Compositor()
        let f = try c.renderImage(scene: SceneDescription(backgroundColor: .white, textLayers: []), width: 4, height: 4)
        #expect(f.pixel(x: 1, y: 1).red == 255)
    }
}

/// Records, from any thread, whether each call came from the thread under test, and lets a test wait for background
/// loads to finish without sleeping.
private final class ThreadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var on = 0
    private var off = 0
    private var finishedCount = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    func note(_ same: Bool) { lock.lock(); if same { on += 1 } else { off += 1 }; lock.unlock() }
    var callsOnRenderThread: Int { lock.lock(); defer { lock.unlock() }; return on }
    var callsOffRenderThread: Int { lock.lock(); defer { lock.unlock() }; return off }

    func noteFinished() {
        lock.lock()
        finishedCount += 1
        let ready = waiters.filter { $0.count <= finishedCount }
        waiters.removeAll { $0.count <= finishedCount }
        lock.unlock()
        for w in ready { w.continuation.resume() }
    }

    func waitForFinished(_ count: Int) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finishedCount >= count { lock.unlock(); c.resume(); return }
            waiters.append((count, c))
            lock.unlock()
        }
    }
}

/// The compositor's clock, moved only by the test.
private final class ManualUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1000.0
    var now: Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(by seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
}
