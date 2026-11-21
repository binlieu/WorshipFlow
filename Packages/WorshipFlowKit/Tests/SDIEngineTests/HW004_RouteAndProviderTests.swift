// HW-004: the device reports which connector carries the fill and which the key (KI-053), the planner follows it, the
// simulator can run the other way round, hardware faults are not "disconnected" (KI-056), and providers merge.
import Testing
import Foundation
import SDIEngine

private func id() -> UUID { UUID() }

@Suite struct HW004_ErrorTests {
    @Test func aHardwareFaultCarriesTheCardsOwnWordsAndIsNotADisconnect() {
        let e = SDIError.hardwareFault(detail: "the card refused the mode [hresult 80004005]")
        #expect(e.description.contains("the card refused the mode"))
        #expect(!e.description.lowercased().contains("disconnected"))
        #expect(e != .deviceDisconnected)
        #expect(e == SDIError.hardwareFault(detail: "the card refused the mode [hresult 80004005]"))
    }
}

@Suite struct HW004_PlannerFollowsTheDeviceTests {
    private let reversedPair1 = SDIKeyRoute(firstConnector: 1, fillConnector: 2, keyConnector: 1, source: .simulator)

    @Test func withNoReportedRouteTheFillIsOnTheFirstConnectorAsBefore() {
        let a = id()
        let plan = SDIConnectorPlanner.plan(requests: [SDIOutputRequest(screenID: a, connector: 1, keying: true)], connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.assignments[a] == SDIAssignment(connector: 1, keyConnector: 2))
        #expect(plan.assignments[a]?.fillConnector == 1)
        #expect(plan.role(of: 1) == .fill(a) && plan.role(of: 2) == .key(a))
    }

    @Test func aReversedRoutePutsTheFillOnTheSecondConnector() {
        let a = id()
        let plan = SDIConnectorPlanner.plan(requests: [SDIOutputRequest(screenID: a, connector: 1, keying: true)], connectorCount: 4,
                                            supportsExternalKeying: true, keyRoutes: [reversedPair1])
        let assignment = plan.assignments[a]
        #expect(assignment?.connector == 1)          // the port still opens on the first connector of the pair
        #expect(assignment?.fillConnector == 2)
        #expect(assignment?.keyConnector == 1)
        #expect(plan.role(of: 2) == .fill(a))
        #expect(plan.role(of: 1) == .key(a))
        #expect(plan.connectorsUsed == 2)
    }

    @Test func aRouteForOnePairDoesNotChangeTheOther() {
        let a = id(), b = id()
        let plan = SDIConnectorPlanner.plan(requests: [SDIOutputRequest(screenID: a, connector: 1, keying: true), SDIOutputRequest(screenID: b, connector: 3, keying: true)],
                                            connectorCount: 4, supportsExternalKeying: true, keyRoutes: [reversedPair1])
        #expect(plan.assignments[b] == SDIAssignment(connector: 3, keyConnector: 4))
        #expect(plan.role(of: 3) == .fill(b) && plan.role(of: 4) == .key(b))
    }

    @Test func aReversedRouteStillClaimsBothConnectorsOfThePair() {
        let a = id(), b = id()
        let plan = SDIConnectorPlanner.plan(requests: [SDIOutputRequest(screenID: a, connector: 1, keying: true), SDIOutputRequest(screenID: b, connector: 2)],
                                            connectorCount: 4, supportsExternalKeying: true, keyRoutes: [reversedPair1])
        #expect(plan.faults[b] == .connectorInUse(by: a))
    }

    @Test func aPlainOutputIgnoresRoutes() {
        let a = id()
        let plan = SDIConnectorPlanner.plan(requests: [SDIOutputRequest(screenID: a, connector: 2)], connectorCount: 4, supportsExternalKeying: true, keyRoutes: [reversedPair1])
        #expect(plan.assignments[a] == SDIAssignment(connector: 2, keyConnector: nil))
        #expect(plan.role(of: 2) == .output(a))
    }
}

