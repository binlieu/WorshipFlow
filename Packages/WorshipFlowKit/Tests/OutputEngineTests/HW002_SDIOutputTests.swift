// HW-002 / SCRN-11, SCRN-10: SDIOutput against the simulated card. Verification level: Simulated, never Hardware Verified.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var mainThreadCalls = 0, total = 0
    func record() { lock.lock(); total += 1; if Thread.isMainThread { mainThreadCalls += 1 }; lock.unlock() }
    var snapshot: (total: Int, onMain: Int) { lock.lock(); defer { lock.unlock() }; return (total, mainThreadCalls) }
}

func lowerThirdScene(alpha: Double = 1) -> SceneDescription {
    SceneDescription(backgroundColor: .clear, textLayers: [], objectLayers: [
        .shape(ShapeLayer(shape: .rectangle, fill: ColorRGBA(red: 1, green: 0, blue: 0, alpha: alpha),
                          frame: NormalizedRect(x: 0.1, y: 0.7, width: 0.8, height: 0.15))),
    ])
}

extension SDIFrame {
    func pixel(_ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(bgra[i]), Int(bgra[i + 1]), Int(bgra[i + 2]), Int(bgra[i + 3]))
    }
}

/// Heavy loops run off the main thread, so a long test never keeps the main queue from other suites in the same
/// process (AVFoundation tests, for one, need it to deliver their callbacks).
func advanceOffMain(_ device: SimulatedSDIDevice, frames: Int) async {
    await Task.detached { device.advance(frames: frames) }.value
}

