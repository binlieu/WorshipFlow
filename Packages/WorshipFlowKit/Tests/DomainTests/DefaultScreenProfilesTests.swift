// OUT-002: first-run screen profiles.
import Testing
import Foundation
@testable import Domain

@Suite struct DefaultScreenProfilesTests {
    @Test func audienceGoesToTheFirstNonOperatorDisplay() {
        let p = ScreenProfile.defaults(displays: [1, 2, 3], operatorDisplay: 1)
        #expect(p.map(\.name) == ["Audience", "Stage", "Broadcast"])
        #expect(p[0].destination == .display(2) && p[0].isEnabled)
        #expect(p[1].destination == .window && p[1].isEnabled)
        #expect(p[2].destination == .window && p[2].isEnabled == false)
        #expect(p.map(\.role) == [.audience, .stage, .broadcast])
    }

    @Test func operatorMayBeAnyOfTheDisplays() {
        #expect(ScreenProfile.defaults(displays: [1, 2], operatorDisplay: 2)[0].destination == .display(1))
    }

    @Test func singleDisplayFallsBackToAWindow() {
        #expect(ScreenProfile.defaults(displays: [1], operatorDisplay: 1)[0].destination == .window)
        #expect(ScreenProfile.defaults(displays: [], operatorDisplay: nil)[0].destination == .window)
    }

    @Test func profilesHaveDistinctIDs() {
        let p = ScreenProfile.defaults(displays: [1, 2], operatorDisplay: 1)
        #expect(Set(p.map(\.id)).count == 3)
    }
}
