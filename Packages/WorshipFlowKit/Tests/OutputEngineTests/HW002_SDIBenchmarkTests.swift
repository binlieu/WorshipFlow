// HW-002 / UNV-04: four simulated SDI outputs at 1080p59.94, driven as fast as possible for 600 frames, with readback.
// Prints mean and worst time per frame; asserts only a generous ceiling so it does not flake. Simulated: the card is
// a simulator, so this measures composition, GPU completion and the copy to memory, not any real SDI path.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@MainActor
@Suite(.serialized) struct HW002_SDIBenchmarkTests {
    func scenes() -> [SceneDescription] {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
            SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu một người tội lỗi như tôi"),
        ])))
        state.apply(.trigger(index: 0))
        return [ScreenRole.audience, .stage, .broadcast, .audience].map { SceneComposer.scene(for: $0, state: state, clockText: "10:32") }
    }

    private func run(keyedPairs: Bool, label: String) async throws -> (mean: Double, worst: Double, perOutputMean: Double, perOutputWorst: Double) {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let all = scenes()
        var outputs: [SDIOutput] = []
        if keyedPairs {
            for (i, connector) in [1, 3].enumerated() {
                let port = try device.openOutput(connector: connector)
                outputs.append(SDIOutput(name: "key\(i)", port: port, mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied),
                                         isSimulated: true, sceneProvider: { all[2] }))
            }
        } else {
            for connector in 1...4 {
                let port = try device.openOutput(connector: connector)
                let scene = all[connector - 1]
                outputs.append(SDIOutput(name: "out\(connector)", port: port, mode: .hd1080p5994, keying: .none,
                                         isSimulated: true, sceneProvider: { scene }))
            }
        }
        for o in outputs { try o.start(); o.waitUntilStarted() }
        await advanceOffMain(device, frames: 10)         // warm-up: shaders, text cache, every buffer in the ring
        for o in outputs { o.resetRenderTiming() }
        let frames = 600
        // Off the main thread: 600 frames of four full HD renders would otherwise hold the main queue for seconds.
        let times: [Double] = await Task.detached {
            var times: [Double] = []
            times.reserveCapacity(frames)
            for _ in 0..<frames {
                let start = DispatchTime.now().uptimeNanoseconds
                device.advance(frames: 1)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return times
        }.value
        let mean = times.reduce(0, +) / Double(frames)
        let worst = times.max() ?? 0
        let p99 = times.sorted()[Int(Double(frames) * 0.99)]
        let timings = outputs.map(\.renderTiming)
        let outMean = timings.map(\.meanMs).reduce(0, +) / Double(timings.count)
        let outWorst = timings.map(\.worstMs).max() ?? 0
        let late = outputs.reduce(0) { $0 + $1.statistics.lateFrames }, dropped = outputs.reduce(0) { $0 + $1.statistics.droppedFrames }
        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif
        print(String(format: "HW-002 BENCHMARK [%@] %@: %d frames, %d outputs, per frame (all outputs): mean %.3f ms, p99 %.3f ms, worst %.3f ms; per output render+readback: mean %.3f ms, worst %.3f ms; late %d, dropped %d",
                     config, label, frames, outputs.count, mean, p99, worst, outMean, outWorst, late, dropped))
        for o in outputs { o.stop() }
        return (mean, worst, outMean, outWorst)
    }

    @Test func fourSimulatedSDIOutputsAtFullHD() async throws {
        let r = try await run(keyedPairs: false, label: "four 1920x1080 1080p59.94 outputs")
        #expect(r.mean < 16.0)         // the frame period; generous, and only a ceiling
    }

    @Test func twoKeyedPairsOnTheSameCard() async throws {
        let r = try await run(keyedPairs: true, label: "two keyed fill+key pairs (four connectors)")
        #expect(r.mean < 200.0)         // includes the simulator splitting each frame, which a real card does in hardware
    }
}
