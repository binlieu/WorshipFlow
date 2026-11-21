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

    // KI-060: these used to sleep for real time and expect "about 60 frames in a second", which a loaded machine breaks.
    // Now the clock's time source is injected. The pacing rule is a pure function of time, tested on its own, and the
    // clock thread runs against a time source the test moves by hand and holds at a limit, so every assertion is about
    // a counted number of frames and no test sleeps.

    private func period(_ mode: SDIVideoMode) -> UInt64 { UInt64(Double(mode.frameDurationValue) / Double(mode.timeScale) * 1_000_000_000) }

    @Test func thePacerAdvancesOncePerFramePeriodForEveryMode() {
        for mode in SDIVideoMode.allKnown {
            var pacer = SDIClockPacer(start: 0, period: period(mode))
            var now: UInt64 = 0
            var frames = 0
            let tenSeconds: UInt64 = 10_000_000_000
            while true {
                switch pacer.step(now: now) {
                case .wait(let ns):
                    if now >= tenSeconds { break }          // everything due by the tenth second has fired
                    now = min(now + ns, tenSeconds)
                    continue
                case .advance: frames += 1; continue
                }
                break
            }
            #expect(frames == Int(tenSeconds / period(mode)), "\(mode.name): \(frames) frames in ten seconds")
        }
    }

    @Test func thePacerNeverWaitsLongerThanItsWakeInterval() {
        let pacer = SDIClockPacer(start: 0, period: period(.hd1080p5994))
        var copy = pacer
        guard case .wait(let ns) = copy.step(now: 0) else { Issue.record("a pacer with nothing due must wait"); return }
        #expect(ns > 0 && ns <= SDIClockPacer.wakeInterval, "it wakes often so a stop is prompt")
    }

    @Test func aStalledClockCatchesUpByAtMostAFewFrames() {
        let p = period(.hd1080p5994)
        var pacer = SDIClockPacer(start: 0, period: p)
        // The thread did not run for a hundred frame periods: it must not fire a hundred frames to catch up.
        var frames = 0
        let now = 100 * p
        while case .advance = pacer.step(now: now) { frames += 1; if frames > 1000 { break } }
        #expect(frames >= 1 && frames <= 6, "caught up with \(frames) frames")
    }

    @Test func aSlightlyLateClockCatchesUpExactly() {
        let p = period(.hd1080p5994)
        var pacer = SDIClockPacer(start: 0, period: p)
        var frames = 0
        let now = 3 * p + 1                 // three frames are due
        while case .advance = pacer.step(now: now) { frames += 1; if frames > 1000 { break } }
        #expect(frames == 3)
    }

    @Test func theRealTimeClockAdvancesAtTheModesFrameRate() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in self.tiny(1) }
        try session.start()
        let time = ManualTimeSource()
        let clock = SimulatedClockDriver(device: device, mode: .hd1080p5994, timeSource: time)
        clock.start()
        await time.run(untilNanoseconds: 1_000_000_000)
        // One second of 59.94 fps is 59 whole frame periods, exactly: nothing is estimated and nothing waited for.
        #expect(session.statistics.scheduler.completed == Int(1_000_000_000 / period(.hd1080p5994)))
        clock.stop()
        let after = session.statistics.scheduler.completed
        time.releaseEverything()
        clock.waitForThreadsToExit()
        #expect(session.statistics.scheduler.completed == after, "the clock must stop")
        session.stop()
    }

    @Test func theClockIsSharedAndOnlyStopsWhenEveryoneHasReleasedIt() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        let ticks = Counter()
        port.onFrameCompleted = { _ in ticks.bump() }
        try port.enable(mode: .hd1080p5994, keying: .none)
        for i in 0..<30 { try port.schedule(tiny(1), atFrame: Int64(i)) }
        port.startPlayback(atFrame: 0)
        let time = ManualTimeSource()
        let clock = SimulatedClockDriver(device: device, mode: .hd1080p5994, timeSource: time)
        #expect(!clock.isRunning && clock.mode == .hd1080p5994)
        clock.start(); clock.start()
        #expect(clock.isRunning)
        clock.stop()
        #expect(clock.isRunning)
        await time.run(untilNanoseconds: 150_000_000)
        #expect(ticks.value == Int(150_000_000 / period(.hd1080p5994)), "one release must not stop a clock that two users started")
        clock.stop()
        #expect(!clock.isRunning)
        let frozen = ticks.value
        time.releaseEverything()
        clock.waitForThreadsToExit()
        #expect(ticks.value == frozen, "no frame after the last release")
    }
}

/// A time source the test moves by hand. `pause` moves time forward but never past the limit; at the limit it blocks the
/// clock thread until the limit is raised or everything is released. `run(untilNanoseconds:)` returns once the clock has
/// done everything due by that time, so the test then reads exact counts. `@unchecked Sendable`: state is guarded by `lock`.
private final class ManualTimeSource: SDIClockTimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var now: UInt64 = 0
    private var limit: UInt64 = 0
    private var blocked = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func nowNanoseconds() -> UInt64 { lock.withLock { now } }

    func pause(nanoseconds: UInt64) {
        lock.lock()
        if released { now += nanoseconds; lock.unlock(); return }
        let step = min(nanoseconds, limit - now)
        if step > 0 { now += step; lock.unlock(); return }
        blocked = true
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume()
        gate.wait()
    }

    func run(untilNanoseconds target: UInt64) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            limit = target
            waiter = c
            let wasBlocked = blocked
            blocked = false
            lock.unlock()
            if wasBlocked { gate.signal() }
        }
    }

    func releaseEverything() {
        lock.lock()
        released = true
        let wasBlocked = blocked
        blocked = false
        lock.unlock()
        if wasBlocked { gate.signal() }
    }
}