@Suite struct HW004_SimulatorRouteTests {
    private func frame() -> SDIFrame {
        // Left half opaque orange, right half transparent: fill and key differ clearly.
        var px = [UInt8]()
        for x in 0..<4 { px += x < 2 ? [0, 128, 255, 255] : [0, 0, 0, 0] }
        return SDIFrame(width: 4, height: 1, bgra: px)
    }

    @Test func theDefaultSimulatorReportsFillOnTheFirstConnectorOfEachPair() {
        let info = SDIDeviceInfo.simulatedDuo2
        #expect(info.keyRoute(firstConnector: 1) == SDIKeyRoute(firstConnector: 1, fillConnector: 1, keyConnector: 2, source: .simulator))
        #expect(info.keyRoute(firstConnector: 3) == SDIKeyRoute(firstConnector: 3, fillConnector: 3, keyConnector: 4, source: .simulator))
        #expect(info.keyRoute(firstConnector: 2) == nil)
        #expect(info.connectors.count == 4)
        #expect(info.connectors.allSatisfy { $0.canOutput && $0.canInput })
    }

    @Test func theReversedSimulatorReportsFillOnTheSecondConnector() {
        let info = SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute
        #expect(info.keyRoute(firstConnector: 1)?.fillConnector == 2)
        #expect(info.keyRoute(firstConnector: 1)?.keyConnector == 1)
        #expect(info.keyRoute(firstConnector: 3)?.fillConnector == 4)
        #expect(info.isSimulated && info.supportsExternalKeying)
    }

    @Test func aReversedSimulatorActuallyPutsTheFillOnTheSecondConnector() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2WithReversedKeyRoute)
        let port = try device.openOutput(connector: 1)
        try port.enable(mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied))
        try port.schedule(frame(), atFrame: 0)
        port.startPlayback(atFrame: 0)
        device.advance(frames: 1)
        let split = FillKeySplitter.split(bgra: frame().bgra, fillAlphaMode: .premultiplied)
        #expect(device.lastDisplayed(onConnector: 2)?.bgra == split.fill)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra == split.key)
    }

    @Test func theDefaultSimulatorPutsTheFillOnTheFirstConnector() throws {
        let device = SimulatedSDIDevice()
        let port = try device.openOutput(connector: 1)
        try port.enable(mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied))
        try port.schedule(frame(), atFrame: 0)
        port.startPlayback(atFrame: 0)
        device.advance(frames: 1)
        let split = FillKeySplitter.split(bgra: frame().bgra, fillAlphaMode: .premultiplied)
        #expect(device.lastDisplayed(onConnector: 1)?.bgra == split.fill)
        #expect(device.lastDisplayed(onConnector: 2)?.bgra == split.key)
    }

    @Test func aLoopbackOnAReversedSimulatorSeesTheKeyOnTheFirstCable() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2WithReversedKeyRoute)
        device.connect(output: 1, toInput: 3)
        device.connect(output: 2, toInput: 4)
        let out = try device.openOutput(connector: 1)
        let inFirst = try device.openInput(connector: 3)
        let inSecond = try device.openInput(connector: 4)
        final class Box: @unchecked Sendable { let l = NSLock(); var v: [Int: SDIFrame] = [:]; func set(_ k: Int, _ f: SDIFrame) { l.lock(); v[k] = f; l.unlock() } }
        let box = Box()
        inFirst.onFrameReceived = { box.set(3, $0.frame) }
        inSecond.onFrameReceived = { box.set(4, $0.frame) }
        try inFirst.enable(mode: nil)
        try inSecond.enable(mode: nil)
        try out.enable(mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied))
        for i in 0..<3 { try out.schedule(frame(), atFrame: Int64(i)) }
        out.startPlayback(atFrame: 0)
        device.advance(frames: 3)
        let split = FillKeySplitter.split(bgra: frame().bgra, fillAlphaMode: .premultiplied)
        #expect(box.v[3]?.bgra == split.key)
        #expect(box.v[4]?.bgra == split.fill)
    }
}

@Suite struct HW004_ProviderTests {
    private func collect(_ stream: AsyncStream<SDIDeviceEvent>, count: Int) async -> [SDIDeviceEvent] {
        var out: [SDIDeviceEvent] = []
        for await e in stream { out.append(e); if out.count == count { break } }
        return out
    }

