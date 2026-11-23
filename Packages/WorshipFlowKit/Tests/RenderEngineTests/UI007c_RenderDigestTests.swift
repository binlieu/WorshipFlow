// UI-007c (SLIDE): text Fit, text Background fill and video objects change nothing for a slide that uses none of them. The pixels of scenes with
// lyric words, a fitted lyric block and text and shape objects are folded into one digest. The value was recorded on the code as it stood before
// any UI-007c change (base 0f89ce3) and must not change.
import Testing
import Foundation
import CryptoKit
import Domain
@testable import RenderEngine

@Suite struct UI007c_RenderDigestTests {
    static func scenes() -> [SceneDescription] {
        let lyric = TextStyle(fontName: "Helvetica Neue", fontSize: 90, color: .white, outlineWidth: 3, outlineColor: .black,
                              shadow: TextShadow(offsetX: 0, offsetY: 4, blur: 12))
        let caption = TextStyle(fontName: "Helvetica Neue", fontSize: 44, color: ColorRGBA(red: 1, green: 0.8, blue: 0.3))
        func block(_ text: String, fit: Bool) -> TextLayer {
            TextLayer(text: text, style: lyric, frame: NormalizedRect(x: 0.1, y: 0.3, width: 0.8, height: 0.3), fitFloor: fit ? 56 : nil)
        }
        var a = SceneDescription(backgroundColor: ColorRGBA(red: 0.05, green: 0.1, blue: 0.2), textLayers: [block("Amazing grace, how sweet the sound", fit: false)])
        a.objectLayers = [
            .shape(ShapeLayer(shape: .roundedRectangle(cornerRadius: 0.2), fill: ColorRGBA(red: 0.2, green: 0.4, blue: 0.9), strokeColor: .white, strokeWidth: 4,
                              frame: NormalizedRect(x: 0.05, y: 0.05, width: 0.4, height: 0.2), opacity: 0.8)),
            .text(TextLayer(text: "Caption one", style: caption, frame: NormalizedRect(x: 0.5, y: 0.08, width: 0.4, height: 0.15), alignment: .leading, verticalAlignment: .top, opacity: 0.9)),
        ]
        var b = SceneDescription(backgroundColor: .black, textLayers: [block("A very long line of words that does not fit its block at the design size and must be shrunk by the fitter to stay inside", fit: true)])
        b.objectLayers = [.text(TextLayer(text: "Second caption with several words in a small box", style: caption, frame: NormalizedRect(x: 0.6, y: 0.7, width: 0.3, height: 0.2)))]
        let c = SceneDescription(backgroundColor: .clear, textLayers: [block("Keyed", fit: false)])
        return [a, b, c]
    }

    static func digest() throws -> String {
        let compositor = try Compositor()
        var hasher = SHA256()
        for scene in scenes() {
            let frame = try compositor.renderImage(scene: scene, width: 640, height: 360)
            hasher.update(data: Data(frame.bgra))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @Test func scenesThatUseNoneOfTheNewValuesRenderAsTheyDidBeforeUI007c() throws {
        let value = try Self.digest()
        print("UI007c render digest \(value)")
        #expect(value == Self.recordedDigest)
    }

    static let recordedDigest = "d75f33c1c866ff909e1ae83cacaf5a985348aa29eee6ed0ed4b5ceaf65fd411c"
}
