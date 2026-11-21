// HW-001 / KEY-001 acceptance tests: SDI scheduling, connector planning, fill and key, simulator
// (SCRN-10, SCRN-11, HW-09, HW-11, NFR-01, NFR-05; ADR-0005). Verification level reachable here: Simulated.
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import SDIEngine

@Suite struct SDIVideoModeTests {
    @Test func productionModeIs1080p5994() {
        let m = SDIVideoMode.hd1080p5994
        #expect(m.width == 1920 && m.height == 1080)
        #expect(m.frameDurationValue == 1001 && m.timeScale == 60000)
        #expect(abs(m.framesPerSecond - 59.94) < 0.001)
    }

    /// HW-09: 59.94 and 60 are different modes and never compare equal.
    @Test func fiftyNineNinetyFourIsNotSixty() {
        #expect(SDIVideoMode.hd1080p5994 != SDIVideoMode.hd1080p60)
        #expect(SDIVideoMode.hd1080p60.frameDurationValue == 1000 && SDIVideoMode.hd1080p60.timeScale == 60000)
        #expect(SDIVideoMode.allKnown.contains(.hd1080p5994) && SDIVideoMode.allKnown.contains(.hd1080p50))
    }

    /// NG-1: nothing above HD is offered for this class of card.
    @Test func noModeExceedsHD() {
        #expect(SDIVideoMode.allKnown.allSatisfy { $0.width <= 1920 && $0.height <= 1080 })
    }
}

@Suite struct SDISchedulerTests {
    @Test func startPrerollsThenStartsPlayback() {
        var s = SDIScheduler(prerollFrames: 3, maxBufferedFrames: 5)
        #expect(s.isRunning == false)
        #expect(s.start() == [.schedule(frameIndex: 0), .schedule(frameIndex: 1), .schedule(frameIndex: 2), .startPlayback(atFrame: 0)])
        #expect(s.isRunning)
        #expect(s.start().isEmpty)                         // starting twice does nothing
        #expect(s.statistics.scheduled == 3)
    }

    @Test func eachCompletionTopsTheBufferBackUp() {
        var s = SDIScheduler(prerollFrames: 3, maxBufferedFrames: 5)
        _ = s.start()
        #expect(s.frameCompleted(.completed, bufferedFrames: 2) == [.schedule(frameIndex: 3)])
        #expect(s.frameCompleted(.completed, bufferedFrames: 3).isEmpty)                     // already full
        #expect(s.frameCompleted(.completed, bufferedFrames: 2) == [.schedule(frameIndex: 4)])
        #expect(s.statistics.completed == 3 && s.statistics.scheduled == 5)
    }

    /// After an underrun the buffer is refilled in one go, never beyond the cap.
    @Test func underrunRefillsButStaysBounded() {
        var s = SDIScheduler(prerollFrames: 3, maxBufferedFrames: 4)
        _ = s.start()
        #expect(s.frameCompleted(.dropped, bufferedFrames: 0) == [.schedule(frameIndex: 3), .schedule(frameIndex: 4), .schedule(frameIndex: 5)])
        // A device reporting more buffered frames than the cap never gets more.
        #expect(s.frameCompleted(.completed, bufferedFrames: 9).isEmpty)
    }

    @Test func countsLateDroppedAndFlushed() {
        var s = SDIScheduler(prerollFrames: 3, maxBufferedFrames: 5)
        _ = s.start()
        _ = s.frameCompleted(.completed, bufferedFrames: 3)
        _ = s.frameCompleted(.displayedLate, bufferedFrames: 3)
        _ = s.frameCompleted(.dropped, bufferedFrames: 3)
        _ = s.frameCompleted(.flushed, bufferedFrames: 3)
        #expect(s.statistics.completed == 1 && s.statistics.late == 1 && s.statistics.dropped == 1 && s.statistics.flushed == 1)
    }

