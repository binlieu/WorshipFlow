// FIX-B R11: which section orders a re-flow would damage. Pure rules; the library and the model are tested elsewhere.
import Testing
import Foundation
@testable import Domain

@Suite struct ReflowImpactTests {
    let presentation = UUID()

    func group(_ name: String, _ order: Int) -> SlideGroup { SlideGroup(presentationID: presentation, name: name, sortOrder: order) }

    @Test func anOrderThatLosesSomeSectionsListsThemOnce() {
        let verse = group("Verse 1", 0), chorus = group("Chorus", 1), bridge = group("Bridge", 2)
        let order = Arrangement(presentationID: presentation, name: "Long", groupIDs: [verse.id, chorus.id, bridge.id, chorus.id])
        let impact = ReflowImpact.sectionOrderLosses(groups: [verse, chorus, bridge], arrangements: [order],
                                                     newSectionNames: ["Verse 1", "Bridge"], playlistTitlesByArrangement: [:])
        #expect(impact.count == 1)
        #expect(impact[0].arrangementName == "Long")
        #expect(impact[0].lostSections == ["Chorus"])
        #expect(!impact[0].becomesEmpty)
    }

    @Test func anOrderWhoseSectionsAllVanishBecomesEmptyAndNamesItsPlaylistItems() {
        let chorus = group("Chorus", 0), verse = group("Verse 1", 1)
        let order = Arrangement(presentationID: presentation, name: "Chorus only", groupIDs: [chorus.id])
        let impact = ReflowImpact.sectionOrderLosses(groups: [chorus, verse], arrangements: [order],
                                                     newSectionNames: ["Verse 1"], playlistTitlesByArrangement: [order.id: ["Song B", "Song B"]])
        #expect(impact.first?.becomesEmpty == true)
        #expect(impact.first?.lostSections == ["Chorus"])
        #expect(impact.first?.playlistItemTitles == ["Song B", "Song B"])
    }

    @Test func ordersThatKeepEverythingAreNotListed() {
        let verse = group("Verse 1", 0), chorus = group("Chorus", 1)
        let kept = Arrangement(presentationID: presentation, name: "Kept", groupIDs: [verse.id, chorus.id])
        let alreadyEmpty = Arrangement(presentationID: presentation, name: "Blank", groupIDs: [])
        #expect(ReflowImpact.sectionOrderLosses(groups: [verse, chorus], arrangements: [kept, alreadyEmpty],
                                                newSectionNames: ["Verse 1", "Chorus", "Bridge"], playlistTitlesByArrangement: [:]).isEmpty)
    }

    @Test func aSectionThatIsOnlyRenamedCountsAsLost() {
        let chorus = group("Chorus", 0)
        let order = Arrangement(presentationID: presentation, name: "Order", groupIDs: [chorus.id])
        let impact = ReflowImpact.sectionOrderLosses(groups: [chorus], arrangements: [order], newSectionNames: ["Refrain"],
                                                     playlistTitlesByArrangement: [:])
        #expect(impact.first?.lostSections == ["Chorus"] && impact.first?.becomesEmpty == true)
    }
}
