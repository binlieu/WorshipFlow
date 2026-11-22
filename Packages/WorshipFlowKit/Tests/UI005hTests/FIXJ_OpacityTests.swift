// FIX-J item 8 (UI-005h): the SDI output's "is this scene opaque" check knows a gradient background, and the plate takes its layer's opacity.
// Old API only, so these could be run red first.
import Testing
import Foundation
import Domain
import OutputEngine
@testable import RenderEngine

@Suite struct FIXJ_OpacityTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    func gradient(_ alphas: [Double]) -> GradientBackground {
        GradientBackground(stops: alphas.enumerated().map { i, a in
            .init(position: Double(i) / Double(max(1, alphas.count - 1)), color: ColorRGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: a)) },
                           centerX: 0.5, centerY: 0.5, radiusX: 1, radiusY: 1)
    }

    @Test func anOpaqueGradientOnAClearBackgroundIsOpaque() {
        var scene = SceneDescription(backgroundColor: .clear, textLayers: [])
        scene.backgroundGradient = gradient([1, 1, 1])
        #expect(SDIOutput.isOpaque(scene))
    }

    @Test func aGradientWithATransparentStopIsNotOpaque() {
        var scene = SceneDescription(backgroundColor: .clear, textLayers: [])
        scene.backgroundGradient = gradient([1, 0.5, 1])
        #expect(!SDIOutput.isOpaque(scene))
        scene.backgroundGradient = gradient([0, 0])
        #expect(!SDIOutput.isOpaque(scene))
    }

    @Test func theEarlierAnswersAreUnchanged() {
        #expect(SDIOutput.isOpaque(SceneDescription(backgroundColor: .black, textLayers: [])))
        #expect(!SDIOutput.isOpaque(SceneDescription(backgroundColor: .clear, textLayers: [])))
        #expect(!SDIOutput.isOpaque(SceneDescription(backgroundColor: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.5), textLayers: [])))
        #expect(SDIOutput.isOpaque(SceneDescription(backgroundColor: .clear, showsVideo: true, textLayers: [])))
        let designAudience = SceneComposer.scene(for: .audience, state: UI005hFixtures.live(), theme: .fullScreen, look: .standard, props: [])
        #expect(SDIOutput.isOpaque(designAudience))
        let lowerThird = SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(), theme: .lowerThird, look: .standard, props: [])
        #expect(!SDIOutput.isOpaque(lowerThird), "the lower third is keyed: a plate and words over nothing")
    }

    @Test func aPlateFadesWithItsLayers() throws {
        var scene = SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(UI005hFixtures.lowerThirdSlide), theme: .lowerThird, look: .standard, props: [])
        let c = try Compositor()
        let full = try c.renderImage(scene: scene, width: 1280, height: 720)
        for i in scene.textLayers.indices { scene.textLayers[i].opacity = 0.5 }
        let half = try c.renderImage(scene: scene, width: 1280, height: 720)
        // A point inside the plate, to the right of the words: the plate's own fill (alpha 0.86 of a premultiplied byte).
        let p = (x: 1150, y: 648)
        let a = Double(full.pixel(x: p.x, y: p.y).alpha), b = Double(half.pixel(x: p.x, y: p.y).alpha)
        #expect(a > 200, "the plate is there at full opacity: \(a)")
        #expect(abs(b - a / 2) <= 2, "half opacity gives half the plate's alpha: \(b) of \(a)")
    }

    @Test func aPlateWhoseLayersAreFullyOpaqueIsDrawnAsBefore() throws {
        let scene = SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(UI005hFixtures.lowerThirdSlide), theme: .lowerThird, look: .standard, props: [])
        let c = try Compositor()
        let f = try c.renderImage(scene: scene, width: 1280, height: 720)
        #expect(abs(Double(f.pixel(x: 1150, y: 648).alpha) - 0.86 * 255) <= 1.5)
    }
}
