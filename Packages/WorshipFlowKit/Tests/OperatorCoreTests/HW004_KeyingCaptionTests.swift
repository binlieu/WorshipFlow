// HW-004 / KI-053: the keying caption names the connector that carries the fill and the one that carries the key, from
// the route the device reports. With no reported route it reads as it always did.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct HW004_KeyingCaptionTests {
    private func device(routes: [SDIKeyRouteSummary]) -> SDIDeviceSummary {
        SDIDeviceSummary(id: "d", name: "Card", connectorCount: 4, supportsKeying: true, isSimulated: false, supportedModes: [], keyRoutes: routes)
    }

    @Test func aReversedRouteNamesFillOnTheSecondConnector() {
        let d = device(routes: [SDIKeyRouteSummary(firstConnector: 1, fillConnector: 2, keyConnector: 1)])
        #expect(ScreenEditing.keyingCaption(connector: 1, device: d) == "Uses connectors 1 and 2: fill on 2, key on 1")
    }

    @Test func aConventionalRouteNamesFillOnTheFirst() {
        let d = device(routes: [SDIKeyRouteSummary(firstConnector: 3, fillConnector: 3, keyConnector: 4)])
        #expect(ScreenEditing.keyingCaption(connector: 3, device: d) == "Uses connectors 3 and 4: fill on 3, key on 4")
    }

    @Test func withNoReportedRouteTheCaptionIsTheOldOne() {
        #expect(ScreenEditing.keyingCaption(connector: 1, device: device(routes: [])) == "Uses connectors 1 and 2")
        #expect(ScreenEditing.keyingCaption(connector: 1, device: nil) == "Uses connectors 1 and 2")
        #expect(ScreenEditing.keyingCaption(connector: 1) == "Uses connectors 1 and 2")      // the original function is unchanged
    }

    @Test func aRouteForAnotherPairIsNotUsed() {
        let d = device(routes: [SDIKeyRouteSummary(firstConnector: 3, fillConnector: 4, keyConnector: 3)])
        #expect(ScreenEditing.keyingCaption(connector: 1, device: d) == "Uses connectors 1 and 2")
    }

    @Test func aKeyedDestinationLabelNamesTheRouteWhenKnown() {
        let d = device(routes: [SDIKeyRouteSummary(firstConnector: 1, fillConnector: 2, keyConnector: 1)])
        let label = ScreenEditing.destinationLabel(.sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied), devices: [d]) { _ in "" }
        #expect(label == "Card, connectors 1 and 2 (fill and key: fill on 2, key on 1)")
    }
}
