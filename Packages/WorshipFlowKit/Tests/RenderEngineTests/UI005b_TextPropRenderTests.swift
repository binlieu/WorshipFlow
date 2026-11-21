// UI-005b item 5: a text prop with Vietnamese marks is drawn by the compositor through the same text path as lyrics: the same layer
// rendered by hand gives the same pixels, the ink stays in the prop's box, and a prop targeted elsewhere draws nothing.
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct UI005b_TextPropRenderTests {
    let words = "Ân điển lạ lùng — Ễ Ậ Ở Ỗ"
    func strap(_ targets: Set<ScreenRole>) -> Prop {
        Prop(name: "Strap", imagePath: "", frame: .full, targets: targets, kind: .text, text: TextPropSpec(text: words, fontSize: 60, anchor: .bottomLeft))
    }
    func liveEmpty() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "")])))
        s.apply(.trigger(index: 0))
        return s
    }
    func broadcastScene(_ props: [Prop]) -> SceneDescription {
        SceneComposer.scene(for: .broadcast, state: liveEmpty(), theme: ThemeResolver.theme(for: .broadcast, lookThemeID: nil, presentationThemeID: nil, themes: Theme.builtIn), look: .standard, props: props)
    }
    func ink(_ f: RenderedFrame, _ xs: Range<Int>, _ ys: Range<Int>) -> Int {
        var n = 0
        for y in ys { for x in xs where f.pixel(x: x, y: y).alpha > 0 { n += 1 } }
        return n
    }

    @Test func theWordsAreDrawnInsideThePropsBoxAndNowhereElse() throws {
        let frame = try Compositor().renderImage(scene: broadcastScene([strap([.broadcast])]), width: 640, height: 360)
        // The bottom-left box is x 4 to 64 %, y 82 to 96 %.
        let inside = ink(frame, 25..<410, 295..<346)
        let total = ink(frame, 0..<640, 0..<360)
        #expect(inside > 200)
        #expect(total == inside)
    }

    @Test func theSameLayerRenderedByHandGivesTheSamePixelsAsTheComposedScene() throws {
        let prop = strap([.broadcast])
        let layer = try #require(prop.textLayer)
        let c = try Compositor()
        let composed = try c.renderImage(scene: broadcastScene([prop]), width: 640, height: 360)
        let byHand = try c.renderImage(scene: SceneDescription(backgroundColor: .clear, textLayers: [layer]), width: 640, height: 360)
        var differing = 0
        for y in 0..<360 { for x in 0..<640 where composed.pixel(x: x, y: y) != byHand.pixel(x: x, y: y) { differing += 1 } }
        #expect(differing == 0)
    }

    @Test func aPropTargetedToStageOnlyLeavesTheBroadcastPictureEmpty() throws {
        let frame = try Compositor().renderImage(scene: broadcastScene([strap([.stage])]), width: 640, height: 360)
        #expect(ink(frame, 0..<640, 0..<360) == 0)
    }
}
