// OUT-002 benchmark: four 1080p scenes per frame, 600 frames, offscreen, GPU-complete each frame (NFR-02, NFR-03).
// Prints mean and worst frame time; asserts only a generous ceiling so it does not flake.
import Testing
import Foundation
import Metal
import Domain
@testable import RenderEngine

@Suite(.serialized) struct FourOutputBenchmarkTests {
    @Test func fourFullHDScenesPerFrame() throws {
        let compositor = try Compositor()
        let device = compositor.device

        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
            SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu một người tội lỗi như tôi"),
        ])))
        state.apply(.trigger(index: 0))
        let roles: [ScreenRole] = [.audience, .stage, .broadcast, .audience]
        let scenes = roles.map { SceneComposer.scene(for: $0, state: state, clockText: "10:32") }

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private
        let targets = try roles.map { _ in try #require(device.makeTexture(descriptor: td)) }

        func renderOneFrame() throws {
            let cb = try #require(compositor.makeCommandBuffer())
            for (scene, target) in zip(scenes, targets) {
                try compositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb)
            }
            cb.commit()
            cb.waitUntilCompleted()
            #expect(cb.error == nil)
        }

        for _ in 0..<10 { try renderOneFrame() }   // warm-up: shader, text cache

        let frames = 600
        var times: [Double] = []
        times.reserveCapacity(frames)
        for _ in 0..<frames {
            let start = DispatchTime.now().uptimeNanoseconds
            try renderOneFrame()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let mean = times.reduce(0, +) / Double(frames)
        let worst = times.max() ?? 0
        let sorted = times.sorted()
        let p99 = sorted[Int(Double(frames) * 0.99)]
        print(String(format: "OUT-002 BENCHMARK four 1920x1080 outputs/frame, %d frames: mean %.3f ms, p99 %.3f ms, worst %.3f ms",
                     frames, mean, p99, worst))
        #expect(mean < 16.0)
    }
}
