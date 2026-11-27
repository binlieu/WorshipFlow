// OUT-002f (REVIEW-5 M6, L17, L22): text boxes, shapes and fit-to-box text are prepared off the render thread like lyric text, the warmer
// does not make a compositor per request, and a fit-floor text object costs no key and no hash on a frame that repeats the one before.
// Counts only: nothing here asserts a time.
import Testing
import Foundation
import Domain
@testable import RenderEngine


/// A colour value that depends on the tag, so that a shape's bitmap in the process-wide store is this test's own (never another test's).
func shade(_ tag: String) -> Double {
    var h: UInt64 = 1469598103934665603
    for u in tag.unicodeScalars { h = (h ^ UInt64(u.value)) &* 1099511628211 }
    return Double(h % 100_000) / 100_000
}

@Suite struct OUT002f_ObjectPreparationTests {
    static let style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)

    /// A scene whose new content is a text box, a text box with "Shrink to fit box" and a shape: no lyric layers at all.
    static func objectScene(_ tag: String = UUID().uuidString) -> SceneDescription {
        SceneDescription(backgroundColor: .black, textLayers: [], objectLayers: [
            .shape(ShapeLayer(shape: .roundedRectangle(cornerRadius: 0.1), fill: ColorRGBA(red: shade(tag), green: 0.4, blue: 0.8, alpha: 1),
                              frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3))),
            .text(TextLayer(text: "Plain box \(tag)", style: style, frame: NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2))),
            .text(TextLayer(text: "Fitted box \(tag), with enough words to need shrinking in a small frame", style: style,
                            frame: NormalizedRect(x: 0.1, y: 0.75, width: 0.4, height: 0.15), fitFloor: 20)),
        ])
    }

    @Test func anUnpreparedObjectSceneCostsLayoutFitAndShapeOnItsFirstFrame() throws {
        let c = try Compositor()
        _ = try c.renderImage(scene: Self.objectScene(), width: 1920, height: 1080)
        #expect(c.rasterizationCount == 2, "both text boxes were laid out by Core Text on the render call")
        #expect(c.objectFitComputationCount == 1, "the fitted box was measured on the render call")
        #expect(c.shapeRasterizationCount == 1, "the shape was rasterised on the render call")
    }

    @Test func aWarmedObjectSceneCostsNoLayoutNoFitAndNoShapeBitmapOnTheFirstFrame() throws {
        let scene = Self.objectScene()
        TextWarmer.warmNow(scenes: [(scene, 1920, 1080)])
        let c = try Compositor()                                       // an output's own compositor: never warmed itself
        _ = try c.renderImage(scene: scene, width: 1920, height: 1080)
        #expect(c.rasterizationCount == 0, "no Core Text layout of a text box on the render call")
        #expect(c.objectFitComputationCount == 0, "no fit computed for a text box on the render call")
        #expect(c.shapeRasterizationCount == 0, "no shape bitmap made on the render call")
    }

    @Test func aWarmedObjectSceneDrawsTheSameBytesAsAnUnwarmedOne() throws {
        let scene = Self.objectScene("bytes")
        let cold = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        TextWarmer.warmNow(scenes: [(scene, 640, 360)])
        let warm = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        #expect(cold.bgra == warm.bgra)
    }

    @Test func warmingTheSameSceneAgainStillLeavesEverythingInTheStores() throws {
        let tag = UUID().uuidString
        TextWarmer.warmNow(scenes: [(Self.objectScene(tag), 1280, 720)])
        TextWarmer.warmNow(scenes: [(Self.objectScene(tag), 1280, 720)])
        let c = try Compositor()
        _ = try c.renderImage(scene: Self.objectScene(tag), width: 1280, height: 720)
        #expect(c.rasterizationCount == 0 && c.objectFitComputationCount == 0 && c.shapeRasterizationCount == 0)
    }

    @Test func theWarmerDoesNotMakeACompositorForEachRequest() {
        let before = TextWarmer.compositorsCreated.count
        for i in 0..<5 { TextWarmer.warmNow(scenes: [(Self.objectScene("reuse \(i) \(UUID())"), 1280, 720)]) }
        #expect(TextWarmer.compositorsCreated.count - before <= 1, "one compositor for the warmer's lifetime, not one per request")
    }

    @Test func aFitFloorTextObjectBuildsItsFitKeyOncePerChangeNotOncePerFrame() throws {
        let c = try Compositor()
        let scene = Self.objectScene()
        for _ in 0..<10 { _ = try c.renderImage(scene: scene, width: 1280, height: 720) }
        #expect(c.objectFitKeyBuildCount == 1, "the repeat frames reuse the answer of the frame before: no key, no hash (\(c.objectFitKeyBuildCount))")
        #expect(c.objectFitComputationCount == 1)
        var changed = scene
        if case .text(var t) = changed.objectLayers[2] { t.text += " and more"; changed.objectLayers[2] = .text(t) }
        for _ in 0..<5 { _ = try c.renderImage(scene: changed, width: 1280, height: 720) }
        #expect(c.objectFitKeyBuildCount == 2, "changed words build the key once more")
    }

    @Test func twoFitFloorBoxesEachKeepTheirOwnAnswer() throws {
        let c = try Compositor()
        var scene = Self.objectScene()
        scene.objectLayers.append(.text(TextLayer(text: "Second fitted \(UUID())", style: Self.style,
                                                  frame: NormalizedRect(x: 0.5, y: 0.75, width: 0.4, height: 0.15), fitFloor: 20)))
        for _ in 0..<10 { _ = try c.renderImage(scene: scene, width: 1280, height: 720) }
        #expect(c.objectFitKeyBuildCount == 2, "one key for each box, built once (\(c.objectFitKeyBuildCount))")
    }
}
