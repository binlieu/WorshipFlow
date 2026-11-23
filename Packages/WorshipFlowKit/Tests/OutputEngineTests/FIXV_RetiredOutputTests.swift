// FIX-V item 4 (REVIEW-4 M2): a stopped output was kept in the coordinator's `retiring` list until an SDI output started or a waiting stop was
// asked, so display-only setups kept every closed screen (window, Metal layer, textures) alive for the life of the app. Written before the fix.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@MainActor
@Suite struct FIXV_RetiredOutputTests {
    final class WeakTarget { weak var target: AnyObject?; init(_ t: AnyObject) { target = t } }

    @Test func afterManyOpenAndCloseCyclesWithDisplayOutputsNothingIsRetained() {
        let audience = ScreenProfile(name: "Audience", role: .audience, destination: .display(2))
        let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
        let h = Harness([audience, stage])
        var weak: [WeakTarget] = []
        for cycle in 0..<12 {
            h.coordinator.start()
            #expect(h.coordinator.runningCount == 2)
            weak += h.made.map { WeakTarget($0) }
            h.made.removeAll()
            if cycle % 3 == 0 { h.coordinator.stop(waitForPorts: false) }
            else if cycle % 3 == 1 { h.coordinator.stop(audience.id, waitForPorts: false); h.coordinator.stop(stage.id, waitForPorts: false) }
            else {
                var changed = audience; changed.destination = .window       // a profile change restarts the output
                h.coordinator.setProfiles([changed, stage])
                h.coordinator.stop(waitForPorts: false)
                h.coordinator.setProfiles([audience, stage])
            }
        }
        weak += h.made.map { WeakTarget($0) }
        h.made.removeAll()
        #expect(h.coordinator.retiredCount == 0)
        #expect(weak.count >= 24)
        #expect(weak.allSatisfy { $0.target == nil }, "every stopped output was deallocated")
    }

    /// An output whose teardown takes time, like an SDI port closing on its own queue: it says it is tearing down until `finishTeardown()`.
    @MainActor
    final class SlowTarget: OutputTarget {
        let name = "SDI"
        var status: OutputStatus = .idle
        var refreshRate = 60.0
        var statistics = FrameStatistics(targetInterval: 1.0 / 60.0)
        var lastRenderError: String?
        var diagnostics = "slow"
        var onStatusChange: (@MainActor (OutputStatus) -> Void)?
        var onTeardownFinished: (@MainActor () -> Void)?
        private(set) var isTearingDown = false
        private(set) var waits = 0
        func start() throws { status = .running }
        func stop() { stopWithoutWaiting(); waitUntilStopped() }
        func stopWithoutWaiting() { isTearingDown = true; status = .stopped(reason: nil) }
        /// A wait returns when the teardown is done (here: it ends the teardown, as the queue would).
        func waitUntilStopped() { if isTearingDown { waits += 1; isTearingDown = false } }
        /// The teardown ends by itself, as it does on the output's queue, and the output says so on the main actor.
        func finishTeardown() { isTearingDown = false; Task { @MainActor in self.onTeardownFinished?() } }
    }

    @Test func anOutputThatIsStillClosingStaysUntilItsOwnTeardownEndsAndIsThenReleased() async {
        let profile = ScreenProfile(name: "Card", role: .broadcast, destination: .window)
        var made: [SlowTarget] = []
        let coordinator = OutputCoordinator(profiles: [profile], displays: { DisplaySnapshot(available: [1], operatorDisplay: 1) },
                                            makeTarget: { _, _ in let t = SlowTarget(); made.append(t); return t })
        coordinator.start()
        var slow: SlowTarget? = made[0]
        let weakSlow = WeakTarget(made[0])
        coordinator.stop(waitForPorts: false)
        #expect(coordinator.retiredCount == 1, "still closing: held, so a start on the same connector can wait for it")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            coordinator.onRetiredReleased = { done.resume() }
            slow?.finishTeardown()
        }
        #expect(coordinator.retiredCount == 0)
        made.removeAll()
        slow = nil
        #expect(weakSlow.target == nil, "released when its own teardown completed")
    }

    @Test func aWaitingStopStillWaitsForAnOutputThatIsClosing() {
        let profile = ScreenProfile(name: "Card", role: .broadcast, destination: .window)
        var made: [SlowTarget] = []
        let coordinator = OutputCoordinator(profiles: [profile], displays: { DisplaySnapshot(available: [1], operatorDisplay: 1) },
                                            makeTarget: { _, _ in let t = SlowTarget(); made.append(t); return t })
        coordinator.start()
        coordinator.stop(waitForPorts: false)
        #expect(coordinator.retiredCount == 1)
        coordinator.stop(waitForPorts: true)
        #expect(made[0].waits == 1, "the waiting stop waited for the teardown")
        #expect(coordinator.retiredCount == 0)
    }
}
