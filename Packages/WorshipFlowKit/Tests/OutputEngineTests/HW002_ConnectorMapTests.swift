// HW-002: the connector map the Screens panel shows for each SDI card, as text per connector.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@Suite struct HW002_ConnectorMapTests {
    @Test func eachConnectorSaysWhatItCarriesAndForWhichScreen() {
        let keyed = ScreenProfile(name: "Program", role: .broadcast, destination: .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied))
        let hall = ScreenProfile(name: "Hall", role: .audience, destination: .display(2),
                                 mirrors: [.sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied)])
        let map = SDIConnectorMap(deviceID: "sim", uses: [
            .fill(OutputSlot(screenID: keyed.id)), .key(OutputSlot(screenID: keyed.id)),
            .output(OutputSlot(screenID: hall.id, mirror: 0)), .unused,
        ])
        let rows = ConnectorMapPresenter.rows(map: map, profiles: [keyed, hall])
        #expect(rows.map(\.connector) == [1, 2, 3, 4])
        #expect(rows.map(\.kind) == [.fill, .key, .output, .unused])
        #expect(rows[0].text == "Connector 1: fill for Program")
        #expect(rows[1].text == "Connector 2: key for Program")
        #expect(rows[2].text == "Connector 3: output for Hall (mirror 1)")
        #expect(rows[3].text == "Connector 4: unused")
        #expect(rows[0].screenName == "Program" && rows[3].screenName == nil)
    }

    @Test func aScreenThatNoLongerExistsIsNamedSafely() {
        let map = SDIConnectorMap(deviceID: "sim", uses: [.output(OutputSlot(screenID: UUID()))])
        #expect(ConnectorMapPresenter.rows(map: map, profiles: [])[0].text == "Connector 1: output for a screen that was removed")
    }
}
