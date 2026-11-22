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
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "My chains are gone", secondary: "Xi\u{1EC1}ng x\u{00ED}ch \u{0111}\u{00E3} tan")])))
        state.apply(.trigger(index: 0))
        return [ScreenRole.audience, .stage, .broadcast].map { SceneComposer.scene(for: $0, state: state, clockText: "9:14") }
    }

    @Test func theFrameTheCardGetsIsTheFrameTheCompositorDraws() throws {
        let compositor = try Compositor()
        for scene in scenes() {
            let renderer = SDIFrameRenderer(width: 1280, height: 720, ringSize: 4, sceneProvider: { scene }, videoSource: nil, mediaSource: nil)
            let frame = try #require(renderer.frame())
            let expected = try compositor.renderImage(scene: scene, width: 1280, height: 720)
            #expect(frame.width == 1280 && frame.height == 720)
            #expect(frame.bgra == expected.bgra)
            #expect(renderer.lastError == nil && renderer.bufferReallocations == 0)
            // The next frames reuse the ring and stay equal: the copy does not leak an earlier frame into a later one.
            let again = try #require(renderer.frame())
            #expect(again.bgra == expected.bgra && renderer.bufferReallocations == 0)
        }
    }
}
