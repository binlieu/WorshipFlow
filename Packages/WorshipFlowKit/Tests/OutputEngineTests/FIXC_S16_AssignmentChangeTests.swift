// FIX-C / S16 (OUT-002, HW-002): a running output whose planned assignment changes is never stopped silently.
// Fake displays and the simulated card; the card's reported key route is switched between calls to `devicesChanged`.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@MainActor
private final class ChangingCard {
    let device = SimulatedSDIDevice(info: .simulatedDuo2)
    var info = SDIDeviceInfo.simulatedDuo2
    var displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
    var made: [SDIOutput] = []
    var coordinator: OutputCoordinator!

    init(_ profiles: [ScreenProfile]) {
        coordinator = OutputCoordinator(
            profiles: profiles, displays: { [unowned self] in self.displays },
            makeTarget: { profile, destination in FakeTarget(name: profile.name, destination: destination) },
            sdi: SDIEnvironment(
                devices: { [unowned self] in
                    [SDIDeviceHandle(id: "sim", info: self.info, isConnected: { true }, openOutput: { try self.device.openOutput(connector: $0) })]
                },
                makeTarget: { [unowned self] profile, setup in
                    let out = SDIOutput(name: profile.name, port: setup.port, mode: setup.planned.mode, keying: setup.planned.keying,
                                        isSimulated: true, sceneProvider: { lowerThirdScene() })
                    self.made.append(out)
                    return out
                }))
    }
    func settle() { for o in made where o.status == .running { o.waitUntilStarted() } }
}

@MainActor
@Suite(.serialized) struct FIXC_S16_AssignmentChangeTests {
    let program = ScreenProfile(name: "Program", role: .broadcast, destination: sdiDest(1, keying: true))

    /// The card now reports fill and key the other way round. The running output must not just vanish: it is faulted
    /// with a message that says what moved, and it does not resume by itself on connectors the operator did not choose.
    @Test func aChangedKeyRouteFaultsTheRunningOutputWithAReadableReason() throws {
        let card = ChangingCard([program])
        card.coordinator.start(); card.settle()
        #expect(card.coordinator.readouts().first?.state == .running)

        card.info = .simulatedDuo2WithReversedKeyRoute
        card.coordinator.devicesChanged()

        let state = try #require(card.coordinator.readouts().first?.state)
        guard case .faulted(let message) = state else { Issue.record("expected a fault, got \(state)"); return }
        #expect(message.contains("changed while it was running"), "\(message)")
        #expect(message.contains("Restart"), "the message should say what to do: \(message)")
        #expect(message.contains("fill") && message.contains("key"))
        #expect(card.made.first?.status == .stopped(reason: nil))
        #expect(card.coordinator.runningCount == 0)

        // It does not come back by itself on the new layout ...
        card.coordinator.devicesChanged()
        #expect(card.coordinator.runningCount == 0)
        // ... but the operator's restart starts it on the new assignment.
        card.coordinator.restart(program.id); card.settle()
        #expect(card.coordinator.readouts().first?.state == .running)
    }

    @Test func aChangeIsReportedThroughOnChange() {
        let card = ChangingCard([program])
        card.coordinator.start(); card.settle()
        var notified = 0
        card.coordinator.onChange = { notified += 1 }
        card.info = .simulatedDuo2WithReversedKeyRoute
        card.coordinator.devicesChanged()
        #expect(notified >= 1)
    }

    /// Nothing changed: nothing is touched.
    @Test func anUnchangedPlanLeavesTheOutputRunning() {
        let card = ChangingCard([program])
        card.coordinator.start(); card.settle()
        card.coordinator.devicesChanged()
        #expect(card.coordinator.readouts().first?.state == .running)
        #expect(card.made.count == 1)
    }
}
