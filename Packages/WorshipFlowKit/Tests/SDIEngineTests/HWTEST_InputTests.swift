// HWTEST-001: the input side of the SDI protocols and the simulator's BNC cable (loopback) with fault injection.
// Simulated only: this proves the kit's plumbing, never behaviour on a real card.
import Testing
import Foundation
@testable import SDIEngine

private final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock(); private var items: [T] = []
    func add(_ v: T) { lock.lock(); items.append(v); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

/// A device that implements only what existed before the input side was added: it must keep compiling.
private final class LegacyOnlyDevice: SDIDevice {
    typealias Port = SimulatedSDIOutputPort
    private let inner = SimulatedSDIDevice()
    var info: SDIDeviceInfo { inner.info }
    var isConnected: Bool { inner.isConnected }
    func openOutput(connector: Int) throws -> SimulatedSDIOutputPort { try inner.openOutput(connector: connector) }
}

@Suite struct HWTEST_InputTests {
    private let mode = SDIVideoMode.hd1080p5994

    /// A small frame whose first byte names it, so a received frame can be traced to the one that was sent.
    private func tag(_ i: Int, width: Int = 4, height: Int = 2) -> SDIFrame {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) { bytes[p * 4 + 3] = 255 }
        bytes[0] = UInt8(i)
        return SDIFrame(width: width, height: height, bgra: bytes)
    }

    private func play(_ device: SimulatedSDIDevice, connector: Int, frames: Int, keying: SDIKeying = .none,
                      make: (Int) -> SDIFrame) throws -> SimulatedSDIOutputPort {
        let port = try device.openOutput(connector: connector)
        try port.enable(mode: mode, keying: keying)
        for i in 0..<frames { try port.schedule(make(i), atFrame: Int64(i)) }
        port.startPlayback(atFrame: 0)
        return port
    }

    @Test func aDeviceWithoutAnInputSideStillCompilesAndRefusesInputs() {
        let legacy = LegacyOnlyDevice()
        #expect(throws: SDIError.connectorUnavailable(3)) { _ = try legacy.openInput(connector: 3) }
    }

    @Test func openingAnInputChecksTheConnector() throws {
        let device = SimulatedSDIDevice()
        #expect(throws: SDIError.connectorUnavailable(0)) { _ = try device.openInput(connector: 0) }
        #expect(throws: SDIError.connectorUnavailable(5)) { _ = try device.openInput(connector: 5) }
        let input = try device.openInput(connector: 3)
        #expect(input.connector == 3)
        #expect(throws: SDIError.connectorUnavailable(3)) { _ = try device.openInput(connector: 3) }
        #expect(throws: SDIError.connectorUnavailable(3)) { _ = try device.openOutput(connector: 3) }
        input.close()
        _ = try device.openOutput(connector: 3)
    }

    @Test func anOutputAndAnInputCannotShareAConnector() throws {
        let device = SimulatedSDIDevice()
        _ = try device.openOutput(connector: 1)
        #expect(throws: SDIError.connectorUnavailable(1)) { _ = try device.openInput(connector: 1) }
    }

    @Test func anUnconnectedInputReportsNoSignal() throws {
        let device = SimulatedSDIDevice()
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        input.onFrameReceived = { frames.add($0) }
        try input.enable(mode: nil)
        _ = try play(device, connector: 1, frames: 6) { tag($0) }
        device.advance(frames: 5)
        #expect(input.signal == .noSignal)
        #expect(frames.all.isEmpty)
    }

    @Test func aConnectedInputReceivesWhatTheOutputShowsOneFrameLater() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        let signals = Box<SDIInputSignal>()
        input.onFrameReceived = { frames.add($0) }
        input.onSignalChange = { signals.add($0) }
        try input.enable(mode: nil)
        #expect(input.signal == .noSignal)
        _ = try play(device, connector: 1, frames: 10) { tag($0) }
        device.advance(frames: 5)
        let got = frames.all
        #expect(got.count == 4)                                   // frame 4 is on the wire, not yet received
        #expect(got.map { Int($0.frame.bgra[0]) } == [0, 1, 2, 3])
        #expect(got.map(\.frameNumber) == [0, 1, 2, 3])
        #expect(got.allSatisfy { $0.mode == mode })
        let stamps = got.compactMap(\.hardwareTimestamp)
        #expect(stamps.count == 4)
        #expect(zip(stamps, stamps.dropFirst()).allSatisfy { $1 - $0 == mode.frameDurationValue })
        #expect(input.signal == .locked(mode))
        #expect(signals.all == [.locked(mode)])
    }

    @Test func theSignalIsLostWhenTheOutputStops() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let signals = Box<SDIInputSignal>()
        input.onSignalChange = { signals.add($0) }
        try input.enable(mode: nil)
        let out = try play(device, connector: 1, frames: 10) { tag($0) }
        device.advance(frames: 4)
        #expect(input.signal == .locked(mode))
        out.stopPlayback()
        device.advance(frames: 3)
        #expect(input.signal == .noSignal)
        #expect(signals.all == [.locked(mode), .noSignal])
    }

    @Test func aFixedModeThatDoesNotMatchTheSourceSeesNoSignal() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        input.onFrameReceived = { frames.add($0) }
        #expect(input.supports(mode: .hd1080p60))
        try input.enable(mode: .hd1080p60)
        _ = try play(device, connector: 1, frames: 10) { tag($0) }
        device.advance(frames: 6)
        #expect(input.signal == .noSignal)
        #expect(frames.all.isEmpty)
    }

    @Test func enablingAnUnknownModeThrows() throws {
        let device = SimulatedSDIDevice()
        let input = try device.openInput(connector: 3)
        let odd = SDIVideoMode(width: 3840, height: 2160, frameDurationValue: 1001, timeScale: 60000, name: "2160p59.94")
        #expect(!input.supports(mode: odd))
        #expect(throws: SDIError.unsupportedMode("2160p59.94")) { try input.enable(mode: odd) }
    }

    @Test func aKeyedPairReachesTwoInputsFillAndKey() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        device.connect(output: 2, toInput: 4)
        let fillIn = try device.openInput(connector: 3)
        let keyIn = try device.openInput(connector: 4)
        let fills = Box<SDICapturedFrame>(), keys = Box<SDICapturedFrame>()
        fillIn.onFrameReceived = { fills.add($0) }
        keyIn.onFrameReceived = { keys.add($0) }
        try fillIn.enable(mode: nil); try keyIn.enable(mode: nil)
        // one pixel: colour (10, 20, 30) at alpha 100, premultiplied
        let f = SDIFrame(width: 1, height: 1, bgra: [10, 20, 30, 100])
        _ = try play(device, connector: 1, frames: 4, keying: .external(fillAlphaMode: .premultiplied)) { _ in f }
        device.advance(frames: 3)
        #expect(fills.all.first?.frame.bgra == [10, 20, 30, 255])
        #expect(keys.all.first?.frame.bgra == [100, 100, 100, 255])
    }

    @Test func swappingFillAndKeyIsInjectable() throws {
        let device = SimulatedSDIDevice()
        device.setFaults(SimulatedFaults(swapFillAndKey: true))
        device.connect(output: 1, toInput: 3)
        device.connect(output: 2, toInput: 4)
        let a = try device.openInput(connector: 3), b = try device.openInput(connector: 4)
        let onThree = Box<SDICapturedFrame>(), onFour = Box<SDICapturedFrame>()
        a.onFrameReceived = { onThree.add($0) }; b.onFrameReceived = { onFour.add($0) }
        try a.enable(mode: nil); try b.enable(mode: nil)
        let f = SDIFrame(width: 1, height: 1, bgra: [10, 20, 30, 100])
        _ = try play(device, connector: 1, frames: 4, keying: .external(fillAlphaMode: .premultiplied)) { _ in f }
        device.advance(frames: 3)
        #expect(onThree.all.first?.frame.bgra == [100, 100, 100, 255])     // the key arrived where the fill belongs
        #expect(onFour.all.first?.frame.bgra == [10, 20, 30, 255])
    }

    @Test func droppingEveryNthFrameLeavesGaps() throws {
        let device = SimulatedSDIDevice()
        device.setFaults(SimulatedFaults(dropEveryNthFrame: 3))
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        input.onFrameReceived = { frames.add($0) }
        try input.enable(mode: nil)
        _ = try play(device, connector: 1, frames: 12) { tag($0) }
        device.advance(frames: 10)                                // frames 0...8 reach the cable's end
        #expect(frames.all.map { Int($0.frame.bgra[0]) } == [0, 1, 3, 4, 6, 7])
        let stamps = frames.all.compactMap(\.hardwareTimestamp)
        #expect(stamps[2] - stamps[1] == 2 * mode.frameDurationValue)   // the gap shows in the hardware clock
    }

    @Test func shiftingByOnePixelMovesTheImageRight() throws {
        let device = SimulatedSDIDevice()
        device.setFaults(SimulatedFaults(shiftPixels: 1))
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        input.onFrameReceived = { frames.add($0) }
        try input.enable(mode: nil)
        var bytes = [UInt8](repeating: 0, count: 4 * 2 * 4)
        for p in 0..<8 { bytes[p * 4] = UInt8(p + 1); bytes[p * 4 + 3] = 255 }     // pixel p has blue = p + 1
        let src = SDIFrame(width: 4, height: 2, bgra: bytes)
        _ = try play(device, connector: 1, frames: 4) { _ in src }
        device.advance(frames: 3)
        let got = try #require(frames.all.first).frame
        func blue(_ f: SDIFrame, _ x: Int, _ y: Int) -> UInt8 { f.bgra[(y * f.width + x) * 4] }
        for y in 0..<2 {
            #expect(blue(got, 0, y) == 0)
            for x in 1..<4 { #expect(blue(got, x, y) == blue(src, x - 1, y)) }
        }
    }

    @Test func aWrongModeIsReportedInAutoDetectAndRefusedWhenFixed() throws {
        let device = SimulatedSDIDevice()
        device.setFaults(SimulatedFaults(wrongMode: .hd1080p60))
        device.connect(output: 1, toInput: 3)
        device.connect(output: 2, toInput: 4)
        let auto = try device.openInput(connector: 3)
        try auto.enable(mode: nil)
        let fixed = try device.openInput(connector: 4)
        let fixedFrames = Box<SDICapturedFrame>()
        fixed.onFrameReceived = { fixedFrames.add($0) }
        try fixed.enable(mode: mode)                              // the mode that was really sent
        _ = try play(device, connector: 1, frames: 6, keying: .external(fillAlphaMode: .premultiplied)) { _ in self.tag(1) }
        device.advance(frames: 4)
        #expect(auto.signal == .locked(.hd1080p60))
        #expect(fixed.signal == .noSignal)
        #expect(fixedFrames.all.isEmpty)
    }

    @Test func unpluggingFailsTheInputAndClearsItsSignal() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let failures = Box<SDIError>()
        input.onFailure = { failures.add($0) }
        try input.enable(mode: nil)
        _ = try play(device, connector: 1, frames: 6) { tag($0) }
        device.advance(frames: 3)
        device.simulateUnplug()
        #expect(failures.all == [.deviceDisconnected])
        #expect(input.signal == .noSignal)
        device.simulateReplug()
        #expect(throws: SDIError.portClosed) { try input.enable(mode: nil) }
        _ = try device.openInput(connector: 3)                    // a fresh port works again
    }

    @Test func disablingStopsDelivery() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        let frames = Box<SDICapturedFrame>()
        input.onFrameReceived = { frames.add($0) }
        try input.enable(mode: nil)
        _ = try play(device, connector: 1, frames: 10) { tag($0) }
        device.advance(frames: 3)
        let before = frames.all.count
        input.disable()
        device.advance(frames: 3)
        #expect(frames.all.count == before)
        #expect(input.signal == .noSignal)
    }

    @Test func disconnectingTheCableRemovesTheSignal() throws {
        let device = SimulatedSDIDevice()
        device.connect(output: 1, toInput: 3)
        let input = try device.openInput(connector: 3)
        try input.enable(mode: nil)
        _ = try play(device, connector: 1, frames: 10) { tag($0) }
        device.advance(frames: 3)
        #expect(input.signal == .locked(mode))
        device.disconnect(input: 3)
        device.advance(frames: 2)
        #expect(input.signal == .noSignal)
    }
}
