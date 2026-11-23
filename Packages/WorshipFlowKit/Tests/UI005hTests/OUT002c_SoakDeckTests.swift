// OUT-002c (KI-007): the soak's own slides, composed the way the audience screen composes them, drawn through the preparation gate on one
// compositor (an output's). Offscreen and counts only: no display is touched.
import Testing
import Foundation
import Domain
import RenderEngine
import OperatorCore
@testable import OutputEngine

@Suite struct OUT002c_SoakDeckTests {
    // The same six lines as App/Sources/SoakConfig.swift (SoakDeck); the app target cannot be imported here.
    static let slides: [SlideContent] = [
        SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
        SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu một người tội lỗi như tôi"),
        SlideContent(primary: "I once was lost, but now am found", secondary: "Xưa tôi lạc lối, nay được tìm thấy"),
        SlideContent(primary: "Was blind, but now I see", secondary: "Xưa tôi mù lòa, nay được thấy sáng"),
        SlideContent(primary: "Praise the Lord, all you nations", secondary: "Hãy ngợi khen Chúa, hỡi muôn dân"),
        SlideContent(primary: "Stacked marks: Ễ Ậ Ở Ỗ Ẵ ỷ ự", secondary: "Nguyện xin Chúa ban phước, ễ ậ ở ỗ ẵ"),
    ]

    func scenes() -> [SceneDescription] {
        // A tag makes the words unique to this run, so the process-wide stores cannot already hold them.
        let tag = UUID().uuidString.prefix(8)
        let deck = ShowDeck(presentationID: UUID(), slides: Self.slides.map { SlideContent(primary: "\($0.primary) \(tag)", secondary: "\($0.secondary) \(tag)") })
        let audience = ScreenProfile(name: "Audience", role: .audience, destination: .window)
        return deck.slides.indices.map { i in
            var state = ShowState()
            state.apply(.load(deck))
            state.apply(.trigger(index: i))
            return PublishedScenes(state: state, clockText: nil, profiles: [audience]).scene(forScreen: audience.id)
        }
    }

    @Test func withoutTheGateEverySlideCostsCoreTextOnItsFirstFrame() throws {
        let c = try Compositor()
        for scene in scenes() { _ = try c.renderImage(scene: scene, width: 1920, height: 1080) }
        #expect(c.rasterizationCount >= 6, "each of the six slides was rasterised on the render call (\(c.rasterizationCount))")
        #expect(c.fitComputationCount >= 1)
        print("OUT002c soak deck, no gate: rasterisations \(c.rasterizationCount), fits \(c.fitComputationCount)")
    }

    @Test func throughTheGateNoSlideCostsCoreTextOrAFitOnTheRenderCall() throws {
        let gate = ScenePreparationGate(preparer: { scene, w, h, wanted, done in if wanted() { ScenePreparation.warm(scene, w, h) }; done() })
        let c = try Compositor()
        var shown: [SceneDescription] = []
        _ = gate.sceneToDraw(SceneDescription(backgroundColor: .black, textLayers: []), width: 1920, height: 1080)   // the output is already up
        for scene in scenes() {
            let drawn = gate.sceneToDraw(scene, width: 1920, height: 1080)
            #expect(drawn == scene)
            shown.append(drawn)
            _ = try c.renderImage(scene: drawn, width: 1920, height: 1080)
        }
        #expect(c.rasterizationCount == 0, "Core Text rasterisations on the render call: \(c.rasterizationCount)")
        #expect(c.fitComputationCount == 0, "fit computations on the render call: \(c.fitComputationCount)")
        #expect(c.objectFitComputationCount == 0)
        #expect(shown.count == 6)
    }
}
