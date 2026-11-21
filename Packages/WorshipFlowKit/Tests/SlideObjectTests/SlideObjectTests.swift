// SLIDE-001a acceptance tests: slide objects — shapes, images and text boxes — with fills and effects
// (PRES-01, MEDIA-07). Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
@testable import RenderEngine
@testable import Persistence

let wfRed = ColorRGBA(red: 1, green: 0, blue: 0), wfGreen = ColorRGBA(red: 0, green: 1, blue: 0), wfBlue = ColorRGBA(red: 0, green: 0, blue: 1)

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NormalizedRect { NormalizedRect(x: x, y: y, width: w, height: h) }
func shape(_ s: ShapeObject.Shape, fill: ColorRGBA?, stroke: ColorRGBA? = nil, strokeWidth: Double = 0, frame: NormalizedRect, opacity: Double = 1) -> SlideObject {
    SlideObject(id: UUID(), frame: frame, opacity: opacity, content: .shape(ShapeObject(shape: s, fill: fill, strokeColor: stroke, strokeWidth: strokeWidth)))
}

@Suite struct SlideObjectModelTests {
    @Test func slideContentCarriesObjectsAndStaysCompatible() throws {
        var content = SlideContent(primary: "Title", secondary: nil)
        #expect(content.objects.isEmpty)
        content.objects = [shape(.rectangle, fill: wfRed, frame: rect(0, 0, 0.5, 0.5))]
        #expect(content.isBlank == false)
        // A slide with only objects is not blank.
        #expect(SlideContent(primary: "", secondary: nil, objects: content.objects).isBlank == false)
        // Content saved before objects existed still decodes.
        let old = try JSONDecoder().decode(SlideContent.self, from: Data(#"{"primary":"Old","secondary":"Cũ"}"#.utf8))
        #expect(old.primary == "Old" && old.secondary == "Cũ" && old.objects.isEmpty)
        let round = try JSONDecoder().decode(SlideContent.self, from: JSONEncoder().encode(content))
        #expect(round == content)
    }

    @Test func everyObjectKindRoundTrips() throws {
        let text = SlideObject(id: UUID(), frame: rect(0.1, 0.1, 0.8, 0.2), opacity: 1,
                               content: .text(TextObject(text: "Point one", style: TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white), alignment: .leading, verticalAlignment: .top)))
        let image = SlideObject(id: UUID(), frame: rect(0.5, 0.5, 0.4, 0.4), opacity: 0.8, content: .image(ImageObject(path: "/tmp/photo.jpg", contentMode: .fit)))
        let round = shape(.roundedRectangle(cornerRadius: 0.1), fill: wfBlue, stroke: .white, strokeWidth: 4, frame: rect(0, 0, 1, 1))
        let all = [text, image, round, shape(.ellipse, fill: nil, stroke: wfRed, strokeWidth: 2, frame: .full)]
        #expect(try JSONDecoder().decode([SlideObject].self, from: JSONEncoder().encode(all)) == all)
    }

    /// Order in the array is back to front.
    @Test func zOrderHelpers() {
        let a = shape(.rectangle, fill: wfRed, frame: .full), b = shape(.rectangle, fill: wfGreen, frame: .full), c = shape(.rectangle, fill: wfBlue, frame: .full)
        var content = SlideContent(primary: "", secondary: nil, objects: [a, b, c])
        content.bringToFront(a.id)
        #expect(content.objects.map(\.id) == [b.id, c.id, a.id])
        content.sendToBack(c.id)
        #expect(content.objects.map(\.id) == [c.id, b.id, a.id])
        content.moveForward(c.id)
        #expect(content.objects.map(\.id) == [b.id, c.id, a.id])
        content.moveBackward(b.id)                                   // already at the back: no change
        #expect(content.objects.map(\.id) == [b.id, c.id, a.id])
        content.removeObject(c.id)
        #expect(content.objects.map(\.id) == [b.id, a.id])
        content.bringToFront(UUID())                                 // unknown id: no change
        #expect(content.objects.count == 2)
    }

    @Test func objectsStayOnTheSlideWhenMovedOrResized() {
        var o = shape(.rectangle, fill: wfRed, frame: rect(0.5, 0.5, 0.4, 0.4))
        o.move(dx: 0.9, dy: -0.9)
        #expect(abs(o.frame.x - 0.6) < 1e-9 && o.frame.y == 0)
        o.resize(width: 5, height: 0)
        #expect(o.frame.x + o.frame.width <= 1.000001 && o.frame.height >= SlideObject.minimumSize)
        o.opacity = 7
        #expect(o.opacity == 1)
    }

    @Test func textStyleShadowIsOptionalAndCompatible() throws {
        var style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)
        #expect(style.shadow == nil)
        style.shadow = TextShadow(color: .black, offsetX: 3, offsetY: 3, blur: 6)
        #expect(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(style)) == style)
        let old = try JSONDecoder().decode(TextStyle.self, from: Data(#"{"fontName":"Helvetica Neue","fontSize":60,"color":{"red":1,"green":1,"blue":1,"alpha":1},"outlineWidth":0,"outlineColor":{"red":0,"green":0,"blue":0,"alpha":1}}"#.utf8))
        #expect(old.shadow == nil && old.fontSize == 60)
    }
}

@Suite struct SlideObjectSceneTests {
    func state(_ content: SlideContent) -> ShowState {
        var s = ShowState(); s.apply(.load(ShowDeck(presentationID: UUID(), slides: [content]))); s.apply(.trigger(index: 0)); return s
    }
    var sermonSlide: SlideContent {
        SlideContent(primary: "Grace", secondary: nil, objects: [
            shape(.rectangle, fill: wfBlue, frame: rect(0, 0, 1, 0.2)),
            SlideObject(id: UUID(), frame: rect(0.1, 0.3, 0.8, 0.2), opacity: 1,
                        content: .text(TextObject(text: "Point one", style: TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white), alignment: .leading, verticalAlignment: .top))),
            SlideObject(id: UUID(), frame: rect(0.6, 0.6, 0.3, 0.3), opacity: 0.5, content: .image(ImageObject(path: "/tmp/photo.jpg", contentMode: .fit))),
        ])
    }

    /// Objects are drawn back to front, under the lyric text.
    @Test func audienceSceneCarriesObjectsInOrder() {
        let scene = SceneComposer.scene(for: .audience, state: state(sermonSlide), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.objectLayers.count == 3)
        guard scene.objectLayers.count == 3 else { return }
        if case .shape(let s) = scene.objectLayers[0] { #expect(s.fill == wfBlue && s.frame == rect(0, 0, 1, 0.2)) } else { Issue.record("first layer should be the shape") }
        if case .text(let t) = scene.objectLayers[1] { #expect(t.text == "Point one" && t.alignment == .leading) } else { Issue.record("second layer should be the text box") }
        if case .image(let i) = scene.objectLayers[2] { #expect(i.path == "/tmp/photo.jpg" && i.opacity == 0.5) } else { Issue.record("third layer should be the image") }
        #expect(scene.textLayers.map(\.text) == ["Grace"])              // lyric text is still its own layer, on top
    }

    /// Full-frame slide artwork must not break a keyed lower third; the stage layout never shows it.
    @Test func broadcastLowerThirdAndStageLeaveObjectsOut() {
        let s = state(sermonSlide)
        #expect(SceneComposer.scene(for: .broadcast, state: s, theme: .lowerThird, look: .standard, props: []).objectLayers.isEmpty)
        #expect(SceneComposer.scene(for: .stage, state: s).objectLayers.isEmpty)
        // A broadcast screen given an opaque theme does show them.
        #expect(SceneComposer.scene(for: .broadcast, state: s, theme: .fullScreen, look: .standard, props: []).objectLayers.count == 3)
    }

    @Test func objectsFollowTheSlideLayerAndClear() {
        var s = state(sermonSlide)
        let hidden = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: ScreenLook(themeID: nil, visibleLayers: [.background, .props]), props: [])
        #expect(hidden.objectLayers.isEmpty && hidden.textLayers.isEmpty)
        s.apply(.clear)
        #expect(SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: []).objectLayers.isEmpty)
    }

    @Test func slidesWithoutObjectsAreUnchanged() {
        let plain = SlideContent(primary: "Grace", secondary: "Ân điển")
        let scene = SceneComposer.scene(for: .audience, state: state(plain), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.objectLayers.isEmpty && scene.textLayers.count == 2)
    }
}

@Suite struct ShapeRenderingTests {
    let clear = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)
    func render(_ layers: [SceneObjectLayer], text: [TextLayer] = [], size: Int = 200) throws -> RenderedFrame {
        var scene = SceneDescription(backgroundColor: clear, textLayers: text)
        scene.objectLayers = layers
        return try Compositor().renderImage(scene: scene, width: size, height: size)
    }
    func layer(_ s: ShapeObject.Shape, fill: ColorRGBA?, stroke: ColorRGBA? = nil, strokeWidth: Double = 0, frame: NormalizedRect, opacity: Double = 1) -> SceneObjectLayer {
        .shape(ShapeLayer(shape: s, fill: fill, strokeColor: stroke, strokeWidth: strokeWidth, frame: frame, opacity: opacity))
    }

    @Test func rectangleFillsExactlyItsFrame() throws {
        let f = try render([layer(.rectangle, fill: wfRed, frame: rect(0.25, 0.25, 0.5, 0.5))])
        #expect(f.pixel(x: 100, y: 100).red == 255 && f.pixel(x: 100, y: 100).alpha == 255)
        #expect(f.pixel(x: 55, y: 55).red == 255)
        #expect(f.pixel(x: 45, y: 100).alpha == 0 && f.pixel(x: 155, y: 100).alpha == 0 && f.pixel(x: 100, y: 45).alpha == 0)
    }

    @Test func ellipseLeavesItsCornersEmpty() throws {
        let f = try render([layer(.ellipse, fill: wfGreen, frame: .full)])
        #expect(f.pixel(x: 100, y: 100).green == 255)
        for (x, y) in [(3, 3), (196, 3), (3, 196), (196, 196)] { #expect(f.pixel(x: x, y: y).alpha == 0) }
        #expect(f.pixel(x: 100, y: 4).green > 200)                    // top of the ellipse touches the frame edge
    }

    @Test func roundedRectangleRoundsOnlyTheCorners() throws {
        let f = try render([layer(.roundedRectangle(cornerRadius: 0.25), fill: wfBlue, frame: .full)])
        #expect(f.pixel(x: 2, y: 2).alpha == 0)                       // corner is cut
        #expect(f.pixel(x: 100, y: 2).blue == 255)                    // edge middle is filled
        #expect(f.pixel(x: 2, y: 100).blue == 255)
    }

    /// Stroke width is in points at a 1080-line reference, like text outline.
    @Test func strokeIsDrawnInsideTheFrameEdge() throws {
        let f = try render([layer(.rectangle, fill: nil, stroke: wfRed, strokeWidth: 54, frame: .full)], size: 200)   // 54 pt at 1080 = 10 px at 200
        #expect(f.pixel(x: 4, y: 100).red == 255 && f.pixel(x: 195, y: 100).red == 255 && f.pixel(x: 100, y: 4).red == 255)
        #expect(f.pixel(x: 100, y: 100).alpha == 0)                   // no fill
        #expect(f.pixel(x: 20, y: 100).alpha == 0)
    }

    @Test func opacityAndPremultiplication() throws {
        let p = try render([layer(.rectangle, fill: .white, frame: .full, opacity: 0.5)]).pixel(x: 100, y: 100)
        #expect(abs(Int(p.alpha) - 128) <= 2 && abs(Int(p.red) - 128) <= 2)
    }

    @Test func layersDrawBackToFrontUnderLyricText() throws {
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 600, color: .white)
        let f = try render([layer(.rectangle, fill: wfRed, frame: .full), layer(.rectangle, fill: wfGreen, frame: rect(0, 0, 0.5, 1))],
                           text: [TextLayer(text: "█", style: style, frame: rect(0.4, 0.4, 0.2, 0.2))])
        #expect(f.pixel(x: 20, y: 20).green == 255 && f.pixel(x: 20, y: 20).red == 0)      // green over red on the left
        #expect(f.pixel(x: 180, y: 20).red == 255)                                           // red alone on the right
        let mid = f.pixel(x: 100, y: 100)
        #expect(mid.red > 240 && mid.green > 240 && mid.blue > 240)                          // lyric text over both
    }

    @Test func textObjectAndShadow() throws {
        let plain = TextStyle(fontName: "Helvetica Neue", fontSize: 200, color: .white)
        var shadowed = plain; shadowed.shadow = TextShadow(color: wfRed, offsetX: 30, offsetY: 30, blur: 0)
        func ink(_ style: TextStyle) throws -> (white: Int, red: Int) {
            let f = try render([.text(TextLayer(text: "I", style: style, frame: .full))], size: 300)
            var w = 0, r = 0
            for y in 0..<300 { for x in 0..<300 { let p = f.pixel(x: x, y: y)
                if p.red > 200 && p.green > 200 && p.blue > 200 { w += 1 } else if p.red > 150 && p.green < 60 && p.alpha > 150 { r += 1 } } }
            return (w, r)
        }
        let a = try ink(plain), b = try ink(shadowed)
        #expect(a.white > 50 && a.red == 0)
        #expect(b.red > 50)                                           // the shadow is visible beside the glyph
        #expect(abs(b.white - a.white) < a.white / 4)                 // the glyph itself is unchanged
    }

    /// Shadows on lyric text work the same way and are never clipped by the text bitmap.
    @Test func rasterizerPadsForShadow() throws {
        var style = TextStyle(fontName: "Helvetica Neue", fontSize: 96, color: .white)
        let plain = try TextRasterizer().rasterize("Ân điển", style: style, maxWidth: 1728)
        style.shadow = TextShadow(color: .black, offsetX: 12, offsetY: 12, blur: 10)
        let shadowed = try TextRasterizer().rasterize("Ân điển", style: style, maxWidth: 1728)
        #expect(shadowed.inkBounds.width > plain.inkBounds.width && shadowed.inkBounds.height > plain.inkBounds.height)
        #expect(shadowed.inkBounds.maxX <= CGFloat(shadowed.width - 1) && shadowed.inkBounds.maxY <= CGFloat(shadowed.height - 1))
        #expect(shadowed.inkBounds.minX >= 1 && shadowed.inkBounds.minY >= 1)
    }
}

@Suite struct SlideObjectStoreTests {
    @Test func schemaV5KeepsOlderRowsAndStoresObjects() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
        let old = try LibraryStore.open(at: url, migratingUpTo: "v4")
        let lib = try await old.createLibrary(name: "Sermons")
        let p = try await old.createPresentation(in: lib.id, title: "Grace", kind: .sermon)
        _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: "Old slide", secondary: "Cũ"))
        try old.close()