    @Test func theSimulatedProviderListsItsCardAndSaysItIsSimulated() {
        let provider = SimulatedSDIProvider(device: SimulatedSDIDevice(), id: "sim")
        let devices = provider.currentDevices()
        #expect(devices.map(\.id) == ["sim"])
        #expect(devices[0].info.isSimulated)
        let env = provider.environmentStatus()
        #expect(env.state == .simulated && env.deviceCount == 1)
        #expect(env.message.localizedCaseInsensitiveContains("simulated"))
    }

    @Test func unplugAndReplugAreEventsOnTheStream() async {
        let device = SimulatedSDIDevice()
        let provider = SimulatedSDIProvider(device: device, id: "sim")
        let stream = provider.events()
        device.simulateUnplug()
        device.simulateReplug()
        let events = await collect(stream, count: 2)
        #expect(events == [.removed(id: "sim"), .arrived(id: "sim")])
    }

    @Test func aProvidedDeviceOpensPortsLikeTheDevice() throws {
        let provider = SimulatedSDIProvider(device: SimulatedSDIDevice(), id: "sim")
        let d = provider.currentDevices()[0]
        let port = try d.openOutput(2)
        #expect(port.connector == 2)
        #expect(try d.openInput(3).connector == 3)
        #expect(d.isConnected())
    }

    @Test func theCompositeMergesDevicesAndKeepsTheirIDs() {
        let a = SimulatedSDIProvider(device: SimulatedSDIDevice(), id: "a")
        let b = SimulatedSDIProvider(device: SimulatedSDIDevice(), id: "b")
        let composite = CompositeSDIProvider([a, b])
        #expect(composite.currentDevices().map(\.id) == ["a", "b"])
    }

    @Test func theCompositeReportsTheRealProvidersEnvironmentWhateverThereIsBesideIt() {
        let real = FakeProvider(status: SDIEnvironmentStatus(state: .driverNotInstalled, driverInstalled: false, apiVersion: nil, frameworkLoadable: nil,
                                                              deviceCount: 0, message: "Blackmagic Desktop Video is not installed on this Mac."))
        let sim = SimulatedSDIProvider(device: SimulatedSDIDevice(), id: "sim")
        let composite = CompositeSDIProvider([real, sim])
        #expect(composite.environmentStatus().state == .driverNotInstalled)
        #expect(composite.currentDevices().map(\.id) == ["sim"])
        #expect(CompositeSDIProvider([sim]).environmentStatus().state == .simulated)
    }

    @Test func theCompositeMergesEventsFromEveryProvider() async {
        let d1 = SimulatedSDIDevice(), d2 = SimulatedSDIDevice()
        let composite = CompositeSDIProvider([SimulatedSDIProvider(device: d1, id: "one"), SimulatedSDIProvider(device: d2, id: "two")])
        let stream = composite.events()
        d1.simulateUnplug()
        d2.simulateUnplug()
        let events = await collect(stream, count: 2)
        #expect(Set(events) == [.removed(id: "one"), .removed(id: "two")])
    }

    @Test func rescanReachesEveryProvider() {
        let a = FakeProvider(status: .init(state: .noCardFound, driverInstalled: true, apiVersion: "16.0", frameworkLoadable: true, deviceCount: 0, message: "x"))
        let b = FakeProvider(status: .init(state: .noCardFound, driverInstalled: true, apiVersion: "16.0", frameworkLoadable: true, deviceCount: 0, message: "x"))
        CompositeSDIProvider([a, b]).rescan()
        #expect(a.rescans == 1 && b.rescans == 1)
    }
}

final class FakeProvider: SDIDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let status: SDIEnvironmentStatus
    init(status: SDIEnvironmentStatus) { self.status = status }
    var rescans: Int { lock.lock(); defer { lock.unlock() }; return count }
    func currentDevices() -> [SDIProvidedDevice] { [] }
    func rescan() { lock.lock(); count += 1; lock.unlock() }
    func events() -> AsyncStream<SDIDeviceEvent> { AsyncStream { $0.finish() } }
    func environmentStatus() -> SDIEnvironmentStatus { status }
}
