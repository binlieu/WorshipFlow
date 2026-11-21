// OUT-002 acceptance tests: screen routing and failover (SCRN-01, SCRN-04, NFR-05; CLAUDE.md hardware rules).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct OutputRouterTests {
    func profile(_ name: String, _ role: ScreenRole, _ dest: OutputDestination, enabled: Bool = true) -> ScreenProfile {
        ScreenProfile(id: UUID(), name: name, role: role, destination: dest, isEnabled: enabled)
    }

    @Test func assignsEachEnabledScreen() {
        let audience = profile("Sanctuary", .audience, .display(2))
        let stage = profile("Stage", .stage, .window)
        let off = profile("Lobby", .audience, .display(3), enabled: false)
        let plan = OutputRouter.plan(profiles: [audience, stage, off], availableDisplays: [1, 2, 3], operatorDisplay: 1)
        #expect(plan.assignments == [audience.id: .display(2), stage.id: .window])
        #expect(plan.faults.isEmpty)
    }

    /// NFR-05: a missing display faults that screen only.
    @Test func missingDisplayFaultsOnlyThatScreen() {
        let audience = profile("Sanctuary", .audience, .display(2))
        let stage = profile("Stage", .stage, .display(3))
        let plan = OutputRouter.plan(profiles: [audience, stage], availableDisplays: [1, 3], operatorDisplay: 1)
        #expect(plan.assignments == [stage.id: .display(3)])
        #expect(plan.faults == [audience.id: .displayMissing])
    }

    /// Two screens may not silently share a display. The first in order keeps it.
    @Test func duplicateDisplayFaultsTheLaterScreen() {
        let a = profile("Sanctuary", .audience, .display(2))
        let b = profile("Stage", .stage, .display(2))
        let plan = OutputRouter.plan(profiles: [a, b], availableDisplays: [1, 2], operatorDisplay: 1)
        #expect(plan.assignments == [a.id: .display(2)])
        #expect(plan.faults == [b.id: .displayInUse(by: a.id)])
    }

    /// A full-screen output never covers the operator's own display.
    @Test func operatorDisplayIsProtected() {
        let a = profile("Sanctuary", .audience, .display(1))
        let plan = OutputRouter.plan(profiles: [a], availableDisplays: [1, 2], operatorDisplay: 1)
        #expect(plan.assignments.isEmpty)
        #expect(plan.faults == [a.id: .operatorDisplay])
    }

    @Test func anyNumberOfWindowsIsFine() {
        let a = profile("One", .audience, .window), b = profile("Two", .stage, .window)
        let plan = OutputRouter.plan(profiles: [a, b], availableDisplays: [], operatorDisplay: nil)
        #expect(plan.assignments.count == 2 && plan.faults.isEmpty)
    }

    /// Never redirect a screen to a different display on its own.
    @Test func faultedScreenIsNeverReassigned() {
        let a = profile("Sanctuary", .audience, .display(9))
        let plan = OutputRouter.plan(profiles: [a], availableDisplays: [1, 2, 3], operatorDisplay: 1)
        #expect(plan.assignments[a.id] == nil)
    }

    @Test func faultsHaveOperatorMessages() {
        for fault in [RoutingFault.displayMissing, .displayInUse(by: UUID()), .operatorDisplay] {
            #expect(fault.operatorMessage.count > 10)
        }
    }

    @Test func profilesRoundTripThroughCodable() throws {
        let p = profile("Sanctuary", .audience, .display(2))
        let data = try JSONEncoder().encode([p, profile("Stage", .stage, .window)])
        #expect(try JSONDecoder().decode([ScreenProfile].self, from: data).first == p)
    }
}