        let store = try LibraryStore.open(at: url)
        #expect(Array(try await store.appliedMigrations().prefix(5)) == ["v1", "v2", "v3", "v4", "v5"])
        var slide = try #require(try await store.slides(of: p.id).first)
        #expect(slide.content == SlideContent(primary: "Old slide", secondary: "Cũ"))        // objects default to empty

        let box = SlideObject(id: UUID(), frame: rect(0.1, 0.3, 0.8, 0.2), opacity: 1,
                              content: .text(TextObject(text: "Điểm thứ nhất", style: TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white), alignment: .leading, verticalAlignment: .top)))
        slide.content.objects = [shape(.ellipse, fill: wfBlue, frame: rect(0, 0, 0.2, 0.2)), box]
        try await store.updateSlide(slide)
        let again = try #require(try await store.slides(of: p.id).first)
        #expect(again.content == slide.content)
        // Text boxes are searchable like lyrics, without diacritics.
        #expect(try await store.search("diem thu nhat", limit: 5).map(\.presentationID) == [p.id])
        let added = try await store.appendSlide(to: p.id, content: SlideContent(primary: "", secondary: nil, objects: [box]))
        #expect(try await store.slides(of: p.id).last?.content.objects == [box])
        #expect(added.content.objects == [box])
        try store.close()
    }

    @Test func reflowKeepsNothingButWordsAndPlainSlidesStaySmall() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "a\nb", secondary: nil, maxLines: 1))
        #expect(try await store.slides(of: p.id).allSatisfy { $0.content.objects.isEmpty })
    }
}
