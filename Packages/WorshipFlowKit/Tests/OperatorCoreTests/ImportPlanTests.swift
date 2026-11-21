// OUT-004: the import sheet's split and break moves.
import Testing
import Domain
@testable import OperatorCore

@Suite struct ImportPlanTests {
    let first = "Verse 1\nl1\nl2\nl3\nl4\nl5\n\nChorus\nc1\nc2"
    let second = "Câu 1\nm1\nm2\nm3\nm4\nm5\n\nĐiệp khúc\nd1\nd2"

    @Test func withoutMovesItEqualsReflowContents() {
        for lines in 1...5 {
            let plan = ImportPlan(primary: first, secondary: second, maxLines: lines)
            #expect(plan.results == Reflow.contents(primary: first, secondary: second, maxLines: lines))
        }
        let plan = ImportPlan(primary: first, secondary: nil, maxLines: 2)
        #expect(plan.results == Reflow.contents(primary: first, secondary: nil, maxLines: 2))
    }

    @Test func movingABreakMovesTheSecondLanguageWithIt() {
        var plan = ImportPlan(primary: first, secondary: second, maxLines: 2)
        #expect(plan.slides.map(\.lines.count) == [2, 2, 1, 2])
        plan.moveBreak(after: 0, by: 1)                      // pull one line up into the first slide
        #expect(plan.slides.map(\.lines.count) == [3, 1, 1, 2])
        let r = plan.results
        #expect(r[0].content.primary == "l1\nl2\nl3")
        #expect(r[0].content.secondary == "m1\nm2\nm3")
        #expect(r[1].content.secondary == "m4")
        #expect(r[2].content.secondary == "m5")
        #expect(r.map(\.sectionName) == ["Verse 1", "Verse 1", "Verse 1", "Chorus"])
    }

    @Test func breaksDoNotCrossSections() {
        var plan = ImportPlan(primary: first, secondary: nil, maxLines: 2)      // slides: [l1 l2] [l3 l4] [l5] | [c1 c2]
        #expect(plan.canMoveBreak(after: 1))
        #expect(plan.canMoveBreak(after: 2) == false)        // the verse ends here and the chorus begins
        let before = plan.slides
        plan.moveBreak(after: 2, by: 1)
        #expect(plan.slides == before)
    }

    @Test func sectionNamesAndSurplusSecondary() {
        let plan = ImportPlan(primary: "Verse 1\na\nb", secondary: "x\ny\nz", maxLines: 1)
        #expect(plan.sectionName(ofSlide: 0) == "Verse 1")
        #expect(plan.results.last?.content.secondary == "y\nz")     // surplus joins the last slide of its section
    }

    @Test func emptyTextGivesNoSlides() {
        #expect(ImportPlan(primary: "  \n", secondary: nil, maxLines: 2).results.isEmpty)
    }
}
