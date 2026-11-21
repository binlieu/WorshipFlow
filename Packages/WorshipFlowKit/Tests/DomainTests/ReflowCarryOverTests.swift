// SLIDE-001b: KI-019 (what a re-flow keeps) and KI-020 (repeated section names), written by the implementer.
import Testing
import Foundation
@testable import Domain

@Suite struct ReflowCarryOverTests {
    func object() -> SlideObject {
        SlideObject(frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
    }
    func old(_ section: String?, _ words: String, notes: String = "", objects: [SlideObject] = []) -> ExistingSlide {
        ExistingSlide(sectionName: section, content: SlideContent(primary: words, objects: objects), notes: notes)
    }
    func new(_ section: String?, _ words: String) -> ReflowResult {
        ReflowResult(sectionName: section, content: SlideContent(primary: words))
    }

    // MARK: Carry over (KI-019)

    @Test func unchangedWordsKeepTheirNotesAndObjects() {
        let o = object()
        let carry = Reflow.carryOver(from: [old("Verse 1", "a\nb", notes: "slow", objects: [o]), old("Chorus", "c", notes: "loud")],
                                     to: [new("Verse 1", "a\nb"), new("Chorus", "c")])
        #expect(carry.notes == ["slow", "loud"] && carry.objects == [[o], []] && carry.losses.isEmpty)
    }

    @Test func matchingIgnoresCapitalsAccentsAndPunctuation() {
        let carry = Reflow.carryOver(from: [old(nil, "Ân điển, lạ lùng!", notes: "n")], to: [new(nil, "an dien la lung")])
        #expect(carry.notes == ["n"] && carry.losses.isEmpty)
    }

    @Test func aSlideMovedToAnotherSectionDoesNotMatch() {
        let carry = Reflow.carryOver(from: [old("Verse 1", "a", notes: "n")], to: [new("Chorus", "a")])
        #expect(carry.notes == [""] && carry.losses == [ReflowLoss(sectionName: "Verse 1", primary: "a", notes: "n", objectCount: 0)])
    }

    @Test func changedWordsLoseTheirNotesAndAreListed() {
        let o = object()
        let carry = Reflow.carryOver(from: [old("Verse 1", "a", notes: "keep me"), old("Verse 1", "b", objects: [o]), old("Verse 1", "c")],
                                     to: [new("Verse 1", "a changed"), new("Verse 1", "b changed"), new("Verse 1", "c")])
        #expect(carry.notes == ["", "", ""] && carry.objects == [[], [], []])
        #expect(carry.losses.map(\.primary) == ["a", "b"])                   // "c" had nothing to lose
        #expect(carry.losses.map(\.notes) == ["keep me", ""] && carry.losses.map(\.objectCount) == [0, 1])
    }

    @Test func blankNotesAreNotAskedAbout() {
        #expect(Reflow.carryOver(from: [old(nil, "a", notes: "  \n ")], to: []).losses.isEmpty)
    }

    @Test func repeatedWordsInOneSectionAreTakenInOrderAndOnlyOnce() {
        let carry = Reflow.carryOver(from: [old("Chorus", "la", notes: "first"), old("Chorus", "la", notes: "second")],
                                     to: [new("Chorus", "la"), new("Chorus", "la"), new("Chorus", "la")])
        #expect(carry.notes == ["first", "second", ""])
        #expect(carry.losses.isEmpty)
    }

    @Test func nothingToKeepGivesEmptyAnswersForEverySlide() {
        let carry = Reflow.carryOver(from: [], to: [new(nil, "a"), new(nil, "b")])
        #expect(carry.notes == ["", ""] && carry.objects == [[], []] && carry.losses.isEmpty)
        #expect(Reflow.carryOver(from: [], to: []) == ReflowCarry(notes: [], objects: [], losses: []))
    }

    // MARK: Repeated section names (KI-020)

    @Test func twoChorusesWithDifferentWordsBecomeTwoSections() {
        let sections = Reflow.sections(from: "Chorus\nfirst words\n\nVerse 1\nv\n\nChorus\nother words")
        #expect(sections.map(\.name) == ["Chorus", "Verse 1", "Chorus 2"])
        #expect(sections.map(\.lines) == [["first words"], ["v"], ["other words"]])
    }

    @Test func identicalRepeatedBlocksShareOneSection() {
        let sections = Reflow.sections(from: "Chorus\nsame\n\nVerse 1\nv\n\nChorus\nsame")
        #expect(sections.map(\.name) == ["Chorus", "Verse 1", "Chorus"])
        let results = Reflow.contents(primary: "Chorus\nsame\n\nVerse 1\nv\n\nChorus\nSAME!", secondary: nil, maxLines: 2)
        #expect(results.map(\.sectionName) == ["Chorus", "Verse 1", "Chorus"])      // capitals and punctuation do not matter
    }

    @Test func aThirdDifferentBlockIsNumberedThreeAndARepeatOfTheSecondSharesIt() {
        let names = Reflow.sections(from: "Chorus\na\n\nChorus\nb\n\nChorus\nc\n\nChorus\nb\n\nChorus\na").map(\.name)
        #expect(names == ["Chorus", "Chorus 2", "Chorus 3", "Chorus 2", "Chorus"])
    }

    @Test func anExplicitNumberThatIsAlreadyTakenMovesOn() {
        // The second "Chorus" would be "Chorus 2", but the author used that name for other words later on.
        let names = Reflow.sections(from: "Chorus\na\n\nChorus\nb\n\nChorus 2\nc").map(\.name)
        #expect(names == ["Chorus", "Chorus 2", "Chorus 3"])
    }

    @Test func differentNamesAreNeverRenamedAndUnlabelledBlocksAreLeftAlone() {
        let names = Reflow.sections(from: "Verse 1\na\n\nVerse 2\nb\n\nplain\n\nBridge\nc").map(\.name)
        #expect(names == ["Verse 1", "Verse 2", nil, "Bridge"])
    }

    @Test func numberedNamesSurviveTheTextRoundTrip() {
        let text = "Chorus\na\n\nVerse 1\nv\n\nChorus\nb"
        let first = Reflow.contents(primary: text, secondary: nil, maxLines: 1)
        let rebuilt = Reflow.text(from: first.map { (name: $0.sectionName, content: $0.content) }, language: .primary)
        let second = Reflow.contents(primary: rebuilt, secondary: nil, maxLines: 1)
        #expect(second.map(\.sectionName) == first.map(\.sectionName))
        #expect(second.map(\.sectionName) == ["Chorus", "Verse 1", "Chorus 2"])
        #expect(second.map(\.content) == first.map(\.content))
    }

    @Test func secondLanguagePairingIsUnaffectedByTheRenaming() {
        let result = Reflow.contents(primary: "Chorus\na\n\nChorus\nb", secondary: "Điệp khúc\nx\n\nĐiệp khúc\ny", maxLines: 1)
        #expect(result.map(\.sectionName) == ["Chorus", "Chorus 2"])
        #expect(result.map(\.content.secondary) == ["x", "y"])
    }
}
