// SLIDE-001a: further checks on slide objects beyond the coordinator's acceptance tests.
import Testing
import Foundation
import Domain

@Suite struct SlideObjectExtraTests {
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> SlideObject {
        SlideObject(frame: NormalizedRect(x: x, y: y, width: w, height: h),
                    content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
    }
    private func live(_ content: SlideContent) -> ShowState {
        var s = ShowState(); s.apply(.load(ShowDeck(presentationID: UUID(), slides: [content]))); s.apply(.trigger(index: 0)); return s
    }

    @Test func slidesWithoutObjectsEncodeAsBefore() throws {
        let json = String(decoding: try JSONEncoder().encode(SlideContent(primary: "A", secondary: nil)), as: UTF8.self)
        #expect(json == #"{"primary":"A"}"#)
    }

    @Test func opacityIsClampedWhenDecodingAndAssigning() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","frame":{"x":0,"y":0,"width":1,"height":1},"opacity":3,"content":{"shape":{"_0":{"shape":{"rectangle":{}},"strokeWidth":0}}}}"#
        let decoded = try JSONDecoder().decode(SlideObject.self, from: Data(json.utf8))
        #expect(decoded.opacity == 1 && decoded.id == id)
        var o = box(0, 0, 1, 1)
        o.opacity = -4
        #expect(o.opacity == 0)
        o.opacity = .nan
        #expect(o.opacity == 1)
    }

    @Test func resizeNearTheEdgeSlidesBackInsteadOfLeavingTheSlide() {
        var o = box(0.995, 0.995, 0.004, 0.004)
        o.resize(width: 0.001, height: 0.001)
        #expect(o.frame.width == SlideObject.minimumSize && o.frame.height == SlideObject.minimumSize)
        #expect(o.frame.x + o.frame.width <= 1 + 1e-12 && o.frame.y + o.frame.height <= 1 + 1e-12)
        var big = box(0.2, 0.2, 0.2, 0.2)
        big.move(dx: .nan, dy: .infinity)
        #expect(big.frame.x == 0.2 && big.frame.y == 0.2)
    }

    @Test func objectsHideWhileAForegroundClipPlays() {
        let slide = SlideContent(primary: "Grace", objects: [box(0, 0, 1, 0.2)])
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: UUID(), kind: .video, duration: 10), at: 0)
        let playing = SceneComposer.scene(for: .audience, state: live(slide), theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(playing.objectLayers.isEmpty && playing.textLayers.isEmpty && playing.foregroundMedia != nil)
        let idle = SceneComposer.scene(for: .audience, state: live(slide), theme: .fullScreen, look: .standard, props: [], media: MediaLayers())
        #expect(idle.objectLayers.count == 1)
    }

    @Test func stoppedShowAndTransparentBroadcastLeaveObjectsOut() {
        var s = live(SlideContent(primary: "Grace", objects: [box(0, 0, 1, 1)]))
        s.apply(.stop)
        #expect(SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: []).objectLayers.isEmpty)
        // The legacy entry points behave like the themed ones: audience shows objects, broadcast lower third does not.
        let on = live(SlideContent(primary: "Grace", objects: [box(0, 0, 1, 1)]))
        #expect(SceneComposer.scene(for: .audience, state: on).objectLayers.count == 1)
        #expect(SceneComposer.scene(for: .broadcast, state: on).objectLayers.isEmpty)
    }

    @Test func sceneDescriptionDecodesWithoutObjectLayers() throws {
        let old = #"{"backgroundColor":{"red":0,"green":0,"blue":0,"alpha":1},"showsVideo":false,"textLayers":[],"overlayImages":[]}"#
        let scene = try JSONDecoder().decode(SceneDescription.self, from: Data(old.utf8))
        #expect(scene.objectLayers.isEmpty)
        var withObjects = scene
        withObjects.objectLayers = [box(0, 0, 1, 1).sceneLayer]
        #expect(try JSONDecoder().decode(SceneDescription.self, from: JSONEncoder().encode(withObjects)) == withObjects)
    }
}