    /// NFR-02 / NFR-05: health degrades on a burst of bad frames and recovers after a clean stretch.
    @Test func healthDegradesAndRecovers() {
        var s = SDIScheduler(prerollFrames: 3, maxBufferedFrames: 5)
        _ = s.start()
        #expect(s.health == .ok)
        for _ in 0..<2 { _ = s.frameCompleted(.dropped, bufferedFrames: 3) }
        #expect(s.health == .ok)                           // two bad frames in the window is tolerated
        _ = s.frameCompleted(.displayedLate, bufferedFrames: 3)
        #expect(s.health == .degraded)
        for _ in 0..<27 { _ = s.frameCompleted(.dropped, bufferedFrames: 3) }
        #expect(s.health == .failing)                      // thirty bad frames in the last 120
        for _ in 0..<120 { _ = s.frameCompleted(.completed, bufferedFrames: 3) }
        #expect(s.health == .ok)
    }

    @Test func stopIgnoresLaterCompletionsAndCanRestart() {
        var s = SDIScheduler(prerollFrames: 2, maxBufferedFrames: 4)
        _ = s.start()
        _ = s.frameCompleted(.completed, bufferedFrames: 1)
        s.stop()
        #expect(s.isRunning == false)
        #expect(s.frameCompleted(.completed, bufferedFrames: 0).isEmpty)
        // A restart begins a fresh timeline at frame zero with fresh statistics.
        #expect(s.start() == [.schedule(frameIndex: 0), .schedule(frameIndex: 1), .startPlayback(atFrame: 0)])
        #expect(s.statistics.completed == 0)
    }

    @Test func nonsenseSettingsAreClamped() {
        var s = SDIScheduler(prerollFrames: 0, maxBufferedFrames: -3)
        #expect(s.start().count >= 2)                       // at least one frame scheduled plus startPlayback
    }
}

