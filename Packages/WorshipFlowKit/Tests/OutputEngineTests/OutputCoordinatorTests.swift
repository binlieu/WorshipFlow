// OUT-002: coordinator re-planning with fake outputs (NFR-05, SCRN-04). No windows, no GPU.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@MainActor
final class FakeTarget: OutputTarget {
    let name: String
    let destination: OutputDestination
    var status: OutputStatus = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    var refreshRate = 60.0
    var statistics = FrameStatistics(targetInterval: 1.0 / 60.0)
    var lastRenderError: String?
    var diagnostics = "fake"
    var isOccluded = false
    var onStatusChange: (@MainActor (OutputStatus) -> Void)?
    var startCount = 0
    var stopCount = 0

    init(name: String, destination: OutputDestination) {
        self.name = name
        self.destination = destination
    }

    func start() throws { startCount += 1; status = .running }
    func stop() { stopCount += 1; status = .stopped(reason: nil) }
    /// Simulates the output stopping by itself, as MetalOutput does when its display is unplugged.
    func failByItself(_ reason: String) { status = .stopped(reason: reason) }
}

@MainActor
final class Harness {
    var displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
    var made: [FakeTarget] = []
    var failNextStart = false
    let backend = FakePowerBackend()
    let sleepGuard: SleepGuard
    var coordinator: OutputCoordinator!

    init(_ profiles: [ScreenProfile]) {
        sleepGuard = SleepGuard(backend: backend)
        coordinator = OutputCoordinator(
            profiles: profiles,
            displays: { [unowned self] in self.displays },
            makeTarget: { [unowned self] profile, destination in
                struct Boom: Error {}
                if self.failNextStart { self.failNextStart = false; throw Boom() }
                let t = FakeTarget(name: profile.name, destination: destination)
                self.made.append(t)
                return t
            },
            sleepGuard: sleepGuard)
    }

    func target(_ name: String) -> FakeTarget? { made.last { $0.name == name } }
    func readout(_ id: UUID) -> ScreenReadout? { coordinator.readouts().first { $0.id == id } }
}