@MainActor
func waitFor(timeout: Double = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
struct SDIRig {
    let device = SimulatedSDIDevice(info: .simulatedDuo2)

    func output(connector: Int, keying: SDIKeying = .none, mode: SDIVideoMode = .hd1080p5994, scene: SceneDescription,
                clock: (any SDIOutputClock)? = nil, log: CallLog? = nil, name: String = "SDI") throws -> SDIOutput {
        let port = try device.openOutput(connector: connector)
        return SDIOutput(name: name, port: port, mode: mode, keying: keying, isSimulated: true,
                         sceneProvider: { log?.record(); return scene }, clock: clock)
    }
}

@MainActor
@Suite(.serialized) struct HW002_SDIOutputTests {
    /// Acceptance: a 600-frame run through SDIOutput, zero late and zero dropped.
    @Test func sixHundredFramesWithZeroLateAndZeroDropped() async throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 1, scene: lowerThirdScene())
        try out.start()
        out.waitUntilStarted()
        #expect(out.status == .running)
        await advanceOffMain(rig.device, frames: 600)
        let s = out.statistics
        #expect(s.presentedFrames == 600)
        #expect(s.droppedFrames == 0 && s.lateFrames == 0)
        let report = try #require(out.sdiReport)
        #expect(report.health == .ok && report.repeatedFrames == 0 && report.isSimulated)
        #expect(out.refreshRate > 59.9 && out.refreshRate < 60)
        out.stop()
        #expect(out.status == .stopped(reason: nil))
    }

    @Test func aKeyedOutputPutsFillOnTheFirstConnectorAndKeyOnTheSecond() throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 1, keying: .external(fillAlphaMode: .premultiplied), scene: lowerThirdScene())
        try out.start(); out.waitUntilStarted()
        rig.device.advance(frames: 5)
        let fill = try #require(rig.device.lastDisplayed(onConnector: 1))
        let key = try #require(rig.device.lastDisplayed(onConnector: 2))
        #expect(fill.width == 1920 && fill.height == 1080 && key.width == 1920)
        // Inside the lower-third bar: red fill, white key. Outside: black fill, black key.
        let (fb, fg, fr, fa) = fill.pixel(960, 800)
        #expect(fr == 255 && fg == 0 && fb == 0 && fa == 255)
        let (kb, kg, kr, ka) = key.pixel(960, 800)
        #expect(kr == 255 && kg == 255 && kb == 255 && ka == 255)
        let (ob, og, or, _) = fill.pixel(960, 100)
        #expect(or == 0 && og == 0 && ob == 0)
        let (xb, xg, xr, xa) = key.pixel(960, 100)
        #expect(xr == 0 && xg == 0 && xb == 0 && xa == 255)
        #expect(rig.device.lastDisplayed(onConnector: 3) == nil)
    }

    @Test func straightAlphaDividesTheColourOutOfTheFill() throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 1, keying: .external(fillAlphaMode: .straight), scene: lowerThirdScene(alpha: 0.5))
        try out.start(); out.waitUntilStarted()
        rig.device.advance(frames: 3)
        let fill = try #require(rig.device.lastDisplayed(onConnector: 1)).pixel(960, 800)
        let key = try #require(rig.device.lastDisplayed(onConnector: 2)).pixel(960, 800)
        #expect(abs(fill.r - 255) <= 3 && fill.g <= 1 && fill.b <= 1)
        #expect(abs(key.r - 128) <= 2 && key.r == key.g && key.g == key.b)
    }

    @Test func premultipliedAlphaKeepsTheColourMultiplied() throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 1, keying: .external(fillAlphaMode: .premultiplied), scene: lowerThirdScene(alpha: 0.5))
        try out.start(); out.waitUntilStarted()
        rig.device.advance(frames: 3)
        let fill = try #require(rig.device.lastDisplayed(onConnector: 1)).pixel(960, 800)
        #expect(abs(fill.r - 128) <= 2)
    }

    @Test func aKeyedOutputWithAnOpaqueBackgroundWarnsThatNothingWillKey() throws {
        let rig = SDIRig()
        let opaque = SceneDescription(backgroundColor: ColorRGBA(red: 0.04, green: 0.06, blue: 0.14), textLayers: [])
        let keyed = try rig.output(connector: 1, keying: .external(fillAlphaMode: .premultiplied), scene: opaque)
        let plain = try rig.output(connector: 3, scene: opaque)
        let good = try rig.output(connector: 4, scene: lowerThirdScene())
        for o in [keyed, plain, good] { try o.start(); o.waitUntilStarted() }
        rig.device.advance(frames: 3)
        #expect(keyed.sdiReport?.warnings == [SDIOutput.opaqueKeyWarning])
        #expect(SDIOutput.opaqueKeyWarning.hasPrefix("Nothing will key: background is opaque"))
        #expect(plain.sdiReport?.warnings.isEmpty == true)          // only a keyed output has anything to key
        let transparentKeyed = try SDIRig().output(connector: 1, keying: .external(fillAlphaMode: .premultiplied), scene: lowerThirdScene())
        try transparentKeyed.start(); transparentKeyed.waitUntilStarted()
        #expect(transparentKeyed.sdiReport?.warnings.isEmpty == true)
    }

    @Test func opaqueSceneRulesCoverVideoImagesAndMedia() {
        func opaque(_ s: SceneDescription) -> Bool { SDIOutput.isOpaque(s) }
        #expect(!opaque(SceneDescription(backgroundColor: .clear, textLayers: [])))
        #expect(opaque(SceneDescription(backgroundColor: .black, textLayers: [])))
        #expect(opaque(SceneDescription(backgroundColor: .clear, showsVideo: true, textLayers: [])))
        #expect(opaque(SceneDescription(backgroundColor: .clear, textLayers: [], backgroundMedia: .image(UUID()))))
        #expect(opaque(SceneDescription(backgroundColor: .clear, textLayers: [], foregroundMedia: .video(UUID()))))
        #expect(opaque(SceneDescription(backgroundColor: .clear, textLayers: [], backgroundImage: ImageLayer(path: "/x.png", frame: .full, opacity: 1, contentMode: .fill))))
    }

    /// Acceptance: unplug stops that output only and says why; the card coming back does not revive the old output.
    @Test func unplugStopsTheOutputAndReportsIt() async throws {
        let rig = SDIRig()
        let a = try rig.output(connector: 1, scene: lowerThirdScene(), name: "A")
        try a.start(); a.waitUntilStarted()
        var seen: [OutputStatus] = []
        a.onStatusChange = { seen.append($0) }
        rig.device.advance(frames: 10)
        rig.device.simulateUnplug()
        #expect(await waitFor { if case .stopped = a.status { return true } else { return false } })
        guard case .stopped(let reason) = a.status, let reason else { Issue.record("expected a reason"); return }
        #expect(reason.contains("SDI card"))
        #expect(seen.count == 1)
        a.stop()
        #expect(seen.count == 1)
    }

    @Test func aStoppedOutputGivesItsConnectorBack() throws {
        let rig = SDIRig()
        let a = try rig.output(connector: 1, keying: .external(fillAlphaMode: .premultiplied), scene: lowerThirdScene())
        try a.start(); a.waitUntilStarted()
        a.stop()
        // The fill connector and the key connector are both free again.
        _ = try rig.device.openOutput(connector: 1)
        _ = try rig.device.openOutput(connector: 2)
    }

    @Test func aKeyedStartOnAnEvenConnectorIsRefusedAtOnce() throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 2, keying: .external(fillAlphaMode: .premultiplied), scene: lowerThirdScene())
        #expect(throws: SDIError.self) { try out.start() }
        #expect(out.status != .running)
    }

    @Test func aModeTheCardRefusesIsRefusedAtStart() throws {
        let rig = SDIRig()
        let odd = SDIVideoMode(width: 640, height: 480, frameDurationValue: 1000, timeScale: 30000, name: "480p30")
        let out = try rig.output(connector: 1, mode: odd, scene: lowerThirdScene())
        #expect(throws: SDIError.self) { try out.start() }
    }

    /// Acceptance: a mirror shows the same pixels as its primary.
    @Test func aMirrorShowsTheSamePixelsAsItsPrimary() async throws {
        let rig = SDIRig()
        let scene = lowerThirdScene()
        let primary = try rig.output(connector: 1, scene: scene, name: "Primary")
        let mirror = try rig.output(connector: 3, scene: scene, name: "Mirror")
        for o in [primary, mirror] { try o.start(); o.waitUntilStarted() }
        await advanceOffMain(rig.device, frames: 30)
        let a = try #require(rig.device.lastDisplayed(onConnector: 1))
        let b = try #require(rig.device.lastDisplayed(onConnector: 3))
        #expect(a == b)
        #expect(a.pixel(960, 800).r == 255)
    }

    @Test func steadyStateReusesItsBuffers() async throws {
        let rig = SDIRig()
        let out = try rig.output(connector: 1, scene: lowerThirdScene())
        try out.start(); out.waitUntilStarted()
        await advanceOffMain(rig.device, frames: 40)   // warm-up: every slot of the ring is filled once
        let before = out.bufferReallocations
        await advanceOffMain(rig.device, frames: 600)
        #expect(out.bufferReallocations == before, "a frame buffer was copied or allocated in steady state")
        #expect(out.renderTiming.frames >= 640)
    }

    @Test func aLiveSimulatedOutputRendersAndReadsBackOffTheMainThread() async throws {
        let rig = SDIRig()
        let clock = SimulatedClockDriver(device: rig.device, mode: .hd1080p5994)
        let log = CallLog()
        let out = try rig.output(connector: 1, scene: lowerThirdScene(), clock: clock, log: log)
        try out.start()
        #expect(await waitFor(timeout: 5) { out.statistics.presentedFrames >= 30 })
        out.stop()
        let calls = log.snapshot
        #expect(calls.total >= 30)
        #expect(calls.onMain == 0, "the scene was read on the main thread \(calls.onMain) times")
        #expect(out.sdiReport?.health != .failing)
    }

    @Test func theLiveClockStopsWhenTheOutputStops() async throws {
        let rig = SDIRig()
        let clock = SimulatedClockDriver(device: rig.device, mode: .hd1080p5994)
        let out = try rig.output(connector: 1, scene: lowerThirdScene(), clock: clock)
        try out.start()
        #expect(await waitFor(timeout: 5) { out.statistics.presentedFrames >= 5 })
        out.stop()
        try await Task.sleep(for: .milliseconds(60))
        let frozen = out.statistics.presentedFrames
        try await Task.sleep(for: .milliseconds(120))
        #expect(out.statistics.presentedFrames == frozen)
    }

    @Test func aNewSceneShowsOnTheNextFrame() throws {
        let rig = SDIRig()
        let box = HW002SceneBox()
        box.set(lowerThirdScene())
        let port = try rig.device.openOutput(connector: 1)
        let out = SDIOutput(name: "x", port: port, mode: .hd1080p5994, keying: .none, isSimulated: true, sceneProvider: { box.get() })
        try out.start(); out.waitUntilStarted()
        rig.device.advance(frames: 10)
        #expect(try #require(rig.device.lastDisplayed(onConnector: 1)).pixel(960, 800).r == 255)
        box.set(SceneDescription(backgroundColor: ColorRGBA(red: 0, green: 0, blue: 1), textLayers: []))
        rig.device.advance(frames: 10)
        let p = try #require(rig.device.lastDisplayed(onConnector: 1)).pixel(960, 800)
        #expect(p.b == 255 && p.r == 0)
    }
}

final class HW002SceneBox: @unchecked Sendable {
    private let lock = NSLock(); private var scene = SceneDescription(backgroundColor: .black, textLayers: [])
    func set(_ s: SceneDescription) { lock.lock(); scene = s; lock.unlock() }
    func get() -> SceneDescription { lock.lock(); defer { lock.unlock() }; return scene }
}
