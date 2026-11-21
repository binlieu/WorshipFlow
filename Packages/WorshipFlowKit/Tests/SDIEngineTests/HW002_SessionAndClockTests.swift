// HW-002: the session reports its own stop (so an output can tell the coordinator), and the simulator's real-time clock.
import Testing
import Foundation
@testable import SDIEngine

private final class Stops: @unchecked Sendable {
    private let lock = NSLock(); private var items: [SDIStopReason] = []
    func add(_ r: SDIStopReason) { lock.lock(); items.append(r); lock.unlock() }
    var all: [SDIStopReason] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Suite struct HW002_SessionAndClockTests {
    private func tiny(_ v: UInt8) -> SDIFrame { SDIFrame(width: 2, height: 1, bgra: [v, v, v, 255, v, v, v, 255]) }

    @Test func aDeviceFailureIsReportedOnce() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let stops = Stops()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in self.tiny(1) }
        session.onStop = { stops.add($0) }
        try session.start()
        #expect(stops.all.isEmpty)
        device.simulateUnplug()
        #expect(stops.all == [.failed(.deviceDisconnected)])
        session.stop()
        #expect(stops.all.count == 1)
    }

    @Test func aRequestedStopIsReportedToo() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let stops = Stops()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in self.tiny(1) }
        session.onStop = { stops.add($0) }
        try session.start()
        session.stop(); session.stop()
        #expect(stops.all == [.requested])
    }

    @Test func aStartThatTheDeviceRefusesIsReported() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 2)
        let stops = Stops()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied)) { _ in self.tiny(1) }
        session.onStop = { stops.add($0) }
        #expect(throws: SDIError.self) { try session.start() }
        #expect(stops.all == [.failed(.keyingUnavailable(connector: 2))])
    }

    @Test func theRealTimeClockAdvancesAtTheModesFrameRate() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in self.tiny(1) }
        try session.start()
        let clock = SimulatedClockDriver(device: device, mode: .hd1080p5994)
        clock.start()
        try await Task.sleep(for: .milliseconds(1000))
        clock.stop()
        let played = session.statistics.scheduler.completed
        // 59.94 fps for one second: about 60 frames. Wide tolerance for a loaded machine.
        #expect(played >= 45 && played <= 66, "played \(played) frames in one second")
        let after = session.statistics.scheduler.completed
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.statistics.scheduler.completed == after, "the clock must stop")
        session.stop()
    }

    @Test func theClockIsSharedAndOnlyStopsWhenEveryoneHasReleasedIt() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let ticks = Counter()
        port.onFrameCompleted = { _ in ticks.bump() }
        try port.enable(mode: .hd1080p5994, keying: .none)
        try port.schedule(tiny(1), atFrame: 0)
        for i in 1..<30 { try port.schedule(tiny(1), atFrame: Int64(i)) }
        port.startPlayback(atFrame: 0)
        let clock = SimulatedClockDriver(device: device, mode: .hd1080p5994)
        #expect(!clock.isRunning && clock.mode == .hd1080p5994)
        clock.start(); clock.start()
        #expect(clock.isRunning)
        clock.stop()
        #expect(clock.isRunning)
        try await Task.sleep(for: .milliseconds(150))
        #expect(ticks.value > 0, "one release must not stop a clock that two users started")
        clock.stop()
        #expect(!clock.isRunning)
        try await Task.sleep(for: .milliseconds(50))
        let frozen = ticks.value
        try await Task.sleep(for: .milliseconds(100))
        #expect(ticks.value == frozen)
    }
}
