// FIX-C / S11 (HW-003): the scheduler preroll is max(3, the device's own minimum), passed through from the bridge.
import Testing
import Foundation
import SDIEngine
@testable import DeckLinkSDI

@Suite struct FIXC_PrerollTests {
    @Test func prerollIsAtLeastThreeAndAtLeastTheDevicesMinimum() {
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: -1) == 3)     // the device did not say
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: 0) == 3)
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: 2) == 3)
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: 3) == 3)
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: 5) == 5)
    }

    @Test func anAbsurdMinimumIsCappedSoTheBufferStaysBounded() {
        #expect(DeckLinkMapping.prerollFrames(deviceMinimum: 1_000_000) == DeckLinkMapping.maxPrerollFrames)
        #expect(DeckLinkMapping.maxPrerollFrames < 16)                      // the bridge's frame pool holds 16
    }

    @Test func anUnopenedOrSimulatedPortReportsNoMinimum() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = try device.openOutput(connector: 1)
        #expect(port.minimumPrerollFrames == 0)
    }
}
