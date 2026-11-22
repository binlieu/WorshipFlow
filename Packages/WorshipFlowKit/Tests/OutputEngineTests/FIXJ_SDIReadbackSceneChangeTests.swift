// FIX-J item 9 (UI-005h): the SDI output's readback (a GPU copy into a ring of shared buffers) must deliver exactly the new scene after the
// scene changes. A stale-buffer regression (a ring slot not rewritten, a copy that was not waited for) would hand the card the picture before.
import Testing
import Foundation
import Domain
import RenderEngine
@testable import OutputEngine

// @unchecked Sendable: `scene` is read and written under `lock`.
private final class SceneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var scene: SceneDescription
    init(_ scene: SceneDescription) { self.scene = scene }
    func set(_ s: SceneDescription) { lock.lock(); scene = s; lock.unlock() }
    func get() -> SceneDescription { lock.lock(); defer { lock.unlock() }; return scene }
}

@Suite struct FIXJ_SDIReadbackSceneChangeTests {
    private func scene(_ primary: String, _ role: ScreenRole = .audience) -> SceneDescription {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: primary)])))
        state.apply(.trigger(index: 0))
        // The Classic theme is set in Helvetica Neue: the built-in looks name the bundled Inter, which other tests in the same process register at
        // some point, so a picture of them can differ before and after that (a race in the test, not in the output).
        return SceneComposer.scene(for: role, state: state, theme: .classicFullScreen, look: .standard, props: [])
    }

    @Test func aChangedSceneIsDeliveredExactlyAndNotThePictureBefore() throws {
        let a = scene("First slide of the morning"), b = scene("Second slide, quite different words")
        #expect(a != b)
        let compositor = try Compositor()
        let ea = try compositor.renderImage(scene: a, width: 1280, height: 720).bgra
        let eb = try compositor.renderImage(scene: b, width: 1280, height: 720).bgra
        let differ = ea != eb
        #expect(differ, "the two scenes draw different pictures")
        let box = SceneBox(a)
        let renderer = SDIFrameRenderer(width: 1280, height: 720, ringSize: 4, sceneProvider: { box.get() }, videoSource: nil, mediaSource: nil)
        var delivered: [Int] = []      // hashes, not the arrays: holding a slot's array would make the next write copy it (that is what `bufferReallocations` counts)
        // A, then B, then A, then B again, each a few frames, so every slot of the ring is written with each scene.
        for (s, expected) in [(a, ea), (b, eb), (a, ea), (b, eb)] {
            box.set(s)
            for _ in 0..<5 {
                let frame = try #require(renderer.frame())
                let same = frame.bgra == expected      // a Bool: a failing array comparison would print millions of bytes
                #expect(same, "a frame after the scene changed is not the new scene")
                delivered.append(frame.bgra.hashValue)
            }
        }
        #expect(Set(delivered).count == 2, "exactly the two pictures were delivered")
        #expect(renderer.lastError == nil && renderer.bufferReallocations == 0)
    }

    @Test func theFirstFrameAfterAChangeIsAlreadyTheNewPicture() throws {
        let compositor = try Compositor()
        let first = scene("Before"), second = scene("After the change")
        let box = SceneBox(first)
        let renderer = SDIFrameRenderer(width: 640, height: 360, ringSize: 2, sceneProvider: { box.get() }, videoSource: nil, mediaSource: nil)
        _ = try #require(renderer.frame())
        box.set(second)
        let frame = try #require(renderer.frame())
        let same = frame.bgra == (try compositor.renderImage(scene: second, width: 640, height: 360)).bgra
        #expect(same, "the first frame after the change is not the new scene")
    }
}
