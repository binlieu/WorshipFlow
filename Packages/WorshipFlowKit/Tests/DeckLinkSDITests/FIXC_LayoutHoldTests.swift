// FIX-C / S16 (HW-003): the card's model and layout are held across a profile change that leaves it with no (or fewer)
// sub-devices, so the fill and key route does not flip to the "unknown model" assumptions meanwhile. Built on the
// bridge's stand-ins (a sub-device with attributes), no card involved.
import Testing
import Foundation
import DeckLinkC
import SDIEngine
@testable import DeckLinkSDI

private func subDevice(_ index: Int64, profile: UInt32) -> DLBDevice {
    DLBTesting.device(withFake: DLBFakeDevice(modelName: "DeckLink Duo 2", subDeviceIndex: index, activeProfile: profile))
}

private let fullDuplex = DeckLinkProfile.oneSubDeviceFullDuplex
private let halfDuplex = DeckLinkProfile.twoSubDevicesHalfDuplex

@Suite(.serialized) struct FIXC_LayoutHoldTests {
    private func card() -> DeckLinkDevice {
        DeckLinkDevice(identifier: .named("Duo2"), members: [subDevice(0, profile: fullDuplex), subDevice(1, profile: fullDuplex)])
    }

    @Test func theLayoutAndKeyRouteAreHeldWhenTheCardHasNoMembersForAMoment() {
        let card = card()
        let before = card.layout
        let infoBefore = card.info
        #expect(before.connectorCount == 4 && before.keyRoute(firstConnector: 1)?.fillConnector == 2)
        #expect(infoBefore.keyRoutes.count == 2)

        _ = card.removeMembers { _ in true }                          // a profile change takes every sub-device away
        #expect(card.currentMembers().isEmpty && !card.isConnected)
        #expect(card.layout == before, "the layout changed while the card was between profiles")
        #expect(card.layout.keyRoute(firstConnector: 1)?.fillConnector == 2)
        let held = card.info
        #expect(held.connectorCount == 4 && held.displayName == "DeckLink Duo 2")
        #expect(held.keyRoutes == infoBefore.keyRoutes, "the key route flipped while the card was between profiles")
    }

    @Test func aPairWithNoMemberKeepsItsLastKnownProfileWhileTheOtherReturns() {
        let card = card()
        let before = card.layout
        _ = card.removeMembers { _ in true }
        card.addMember(subDevice(0, profile: fullDuplex))               // only the first sub-device is back so far
        #expect(card.layout == before)
        #expect(card.info.keyRoutes.count == 2)
    }

    @Test func aRealChangeOfProfileStillShowsOnceTheMembersReportIt() {
        let card = card()
        _ = card.removeMembers { _ in true }
        card.addMember(subDevice(0, profile: halfDuplex))
        card.addMember(subDevice(1, profile: halfDuplex))
        #expect(card.layout.keyRoute(firstConnector: 1) == nil && card.layout.keyRoute(firstConnector: 3) == nil)
        #expect(card.info.connectors.allSatisfy { $0.keyRole == nil }, "the new profile's roles should show")
    }

    @Test func aCardThatLeavesAndReturnsIsTheSameObjectWithItsLayout() {
        let provider = DeckLinkDeviceProvider()
        let a = subDevice(0, profile: fullDuplex), b = subDevice(1, profile: fullDuplex)
        provider.reconcile(found: [a, b])
        let first = provider.currentDevices()
        #expect(first.count == 1)
        guard let before = provider.devicesForTesting().first else { Issue.record("no card"); return }
        let layout = before.layout

        provider.reconcile(found: [])                                     // every sub-device gone for a moment
        #expect(provider.devicesForTesting().isEmpty)
        provider.reconcile(found: [subDevice(0, profile: fullDuplex)])    // one comes back first
        guard let after = provider.devicesForTesting().first else { Issue.record("no card after return"); return }
        #expect(after === before, "a returning card should keep its identity")
        #expect(after.layout == layout, "the layout flipped while the card was coming back")
    }
}
