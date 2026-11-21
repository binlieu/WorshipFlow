// HW-003: the connector layout, built from the SDK manual's Duo 2 table (section 2.4.11). These tests check that the
// table is encoded as written; they cannot say the table matches the hardware. Verification level: Unit Tested.
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

@Suite struct HW003_ConnectorLayoutTests {
    private let full = DeckLinkProfile.oneSubDeviceFullDuplex
    private let half = DeckLinkProfile.twoSubDevicesHalfDuplex

    private func map(_ layout: DeckLinkConnectorLayout) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: layout.entries.map { ($0.connector, $0.subDeviceIndex) })
    }

    @Test func theProfileCodesAreTheSDKsFourCharacterCodes() {
        #expect(DeckLinkProfile.oneSubDeviceFullDuplex == 0x31646664)    // '1dfd'
        #expect(DeckLinkProfile.oneSubDeviceHalfDuplex == 0x31646864)    // '1dhd'
        #expect(DeckLinkProfile.twoSubDevicesFullDuplex == 0x32646664)   // '2dfd'
        #expect(DeckLinkProfile.twoSubDevicesHalfDuplex == 0x32646864)   // '2dhd'
        #expect(DeckLinkProfile.fourSubDevicesHalfDuplex == 0x34646864)  // '4dhd'
        #expect(DeckLinkProfile.name(DeckLinkProfile.oneSubDeviceFullDuplex).contains("full duplex"))
    }

    @Test func duo2HalfDuplexFollowsTheManualTable() {
        // Manual: sub-device 0 = SDI 1, 1 = SDI 3, 2 = SDI 2, 3 = SDI 4.
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [half, half], subDeviceCount: 4)
        #expect(layout.source == .manualTableDuo2)
        #expect(layout.connectorCount == 4)
        #expect(map(layout) == [1: 0, 2: 2, 3: 1, 4: 3])
        #expect(layout.entries.allSatisfy { $0.role == .inputOrOutput })
    }

    @Test func duo2FullDuplexPairsFollowTheManualTable() {
        // Manual: sub-device 0 = SDI 1 (in/key) and SDI 2 (out/fill); sub-device 1 = SDI 3 (in/key) and SDI 4 (out/fill).
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [full, full], subDeviceCount: 2)
        #expect(map(layout) == [1: 0, 2: 0, 3: 1, 4: 1])
        #expect(layout.entry(connector: 1)?.role == .inputOrKey)
        #expect(layout.entry(connector: 2)?.role == .outputOrFill)
        #expect(layout.entry(connector: 3)?.role == .inputOrKey)
        #expect(layout.entry(connector: 4)?.role == .outputOrFill)
    }

    @Test func eachPairFollowsItsOwnProfile() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [full, half], subDeviceCount: 3)
        #expect(map(layout) == [1: 0, 2: 0, 3: 1, 4: 3])
    }

    @Test func anUnknownProfileAssumesHalfDuplex() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [nil, nil], subDeviceCount: 4)
        #expect(map(layout) == [1: 0, 2: 2, 3: 1, 4: 3])
    }

    @Test func theManualPutsFillOnTheHigherConnectorOfTheFullDuplexPair() throws {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [full, full], subDeviceCount: 2)
        let first = try #require(layout.keyRoute(firstConnector: 1))
        #expect(first == DeckLinkKeyRoute(subDeviceIndex: 0, fillConnector: 2, keyConnector: 1, fromDocumentation: true))
        let second = try #require(layout.keyRoute(firstConnector: 3))
        #expect(second == DeckLinkKeyRoute(subDeviceIndex: 1, fillConnector: 4, keyConnector: 3, fromDocumentation: true))
    }

    @Test func halfDuplexHasNoSingleSubDeviceForFillAndKey() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [half, half], subDeviceCount: 4)
        #expect(layout.keyRoute(firstConnector: 1) == nil)
        #expect(layout.keyRoute(firstConnector: 3) == nil)
    }

    @Test func aKeyRouteNeedsBothConnectorsToExist() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [full, full], subDeviceCount: 2)
        #expect(layout.keyRoute(firstConnector: 4) == nil)
        #expect(layout.keyRoute(firstConnector: 9) == nil)
        #expect(layout.entry(connector: 5) == nil)
    }

    @Test func otherModelsFallBackToSubDeviceOrderAndSayItIsAnAssumption() throws {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Quad 2", pairProfiles: [nil, nil], subDeviceCount: 4)
        #expect(layout.source == .subDeviceOrder)
        #expect(map(layout) == [1: 0, 2: 1, 3: 2, 4: 3])
        let route = try #require(layout.keyRoute(firstConnector: 1))
        #expect(!route.fromDocumentation)
        #expect(route.fillConnector == 1 && route.keyConnector == 2, "the planner's convention, assumed")
    }

    @Test func aSingleConnectorCardHasOneConnector() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Mini Monitor", pairProfiles: [nil, nil], subDeviceCount: 1)
        #expect(layout.connectorCount == 1)
        #expect(layout.keyRoute(firstConnector: 1) == nil)
        let none = DeckLinkConnectorLayout.make(modelName: "", pairProfiles: [], subDeviceCount: 0)
        #expect(none.connectorCount == 1, "never zero connectors, so the planner always has something to range-check")
    }

    @Test func roleCapabilities() {
        #expect(DeckLinkConnectorLayout.Role.inputOrOutput.canInput && DeckLinkConnectorLayout.Role.inputOrOutput.canOutput)
        #expect(DeckLinkConnectorLayout.Role.inputOrKey.canInput && !DeckLinkConnectorLayout.Role.inputOrKey.canOutput)
        #expect(!DeckLinkConnectorLayout.Role.outputOrFill.canInput && DeckLinkConnectorLayout.Role.outputOrFill.canOutput)
    }

    @Test func duo2IsRecognisedByModelName() {
        #expect(DeckLinkConnectorLayout.isDuo2(modelName: "DeckLink Duo 2"))
        #expect(DeckLinkConnectorLayout.isDuo2(modelName: "decklink duo 2"))
        #expect(!DeckLinkConnectorLayout.isDuo2(modelName: "DeckLink Duo"))
        #expect(!DeckLinkConnectorLayout.isDuo2(modelName: "DeckLink Quad 2"))
    }

    @Test func theSnapshotListsEveryConnector() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [full, full], subDeviceCount: 2)
        #expect(layout.snapshot["entries"]?.arrayValue?.count == 4)
        #expect(layout.snapshot["source"]?.stringValue == "manualTableDuo2")
    }
}
