// HW-004: the output planner and the connector map follow the device-reported key route (KI-053), and a provided
// device becomes a coordinator handle.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct HW004_OutputPlannerRouteTests {
    private func keyed(connector: Int) -> ScreenProfile {
        ScreenProfile(name: "Lower third", role: .broadcast, destination: .sdi(deviceID: "sim", connector: connector, keying: true, fillAlphaMode: .premultiplied))
    }

    private func plan(_ p: [ScreenProfile], info: SDIDeviceInfo) -> OutputPlan {
        OutputPlanner.plan(profiles: p, availableDisplays: [], operatorDisplay: nil, sdiDevices: [SDIDeviceStatus(id: "sim", info: info, isConnected: true)])
    }

    @Test func aReversedRouteShowsInThePlannedOutputAndTheConnectorMap() throws {
        let p = keyed(connector: 1)
        let result = plan([p], info: .simulatedDuo2WithReversedKeyRoute)
        guard case .sdi(let out)? = result.assignments[OutputSlot(screenID: p.id)] else { Issue.record("expected an SDI output"); return }
        #expect(out.connector == 1)             // the port opens on the first connector of the pair
        #expect(out.fillConnector == 2 && out.keyConnector == 1)
        let map = try #require(result.connectorMaps["sim"])
        #expect(map.uses[0] == .key(OutputSlot(screenID: p.id)))
        #expect(map.uses[1] == .fill(OutputSlot(screenID: p.id)))
        let rows = ConnectorMapPresenter.rows(map: map, profiles: [p])
        #expect(rows[0].text == "Connector 1: key for Lower third")
        #expect(rows[1].text == "Connector 2: fill for Lower third")
    }

    @Test func theDefaultSimulatedCardIsPlannedAsBefore() throws {
        let p = keyed(connector: 1)
        let result = plan([p], info: .simulatedDuo2)
        guard case .sdi(let out)? = result.assignments[OutputSlot(screenID: p.id)] else { Issue.record("expected an SDI output"); return }
        #expect(out.connector == 1 && out.keyConnector == 2 && out.fillConnector == 1)
        let map = try #require(result.connectorMaps["sim"])
        #expect(map.uses[0] == .fill(OutputSlot(screenID: p.id)) && map.uses[1] == .key(OutputSlot(screenID: p.id)))
    }

    @Test func aCardThatReportsNoRouteIsPlannedAsBefore() {
        let p = keyed(connector: 3)
        var info = SDIDeviceInfo.simulatedDuo2
        info.keyRoutes = []
        guard case .sdi(let out)? = plan([p], info: info).assignments[OutputSlot(screenID: p.id)] else { Issue.record("expected an SDI output"); return }
        #expect(out.connector == 3 && out.keyConnector == 4 && out.fillConnector == 3)
    }

    @Test func aReversedKeyedPairStillBlocksAScreenOnItsOtherConnector() {
        let a = keyed(connector: 1)
        let b = ScreenProfile(name: "Stage", role: .stage, destination: .sdi(deviceID: "sim", connector: 2, keying: false, fillAlphaMode: .premultiplied))
        let result = plan([a, b], info: .simulatedDuo2WithReversedKeyRoute)
        guard case .sdiConnector(.connectorInUse)? = result.faults[OutputSlot(screenID: b.id)] else {
            Issue.record("expected the second connector to be reported as in use, got \(String(describing: result.faults[OutputSlot(screenID: b.id)]))")
            return
        }
    }
}

@Suite struct HW004_HandleTests {
    @Test func aProvidedDeviceBecomesAHandleThatOpensItsPorts() throws {
        let provider = SimulatedSDIProvider(device: SimulatedSDIDevice(info: .simulatedDuo2WithReversedKeyRoute), id: "sim")
        let handle = SDIDeviceHandle(provider.currentDevices()[0])
        #expect(handle.id == "sim")
        #expect(handle.info.keyRoute(firstConnector: 1)?.fillConnector == 2)
        #expect(handle.isConnected)
        #expect(try handle.openOutput(connector: 1).connector == 1)
        #expect(handle.status.info.isSimulated)
    }
}