@Suite struct SDIConnectorPlannerTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
    func req(_ id: UUID, _ connector: Int, keying: Bool = false) -> SDIOutputRequest { SDIOutputRequest(screenID: id, connector: connector, keying: keying) }

    /// Master spec plan A: four independent outputs.
    @Test func fourIndependentOutputs() {
        let plan = SDIConnectorPlanner.plan(requests: [req(a, 1), req(b, 2), req(c, 3), req(d, 4)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults.isEmpty && plan.connectorsUsed == 4)
        #expect(plan.assignments[a] == SDIAssignment(connector: 1, keyConnector: nil))
        #expect((1...4).map { plan.role(of: $0) } == [.output(a), .output(b), .output(c), .output(d)])
    }

    /// Master spec plan B: fill and key on 1 and 2, two more outputs on 3 and 4. HW-11: keying consumes two connectors.
    @Test func fillAndKeyPlusTwoOutputs() {
        let plan = SDIConnectorPlanner.plan(requests: [req(a, 1, keying: true), req(b, 3), req(c, 4)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults.isEmpty && plan.connectorsUsed == 4)
        #expect(plan.assignments[a] == SDIAssignment(connector: 1, keyConnector: 2))
        #expect((1...4).map { plan.role(of: $0) } == [.fill(a), .key(a), .output(b), .output(c)])
    }

    @Test func twoKeyedOutputsUseAllFour() {
        let plan = SDIConnectorPlanner.plan(requests: [req(a, 1, keying: true), req(b, 3, keying: true)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults.isEmpty)
        #expect(plan.assignments[b] == SDIAssignment(connector: 3, keyConnector: 4))
    }

    /// Never guess: a keyed output must start on the first connector of a pair, and its partner must be free.
    @Test func keyingConflictsAreFaultsNotGuesses() {
        var plan = SDIConnectorPlanner.plan(requests: [req(a, 2, keying: true)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults[a] == .keyingNeedsFirstConnectorOfAPair && plan.assignments.isEmpty)
        plan = SDIConnectorPlanner.plan(requests: [req(a, 2), req(b, 1, keying: true)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.assignments[a] == SDIAssignment(connector: 2, keyConnector: nil))      // earlier request keeps its connector
        #expect(plan.faults[b] == .pairedConnectorInUse(by: a))
        plan = SDIConnectorPlanner.plan(requests: [req(a, 1, keying: true), req(b, 2)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults[b] == .connectorInUse(by: a))                                    // 2 is carrying a's key
        plan = SDIConnectorPlanner.plan(requests: [req(a, 1, keying: true)], connectorCount: 4, supportsExternalKeying: false)
        #expect(plan.faults[a] == .keyingUnsupported)
    }

    @Test func duplicateAndOutOfRangeConnectors() {
        let plan = SDIConnectorPlanner.plan(requests: [req(a, 1), req(b, 1), req(c, 0), req(d, 5), req(e, 4)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.assignments.keys.sorted { $0.uuidString < $1.uuidString } == [a, e].sorted { $0.uuidString < $1.uuidString })
        #expect(plan.faults[b] == .connectorInUse(by: a))
        #expect(plan.faults[c] == .connectorOutOfRange && plan.faults[d] == .connectorOutOfRange)
        #expect(plan.role(of: 2) == .unused && plan.role(of: 9) == .unused)
    }

    @Test func faultsExplainThemselves() {
        for f in [SDIPlanFault.connectorOutOfRange, .connectorInUse(by: a), .keyingNeedsFirstConnectorOfAPair, .pairedConnectorInUse(by: a), .keyingUnsupported] {
            #expect(f.operatorMessage.count > 15)
        }
    }
}

@Suite struct FillKeySplitterTests {
    // Pixels are BGRA, premultiplied, as the compositor produces them.
    let opaqueRed: [UInt8] = [0, 0, 255, 255]
    let halfWhite: [UInt8] = [128, 128, 128, 128]
    let clear: [UInt8] = [0, 0, 0, 0]

    /// The key is the alpha as a grey level, fully opaque. Black is not transparency: clear pixels key to black.
    @Test func keyIsAlphaAsLuma() {
        let out = FillKeySplitter.split(bgra: opaqueRed + halfWhite + clear, fillAlphaMode: .premultiplied)
        #expect(out.key == [255, 255, 255, 255,  128, 128, 128, 255,  0, 0, 0, 255])
    }

    @Test func premultipliedFillKeepsColourAndBecomesOpaque() {
        let out = FillKeySplitter.split(bgra: opaqueRed + halfWhite + clear, fillAlphaMode: .premultiplied)
        #expect(out.fill == [0, 0, 255, 255,  128, 128, 128, 255,  0, 0, 0, 255])
    }

    /// For a switcher expecting a straight (unshaped) fill, colour is divided by alpha.
    @Test func straightFillUnpremultiplies() {
        let out = FillKeySplitter.split(bgra: opaqueRed + halfWhite + clear, fillAlphaMode: .straight)
        #expect(out.fill == [0, 0, 255, 255,  255, 255, 255, 255,  0, 0, 0, 255])
        let dim = FillKeySplitter.split(bgra: [10, 20, 30, 60], fillAlphaMode: .straight).fill   // 10/60, 20/60, 30/60 of 255, rounded
        #expect(dim == [43, 85, 128, 255] || dim == [42, 85, 127, 255] || dim == [43, 85, 127, 255] || dim == [42, 85, 128, 255])
    }

    @Test func sizesMatchAndTruncatedInputIsSafe() {
        let out = FillKeySplitter.split(bgra: opaqueRed + [1, 2, 3], fillAlphaMode: .premultiplied)   // 7 bytes: one whole pixel
        #expect(out.fill.count == 4 && out.key.count == 4)
        #expect(FillKeySplitter.split(bgra: [], fillAlphaMode: .straight).key.isEmpty)
    }
}

/// Collects completions from the simulator's callback thread.
final class CompletionLog: @unchecked Sendable {
    private let lock = NSLock(); private var items: [SDIFrameCompletion] = []
    func add(_ c: SDIFrameCompletion) { lock.lock(); items.append(c); lock.unlock() }
    var all: [SDIFrameCompletion] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct SimulatedSDIDeviceTests {
    func frame(_ value: UInt8, alpha: UInt8 = 255) -> SDIFrame {
        SDIFrame(width: 2, height: 1, bgra: [value, value, value, alpha, value, value, value, alpha])
    }

    @Test func simulatedDuo2DescribesItself() {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        #expect(device.info.connectorCount == 4 && device.info.supportsExternalKeying)
        #expect(device.info.isSimulated)                    // never mistaken for real hardware
        #expect(device.info.displayName.localizedCaseInsensitiveContains("simulat"))
    }

    @Test func playsScheduledFramesInOrderOnItsOwnClock() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        #expect(port.supports(mode: .hd1080p5994, keying: .none))
        try port.enable(mode: .hd1080p5994, keying: .none)
        let log = CompletionLog()
        port.onFrameCompleted = { log.add($0) }
        for i in 0..<3 { try port.schedule(frame(UInt8(i)), atFrame: Int64(i)) }
        #expect(port.bufferedFrameCount == 3)
        port.startPlayback(atFrame: 0)
        device.advance(frames: 2)
        #expect(log.all.map(\.frameIndex) == [0, 1] && log.all.allSatisfy { $0.result == .completed })
        #expect(port.bufferedFrameCount == 1)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra.first == 1)
    }

    /// A frame scheduled for a time already past is reported late, and an empty buffer is reported as a drop.
    @Test func lateAndUnderrunAreReported() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        try port.enable(mode: .hd1080p5994, keying: .none)
        let log = CompletionLog()
        port.onFrameCompleted = { log.add($0) }
        try port.schedule(frame(1), atFrame: 0)
        port.startPlayback(atFrame: 0)
        device.advance(frames: 3)                           // frame 0 plays; frames 1 and 2 had nothing to show
        #expect(log.all.map(\.result) == [.completed, .dropped, .dropped])
        try port.schedule(frame(2), atFrame: 1)             // in the past now
        device.advance(frames: 1)
        #expect(log.all.last?.result == .displayedLate)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra.first == 2)    // a late frame is still shown
    }

    /// KEY-001: with external keying, connector 1 carries the fill and connector 2 the key, from one frame.
    @Test func externalKeyingDrivesTheConnectorPair() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        #expect(port.supports(mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied)))
        try port.enable(mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied))
        try port.schedule(frame(100, alpha: 128), atFrame: 0)
        port.startPlayback(atFrame: 0)
        device.advance(frames: 1)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra == [100, 100, 100, 255, 100, 100, 100, 255])    // fill
        #expect(device.lastDisplayed(onConnector: 2)?.bgra == [128, 128, 128, 255, 128, 128, 128, 255])    // key
        // The key connector cannot be opened on its own while the pair is keyed.
        #expect(throws: SDIError.self) { _ = try device.openOutput(connector: 2) }
    }

    @Test func refusesWhatTheCardWouldRefuse() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        #expect(throws: SDIError.self) { _ = try device.openOutput(connector: 5) }
        let port = try device.openOutput(connector: 2)
        #expect(port.supports(mode: .hd1080p5994, keying: .external(fillAlphaMode: .straight)) == false)   // 2 is not the first of a pair
        #expect(throws: SDIError.self) { try port.schedule(frame(1), atFrame: 0) }                          // not enabled yet
        try port.enable(mode: .hd1080p5994, keying: .none)
        #expect(throws: SDIError.self) { try port.schedule(SDIFrame(width: 3, height: 3, bgra: [UInt8](repeating: 0, count: 36)), atFrame: 0) }   // wrong size is refused only when it is not the mode's size… see below
        #expect(throws: SDIError.self) { _ = try device.openOutput(connector: 2) }                          // already open
    }

    /// NFR-05: when the device disappears, ports fail with a clear error and the device reports it; nothing crashes.
    @Test func unplugFailsCleanly() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        try port.enable(mode: .hd1080p5994, keying: .none)
        port.startPlayback(atFrame: 0)
        device.simulateUnplug()
        #expect(device.isConnected == false)
        #expect(throws: SDIError.deviceDisconnected) { try port.schedule(frame(1), atFrame: 5) }
        device.advance(frames: 2)                           // harmless
        device.simulateReplug()
        #expect(device.isConnected)
        #expect(throws: SDIError.self) { try port.schedule(frame(1), atFrame: 5) }   // the old port stays dead; a new one must be opened
        _ = try device.openOutput(connector: 1)
    }
}