@MainActor
@Suite struct OutputCoordinatorTests {
    let audience = ScreenProfile(name: "Audience", role: .audience, destination: .display(2))
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .display(3))
    let broadcast = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)

    @Test func startRunsEveryEnabledScreen() {
        let h = Harness([audience, stage, broadcast])
        h.coordinator.start()
        #expect(h.coordinator.runningCount == 3)
        #expect(h.readout(audience.id)?.state == .running)
        #expect(h.target("Audience")?.destination == .display(2))
        #expect(h.target("Broadcast")?.destination == .window)
    }

    @Test func disabledScreenDoesNotStart() {
        var off = broadcast; off.isEnabled = false
        let h = Harness([audience, off])
        h.coordinator.start()
        #expect(h.coordinator.runningCount == 1)
        #expect(h.readout(off.id)?.state == .stopped)
    }

    @Test func startWithMissingDisplayFaultsOnlyThatScreen() {
        let h = Harness([audience, stage])
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)
        h.coordinator.start()
        #expect(h.readout(stage.id)?.state == .running)
        guard case .faulted(let message)? = h.readout(audience.id)?.state else { Issue.record("expected a fault"); return }
        #expect(message == RoutingFault.displayMissing.operatorMessage)
    }

    @Test func operatorDisplayIsNeverCovered() {
        var onOperator = audience; onOperator.destination = .display(1)
        let h = Harness([onOperator])
        h.coordinator.start()
        #expect(h.coordinator.runningCount == 0)
        #expect(h.readout(onOperator.id)?.state == .faulted(RoutingFault.operatorDisplay.operatorMessage))
    }

    /// Acceptance: a display disappears; that screen stops, the others are not touched.
    @Test func displayDisappearingStopsOnlyThatScreen() throws {
        let h = Harness([audience, stage, broadcast])
        h.coordinator.start()
        let stageTarget = try #require(h.target("Stage"))
        let broadcastTarget = try #require(h.target("Broadcast"))
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.target("Audience")?.stopCount == 1)
        guard case .faulted? = h.readout(audience.id)?.state else { Issue.record("audience should be faulted"); return }
        #expect(stageTarget.stopCount == 0 && stageTarget.startCount == 1 && stageTarget.status == .running)
        #expect(broadcastTarget.stopCount == 0 && broadcastTarget.status == .running)
        #expect(h.made.count == 3)   // nothing was recreated
        #expect(h.coordinator.runningCount == 2)
    }

    /// The screen is never redirected to another display, even when one is free.
    @Test func faultedScreenIsNotRedirected() {
        let h = Harness([audience])
        h.coordinator.start()
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)   // display 3 is free
        h.coordinator.displaysChanged()
        #expect(h.coordinator.runningCount == 0)
        #expect(h.made.count == 1)
        guard case .faulted? = h.readout(audience.id)?.state else { Issue.record("expected a fault"); return }
    }

    /// Auto-resume on the same display is allowed.
    @Test func displayReturningResumesOnTheSameDisplay() {
        let h = Harness([audience, stage])
        h.coordinator.start()
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state != .running)
        h.displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state == .running)
        #expect(h.made.count == 3)
        #expect(h.made.last?.destination == .display(2))
        #expect(h.target("Stage")?.stopCount == 0)
    }

    /// A different display appearing does not pull a faulted screen onto it.
    @Test func otherDisplayAppearingDoesNotResume() {
        let h = Harness([audience])
        h.coordinator.start()
        h.displays = DisplaySnapshot(available: [1], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        h.displays = DisplaySnapshot(available: [1, 5], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.coordinator.runningCount == 0)
    }

    /// The output noticed the unplug first and stopped itself with a reason.
    @Test func outputStoppingByItselfBecomesAFaultAndResumesWhenDisplayReturns() throws {
        let h = Harness([audience])
        h.coordinator.start()
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)
        try #require(h.target("Audience")).failByItself("The display was disconnected.")
        #expect(h.readout(audience.id)?.state == .faulted("The display was disconnected."))
        #expect(h.coordinator.runningCount == 0)
        h.displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state == .running)
    }

    /// A window the operator closed stays closed.
    @Test func closedWindowStaysFaultedUntilRestart() throws {
        let h = Harness([broadcast])
        h.coordinator.start()
        try #require(h.target("Broadcast")).failByItself("Broadcast was closed.")
        h.coordinator.displaysChanged()
        #expect(h.readout(broadcast.id)?.state == .faulted("Broadcast was closed."))
        h.coordinator.restart(broadcast.id)
        #expect(h.readout(broadcast.id)?.state == .running)
    }

    @Test func restartDoesNotRescueAScreenWhoseDisplayIsStillMissing() {
        let h = Harness([audience])
        h.displays = DisplaySnapshot(available: [1], operatorDisplay: 1)
        h.coordinator.start()
        h.coordinator.restart(audience.id)
        guard case .faulted? = h.readout(audience.id)?.state else { Issue.record("expected a fault"); return }
    }

    @Test func operatorStopOfOneScreenIsNotUndoneByADisplayChange() {
        let h = Harness([audience, stage])
        h.coordinator.start()
        h.coordinator.stop(audience.id)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state == .stopped)
        #expect(h.readout(stage.id)?.state == .running)
    }

    /// An operator-stopped screen is neither shown as faulted nor restarted by unplugging and replugging its display.
    @Test func operatorStoppedScreenDoesNotComeBackWhenItsDisplayReturns() {
        let h = Harness([audience, stage])
        h.coordinator.start()
        h.coordinator.stop(audience.id)
        h.displays = DisplaySnapshot(available: [1, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state == .stopped)
        h.displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(audience.id)?.state == .stopped)
        #expect(h.made.count == 2)
        #expect(h.readout(stage.id)?.state == .running)
    }

    @Test func stopStopsEverythingAndReleasesSleep() {
        let h = Harness([audience, stage, broadcast])
        h.coordinator.start()
        #expect(h.sleepGuard.isHolding)
        h.coordinator.stop()
        #expect(h.coordinator.runningCount == 0)
        #expect(h.made.allSatisfy { $0.status == .stopped(reason: nil) })
        #expect(h.coordinator.readouts().allSatisfy { $0.state == .stopped })
        #expect(h.sleepGuard.isHolding == false)
        h.displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()   // inactive: nothing restarts
        #expect(h.coordinator.runningCount == 0)
    }

    @Test func sleepIsHeldWhileAnyOutputRuns() {
        let h = Harness([audience, broadcast])
        h.coordinator.start()
        #expect(h.sleepGuard.isHolding)
        h.coordinator.stop(audience.id)
        #expect(h.sleepGuard.isHolding)
        h.coordinator.stop(broadcast.id)
        #expect(h.sleepGuard.isHolding == false)
    }

    /// KI-008: an occluded output says hidden.
    @Test func occludedOutputIsReportedHidden() throws {
        let h = Harness([broadcast])
        h.coordinator.start()
        try #require(h.target("Broadcast")).isOccluded = true
        #expect(h.readout(broadcast.id)?.state == .hidden)
        try #require(h.target("Broadcast")).isOccluded = false
        #expect(h.readout(broadcast.id)?.state == .running)
    }

    @Test func renameRestartsNothingButDisableAndRetargetDo() throws {
        let h = Harness([audience, stage])
        h.coordinator.start()
        var renamed = audience; renamed.name = "Sanctuary"
        h.coordinator.setProfiles([renamed, stage])
        #expect(h.target("Audience")?.stopCount == 0)
        #expect(h.readout(audience.id)?.name == "Sanctuary")

        var disabled = stage; disabled.isEnabled = false
        h.coordinator.setProfiles([renamed, disabled])
        #expect(h.target("Stage")?.stopCount == 1)
        #expect(h.target("Audience")?.stopCount == 0)
        #expect(h.readout(stage.id)?.state == .stopped)

        var moved = renamed; moved.destination = .window
        h.coordinator.setProfiles([moved, disabled])
        #expect(h.made.filter { $0.name == "Audience" }.count == 1)   // name unchanged in made targets
        #expect(h.made.last?.destination == .window)
        #expect(h.coordinator.runningCount == 1)
    }

    @Test func twoScreensOnOneDisplayFaultTheLaterOne() {
        var second = stage; second.destination = .display(2)
        let h = Harness([audience, second])
        h.coordinator.start()
        #expect(h.readout(audience.id)?.state == .running)
        #expect(h.readout(second.id)?.state == .faulted(RoutingFault.displayInUse(by: audience.id).operatorMessage))
    }

    @Test func factoryFailureFaultsThatScreenOnly() {
        let h = Harness([audience, broadcast])
        h.failNextStart = true
        h.coordinator.start()
        guard case .faulted? = h.readout(audience.id)?.state else { Issue.record("expected a fault"); return }
        #expect(h.readout(broadcast.id)?.state == .running)
    }

    @Test func statisticsAreReported() throws {
        let h = Harness([broadcast])
        h.coordinator.start()
        let t = try #require(h.target("Broadcast"))
        t.statistics.recordPresentation(at: 0)
        t.statistics.recordPresentation(at: 1.0 / 60.0)
        t.refreshRate = 59.94
        let r = try #require(h.readout(broadcast.id))
        #expect(r.presented == 2 && r.refreshRate == 59.94)
    }
}
