// SLIDE-003 acceptance tests (PRES-04). Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct ArrangementResolverTests {
    let pid = UUID()
    func fixture() -> (groups: [SlideGroup], slides: [Slide]) {
        let verse = SlideGroup(presentationID: pid, name: "Verse 1", sortOrder: 0)
        let chorus = SlideGroup(presentationID: pid, name: "Chorus", sortOrder: 1)
        let bridge = SlideGroup(presentationID: pid, name: "Bridge", sortOrder: 2)
        func slide(_ text: String, _ order: Int, _ group: SlideGroup?) -> Slide {
            Slide(presentationID: pid, sortOrder: order, content: SlideContent(primary: text), groupID: group?.id)
        }
        let slides = [slide("V1a", 0, verse), slide("V1b", 1, verse), slide("C", 2, chorus), slide("B", 3, bridge), slide("loose", 4, nil)]
        return ([verse, chorus, bridge], slides)
    }
    func texts(_ slides: [Slide]) -> [String] { slides.map(\.content.primary) }

    @Test func noArrangementIsNaturalOrder() {
        let f = fixture()
        #expect(texts(ArrangementResolver.order(slides: f.slides.shuffled(), groups: f.groups, arrangement: nil)) == ["V1a", "V1b", "C", "B", "loose"])
    }

    @Test func arrangementRepeatsAndReordersGroups() {
        let f = fixture()
        let arr = Arrangement(presentationID: pid, name: "Sunday", groupIDs: [f.groups[1].id, f.groups[0].id, f.groups[1].id, f.groups[2].id, f.groups[1].id])
        #expect(texts(ArrangementResolver.order(slides: f.slides, groups: f.groups, arrangement: arr)) == ["C", "V1a", "V1b", "C", "B", "C"])
    }

    /// Slides outside any group are not part of an arrangement.
    @Test func ungroupedSlidesAreLeftOut() {
        let f = fixture()
        let arr = Arrangement(presentationID: pid, name: "Short", groupIDs: [f.groups[0].id])
        #expect(texts(ArrangementResolver.order(slides: f.slides, groups: f.groups, arrangement: arr)) == ["V1a", "V1b"])
    }

    @Test func unknownGroupIDsAreSkipped() {
        let f = fixture()
        let arr = Arrangement(presentationID: pid, name: "Stale", groupIDs: [UUID(), f.groups[1].id])
        #expect(texts(ArrangementResolver.order(slides: f.slides, groups: f.groups, arrangement: arr)) == ["C"])
    }

    @Test func emptyArrangementIsEmpty() {
        let f = fixture()
        let arr = Arrangement(presentationID: pid, name: "Empty", groupIDs: [])
        #expect(ArrangementResolver.order(slides: f.slides, groups: f.groups, arrangement: arr).isEmpty)
    }
}
