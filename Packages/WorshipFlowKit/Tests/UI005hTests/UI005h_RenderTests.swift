// UI-005h items 2 and 3 in the compositor: the audience gradient, and the lower third's plate with accent bar, and the geometry the
// compositor gives the text, the plate and the bar at 1920 x 1080 (design against app).
import Testing
import Foundation
import Metal
import Domain
@testable import RenderEngine

@Suite struct UI005h_RenderTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    // MARK: Gradient

    func gradientFrame(video: MTLTexture? = nil, showsVideo: Bool = false, compositor: Compositor) throws -> RenderedFrame {
        let scene = SceneDescription(backgroundColor: Theme.mediaFallbackColor, showsVideo: showsVideo, textLayers: [],
                                     backgroundGradient: Theme.fullScreen.mediaFallback)
        return try compositor.renderImage(scene: scene, width: 960, height: 540, video: video)
    }
    func close(_ p: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8), _ r: Int, _ g: Int, _ b: Int, _ tol: Int = 3) -> Bool {
        abs(Int(p.red) - r) <= tol && abs(Int(p.green) - g) <= tol && abs(Int(p.blue) - b) <= tol && p.alpha == 255
    }

    @Test func theRadialGradientHasTheDesignsStopsAtTheDesignsRadii() throws {
        let f = try gradientFrame(compositor: try Compositor())
        // Centre (80 %, 90 %): the first stop. Half a radius away along the width (0.55 of the width): the middle stop. Past the radius: the last.
        let cx = 0.8 * 960.0, cy = 0.9 * 540.0
        #expect(close(f.pixel(x: Int(cx), y: Int(cy)), 0x2d, 0x7d, 0x6c))
        #expect(close(f.pixel(x: Int(cx - 0.55 * 960), y: Int(cy)), 0x12, 0x3b, 0x52))             // 0.5 * 110 % of the width to the left
        #expect(close(f.pixel(x: Int(cx), y: Int(cy - 0.5 * 540)), 0x12, 0x3b, 0x52))             // 0.5 * 100 % of the height up
        #expect(close(f.pixel(x: 0, y: 0), 0x05, 0x0f, 0x1c, 2))                                    // normalised radius 1.16: the last stop
        // A quarter of the way to the middle stop is the straight blend in sRGB, as a browser draws it.
        #expect(close(f.pixel(x: Int(cx - 0.275 * 960), y: Int(cy)), (0x2d + 0x12) / 2, (0x7d + 0x3b) / 2, (0x6c + 0x52) / 2, 4))
        #expect(f.pixel(x: 400, y: 300).alpha == 255)
    }

    @Test func theLoopStillCoversTheGradientWhereItPlays() throws {
        let c = try Compositor()
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        let red = try #require(c.device.makeTexture(descriptor: td))
        let bytes: [UInt8] = (0..<16).flatMap { _ in [UInt8(0), 0, 255, 255] }      // B, G, R, A: opaque red
        red.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 16)
        let f = try gradientFrame(video: red, showsVideo: true, compositor: c)
        #expect(close(f.pixel(x: 770, y: 480), 255, 0, 0, 1) && close(f.pixel(x: 5, y: 5), 255, 0, 0, 1))
    }

    @Test func noGradientGivesTheFlatColourItAlwaysDid() throws {
        let scene = SceneDescription(backgroundColor: Theme.mediaFallbackColor, showsVideo: false, textLayers: [])
        let f = try Compositor().renderImage(scene: scene, width: 320, height: 180)
        let want = Theme.mediaFallbackColor
        #expect(close(f.pixel(x: 10, y: 10), Int((want.red * 255).rounded()), Int((want.green * 255).rounded()), Int((want.blue * 255).rounded()), 1) && f.pixel(x: 300, y: 170) == f.pixel(x: 10, y: 10))
    }

    // MARK: Geometry, design against app (1920 x 1080; the design's numbers are from scripts/design-rects on the mockup)

    func report(_ role: ScreenRole, theme: Theme, slide: SlideContent, extra: (inout SceneDescription) -> Void = { _ in }) throws -> (SceneLayoutReport, SceneDescription) {
        var scene = SceneComposer.scene(for: role, state: UI005hFixtures.live(slide), theme: theme, look: .standard, props: [])
        extra(&scene)
        return (try Compositor().layoutReport(scene: scene, width: 1920, height: 1080), scene)
    }
    func box(_ b: LayoutBox, _ x: Double, _ y: Double, _ w: Double?, _ h: Double?, _ tol: Double = 1.0) -> Bool {
        abs(b.x - x) <= tol && abs(b.y - y) <= tol && (w.map { abs(b.width - $0) <= tol } ?? true) && (h.map { abs(b.height - $0) <= tol } ?? true)
    }

    @Test func theAudienceTextBoxesMatchTheDesign() throws {
        let (r, _) = try report(.audience, theme: .fullScreen, slide: UI005hFixtures.sampleSlide)
        try #require(r.texts.count == 2)
        let p = r.texts[0], s = r.texts[1]
        #expect(box(p.box, 391.9, 262.2, 1136.2, 285.7), "primary \(p.box)")
        #expect(box(s.box, 631.9, 613.1, 656.1, 204.7), "secondary \(s.box)")
        #expect(abs(p.fontSize - 119.04) < 0.01 && p.weight == 600)
        #expect(abs(s.fontSize - 78.72) < 0.01 && s.weight == 500)
    }

    @Test func theLowerThirdPlateBarAndTextMatchTheDesign() throws {
        let (r, _) = try report(.broadcast, theme: .lowerThird, slide: UI005hFixtures.lowerThirdSlide)
        let plate = try #require(r.plate), bar = try #require(r.bar)
        try #require(r.texts.count == 2)
        #expect(box(plate, 115.2, 773.8, 1689.6, 210.3), "plate \(plate)")
        #expect(box(bar, 161.3, 804.5, 11.5, 148.9), "bar \(bar)")
        #expect(box(r.texts[0].box, 211.2, 804.5, 1239.8, 84.0), "primary \(r.texts[0].box)")
        #expect(box(r.texts[1].box, 211.2, 888.5, nil, 64.9), "secondary \(r.texts[1].box)")
        let (first, second) = (r.texts[0], r.texts[1])
        #expect(abs(first.fontSize - 67.2) < 0.01 && first.weight == 600)
        #expect(abs(second.fontSize - 49.92) < 0.01 && second.weight == 500)
    }

    @Test func thePlateGrowsUpwardsWithItsTextAndKeepsItsBottomMargin() throws {
        let (two, _) = try report(.broadcast, theme: .lowerThird, slide: UI005hFixtures.lowerThirdSlide)
        let (one, _) = try report(.broadcast, theme: .lowerThird, slide: SlideContent(primary: "Only English"))
        let (long, _) = try report(.broadcast, theme: .lowerThird, slide: SlideContent(primary: String(repeating: "Amazing grace how sweet the sound ", count: 8), secondary: "Ng\u{1EAF}n"))
        let a = try #require(two.plate), b = try #require(one.plate), c = try #require(long.plate)
        #expect(abs((a.y + a.height) - 984) < 0.01)
        #expect(abs((b.y + b.height) - 984) < 0.01)
        #expect(abs((c.y + c.height) - 984) < 0.01)
        #expect(b.height < a.height && c.height > a.height)
        #expect(abs(b.height - (30.72 * 2 + 84)) < 0.5)
        #expect(a.x == b.x && a.width == b.width && a.x == c.x)
        let longBar = try #require(long.bar), twoBar = try #require(two.bar)
        #expect(longBar.height > twoBar.height)
    }

    @Test func theStageBoxesMatchTheDesign() throws {
        let timer = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 632))
        let ctx = StageContext(state: UI005hFixtures.live(), now: 0, timeOfDayText: "9:14", timers: [timer], message: "Repeat chorus \u{00D7}2, then bridge", notes: nil)
        let scene = StageComposer.scene(layout: .standard, context: ctx)
        let r = try Compositor().layoutReport(scene: scene, width: 1920, height: 1080)
        var t: [String: TextLayoutItem] = [:]
        for item in r.texts { t[item.text] = item }
        let currentText = "My chains are gone\nI\u{2019}ve been set free"
        let secondText = "Xi\u{1EC1}ng x\u{00ED}ch \u{0111}\u{00E3} tan \u{00B7} T\u{00F4}i \u{0111}\u{01B0}\u{1EE3}c t\u{1EF1} do"
        let current = try #require(t[currentText]), second = try #require(t[secondText])
        #expect(box(current.box, 76.8, 76.8, nil, 268.1), "current \(current.box)")
        // The mockup's second-language line box is 16 px tall (the page's fixed line height) around y = 377.6; the picture draws the line 12 px
        // lower, which is where this normal 1.3 line box is centred.
        #expect(abs(second.box.y + second.box.height / 2 - 389.6) < 1.0, "second \(second.box)")
        let label = try #require(t["NEXT"]), next = try #require(t["My God, my Savior has ransomed me"])
        #expect(box(label.box, 76.8, 796, nil, 34.44), "label \(label.box)")
        #expect(box(next.box, 76.8, 837.5, 1222.0, 80.55), "next \(next.box)")
        let clock = try #require(t["9:14"]), timerBox = try #require(t["10:32"])
        #expect(abs(clock.box.x + clock.box.width - 1843.2) < 1 && abs(clock.box.y - 64.8) < 1 && abs(clock.box.height - 81.25) < 1, "clock \(clock.box)")
        #expect(abs(timerBox.box.x + timerBox.box.width - 1843.2) < 1 && abs(timerBox.box.y - 163.7) < 1 && abs(timerBox.box.height - 121.88) < 1, "timer \(timerBox.box)")
        let band = try #require(r.plate), text = try #require(t["Repeat chorus \u{00D7}2, then bridge"])
        #expect(box(band, 0, 985, 1920, 95), "band \(band)")
        #expect(box(text.box, 76.8, 1002.7, nil, 59.7), "band text \(text.box)")
        #expect(r.bar == nil)
    }
}
