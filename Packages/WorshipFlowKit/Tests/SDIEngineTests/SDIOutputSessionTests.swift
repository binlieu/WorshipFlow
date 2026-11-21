// HW-001: the output session against the simulated card. Verification level: Simulated.
import Testing
import Foundation
@testable import SDIEngine

private final class Requested: @unchecked Sendable {
    private let lock = NSLock(); private var items: [Int64] = []
    func add(_ i: Int64) { lock.lock(); items.append(i); lock.unlock() }
    var all: [Int64] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct SDIOutputSessionTests {
    private func tiny(_ v: UInt8) -> SDIFrame { SDIFrame(width: 2, height: 1, bgra: [v, v, v, 255, v, v, v, 255]) }

    @Test func steadyClockRunHasNoLateOrDroppedFrames() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let asked = Requested()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { i in asked.add(i); return SDIFrame(width: 2, height: 1, bgra: Array(repeating: UInt8(i % 200), count: 8)) }
        try session.start()
        #expect(session.state == .running)
        device.advance(frames: 600)
        let stats = session.statistics
        #expect(stats.scheduler.completed == 600)
        #expect(stats.scheduler.late == 0 && stats.scheduler.dropped == 0)
        #expect(stats.repeatedFrames == 0)
        #expect(session.health == .ok)
        #expect(asked.all == Array(0..<Int64(asked.all.count)))                 // each index asked once, in order
        #expect(device.lastDisplayed(onConnector: 1)?.bgra.first == UInt8(599 % 200))
        session.stop()
        #expect(session.state == .stopped(.requested))
    }

    @Test func providerStallRepeatsFramesAndRecovers() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { [self] i in
            (100..<110).contains(i) ? nil : tiny(UInt8(i % 200))
        }
        try session.start()
        device.advance(frames: 106)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra.first == 99)        // frames 100... repeat frame 99
        device.advance(frames: 200)
        let stats = session.statistics
        #expect(stats.repeatedFrames == 10)
        #expect(stats.scheduler.late == 0 && stats.scheduler.dropped == 0)
        #expect(session.health == .ok)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra.first == UInt8(305 % 200))   // fresh frames are back
    }

    @Test func firstFrameStallShowsBlackOfTheModeSize() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let session = SDIOutputSession(port: port, mode: .hd720p60) { _ in nil }
        try session.start()
        device.advance(frames: 1)
        let shown = device.lastDisplayed(onConnector: 1)
        #expect(shown?.width == 1280 && shown?.height == 720)
        #expect(shown?.bgra.allSatisfy { $0 == 0 } == true)
        #expect(session.statistics.repeatedFrames > 0)
    }

    @Test func unplugMidRunStopsWithTheReason() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { [self] i in tiny(UInt8(i % 200)) }
        try session.start()
        device.advance(frames: 50)
        let before = session.statistics
        device.simulateUnplug()
        #expect(session.state == .stopped(.failed(.deviceDisconnected)))
        device.advance(frames: 10)                                              // no crash, nothing changes
        #expect(session.statistics == before)
        session.stop()                                                          // idempotent
        #expect(session.stopReason == .failed(.deviceDisconnected))
    }

    @Test func startFailureIsReportedAndStopsTheSession() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 2)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied)) { _ in nil }
        #expect(throws: SDIError.self) { try session.start() }
        #expect(session.state == .stopped(.failed(.keyingUnavailable(connector: 2))))
    }

    @Test func keyedSessionDrivesBothConnectors() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 3)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied)) { _ in
            SDIFrame(width: 1, height: 1, bgra: [10, 20, 30, 40])
        }
        try session.start()
        device.advance(frames: 5)
        #expect(device.lastDisplayed(onConnector: 3)?.bgra == [10, 20, 30, 255])
        #expect(device.lastDisplayed(onConnector: 4)?.bgra == [40, 40, 40, 255])
    }
}
