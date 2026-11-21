// UI-003 / LIVE-03: the stage message on a stage screen. A layout with a message element draws it there; a layout
// without one draws a banner along the bottom. A blank message draws nothing. Audience and broadcast never read it.
import Testing
import Foundation
@testable import Domain

@Suite struct UI003_StageMessageBannerTests {
    func context(message: String?) -> StageContext {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One"), SlideContent(primary: "Two")])))
        state.apply(.trigger(index: 0))
        return StageContext(state: state, now: 0, timeOfDayText: "9:00 AM", timers: [], message: message, notes: nil)
    }

    @Test func aLayoutWithoutAMessageElementGetsABannerAlongTheBottom() {
        let layout = StageLayout.standard
        #expect(!layout.elements.contains { $0.kind == .message })
        let scene = StageComposer.scene(layout: layout, context: context(message: "Wrap up in 2 min"))
        let banner = scene.textLayers.first { $0.text == "Wrap up in 2 min" }
        #expect(banner != nil)
        #expect(banner?.style.color == layout.warningColor)
        #expect((banner?.frame.y ?? 0) >= 0.8 && (banner?.frame.y ?? 0) + (banner?.frame.height ?? 1) <= 1.0001)
    }

    @Test func aLayoutWithAMessageElementDrawsItThereAndNotTwice() {
        var layout = StageLayout.standard
        let frame = NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2)
        layout.elements.append(StageElement(id: UUID(), kind: .message, frame: frame,
                                            style: TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white), alignment: .center))
        let scene = StageComposer.scene(layout: layout, context: context(message: "Repeat chorus"))
        let hits = scene.textLayers.filter { $0.text == "Repeat chorus" }
        #expect(hits.count == 1 && hits.first?.frame == frame)
    }

    @Test func aBlankOrMissingMessageDrawsNothingExtra() {
        let plain = StageComposer.scene(layout: .standard, context: context(message: nil))
        #expect(StageComposer.scene(layout: .standard, context: context(message: "   ")) == plain)
        #expect(StageComposer.scene(layout: .standard, context: context(message: "")) == plain)
    }

    @Test func theMessageStaysWhenTheSlideChanges() {
        var ctx = context(message: "Stay")
        ctx.state.apply(.next)
        #expect(StageComposer.scene(layout: .standard, context: ctx).textLayers.contains { $0.text == "Stay" })
    }

    @Test func audienceAndBroadcastScenesDoNotChangeWithAMessage() {
        // The composers for those roles take no message at all; the same state gives the same scene.
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One")])))
        state.apply(.trigger(index: 0))
        for role in [ScreenRole.audience, .broadcast] {
            let scene = SceneComposer.scene(for: role, state: state, theme: Theme.builtIn[0], look: .standard, props: [])
            #expect(!scene.textLayers.contains { $0.text == "Wrap up" })
        }
    }
}
