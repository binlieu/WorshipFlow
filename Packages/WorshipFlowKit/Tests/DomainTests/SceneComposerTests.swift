// OUT-002 acceptance tests: one live state, a different composition per screen role (G-2, SCRN-01..03, SCRN-09).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct SceneComposerTests {
    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay"),
            SlideContent(primary: "That saved a wretch like me", secondary: nil),
        ])))
        s.apply(.trigger(index: 0))
        return s
    }
    func texts(_ scene: SceneDescription) -> [String] { scene.textLayers.map(\.text) }

    @Test func audienceShowsBothLanguagesOverVideo() {
        let scene = SceneComposer.scene(for: .audience, state: liveState())
        #expect(scene.showsVideo)
        #expect(texts(scene).contains("Amazing grace, how sweet the sound"))
        #expect(texts(scene).contains("Ân điển lạ lùng thay"))
        #expect(texts(scene).contains { $0.contains("That saved a wretch") } == false)   // never the next slide
    }

    @Test func stageShowsCurrentAndNextWithoutVideo() {
        let scene = SceneComposer.scene(for: .stage, state: liveState())
        #expect(scene.showsVideo == false)
        #expect(scene.backgroundColor.alpha == 1)
        #expect(texts(scene).contains { $0.contains("Amazing grace, how sweet the sound") })
        #expect(texts(scene).contains { $0.contains("That saved a wretch like me") })
        // Current is above next and larger.
        let current = scene.textLayers.first { $0.text.contains("Amazing grace") }
        let next = scene.textLayers.first { $0.text.contains("That saved") }
        #expect((current?.frame.y ?? 1) < (next?.frame.y ?? 0))
        #expect((current?.style.fontSize ?? 0) > (next?.style.fontSize ?? 0))
    }

    @Test func broadcastIsATransparentLowerThird() {
        let scene = SceneComposer.scene(for: .broadcast, state: liveState())
        #expect(scene.backgroundColor.alpha == 0)
        #expect(scene.showsVideo == false)
        #expect(scene.textLayers.isEmpty == false)
        for layer in scene.textLayers { #expect(layer.frame.y >= 0.6) }
    }

    @Test func clearedAudienceKeepsBackgroundAndDropsText() {
        var s = liveState(); s.apply(.clear)
        let audience = SceneComposer.scene(for: .audience, state: s)
        #expect(audience.textLayers.isEmpty && audience.showsVideo)
        let broadcast = SceneComposer.scene(for: .broadcast, state: s)
        #expect(broadcast.textLayers.isEmpty && broadcast.backgroundColor.alpha == 0)
        // The stage still shows what comes next.
        let stage = SceneComposer.scene(for: .stage, state: s)
        #expect(texts(stage).contains { $0.contains("That saved a wretch like me") })
        #expect(texts(stage).contains { $0.contains("Amazing grace") } == false)
    }

    @Test func stoppedScreensAreEmpty() {
        var s = liveState(); s.apply(.stop)
        for role in ScreenRole.allCases {
            let scene = SceneComposer.scene(for: role, state: s)
            #expect(scene.textLayers.isEmpty && scene.showsVideo == false)
        }
        #expect(SceneComposer.scene(for: .audience, state: s).backgroundColor == .black)
        #expect(SceneComposer.scene(for: .broadcast, state: s).backgroundColor.alpha == 0)
    }

    /// A slide with no second language produces no empty text layer.
    @Test func missingSecondaryAddsNoLayer() {
        var s = liveState(); s.apply(.next)
        let scene = SceneComposer.scene(for: .audience, state: s)
        #expect(scene.textLayers.count == 1)
        #expect(scene.textLayers.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    /// LIVE-04 groundwork: the stage scene carries the clock text it is given; audience and broadcast never do.
    @Test func clockAppearsOnStageOnly() {
        let s = liveState()
        #expect(texts(SceneComposer.scene(for: .stage, state: s, clockText: "10:32")).contains("10:32"))
        #expect(texts(SceneComposer.scene(for: .audience, state: s, clockText: "10:32")).contains("10:32") == false)
        #expect(texts(SceneComposer.scene(for: .broadcast, state: s, clockText: "10:32")).contains("10:32") == false)
    }
}
