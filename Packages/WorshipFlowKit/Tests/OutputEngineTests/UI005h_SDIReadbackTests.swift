// UI-005h: the SDI output copies each rendered frame to memory with a GPU copy into a shared buffer (about four times faster than
// `getBytes` for a picture that is not flat; see wf-looks-probe readback). The bytes it hands the card must be the ones the compositor draws.
import Testing
import Foundation
import Domain
import RenderEngine
@testable import OutputEngine

@Suite struct UI005h_SDIReadbackTests {
    private func scenes() -> [SceneDescription] {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Through many dangers", secondary: "Qua bao hi\u{1EC3}m nguy")])))
        state.apply(.trigger(index: 0))
        return [ScreenRole.audience, .stage, .broadcast].map { SceneComposer.scene(for: $0, state: state, clockText: "9:14") }
    }

    @Test func theFrameTheCardGetsIsTheFrameTheCompositorDraws() throws {
        // The built-in looks name Inter, which the app registers before any screen draws; register it before the first picture, not at some
        // point between the two (FIX-L: that was the intermittent failure).
        #expect(OutputTestFonts.registerInter(), "the bundled Inter could not be registered, so the looks would be drawn in the system font")
        let compositor = try Compositor()
        for scene in scenes() {
            let renderer = SDIFrameRenderer(width: 1280, height: 720, ringSize: 4, sceneProvider: { scene }, videoSource: nil, mediaSource: nil)
            let frame = try #require(renderer.frame())
            let expected = try compositor.renderImage(scene: scene, width: 1280, height: 720)
            #expect(frame.width == 1280 && frame.height == 720)
            #expect(PixelDiff.describe(frame.bgra, expected.bgra, width: 1280) == nil, "the frame the card gets is not the frame the compositor draws")
            #expect(renderer.lastError == nil && renderer.bufferReallocations == 0)
            // The next frames reuse the ring and stay equal: the copy does not leak an earlier frame into a later one.
            let again = try #require(renderer.frame())
            #expect(PixelDiff.describe(again.bgra, expected.bgra, width: 1280) == nil, "the next frame is not the frame the compositor draws")
            #expect(renderer.bufferReallocations == 0)
        }
    }
}
