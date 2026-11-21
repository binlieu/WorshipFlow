// LIB-004: splitting long verse text across slides at sentence or clause boundaries, never mid-word.
import Testing
@testable import ScriptureEngine

@Suite struct TextSplitterTests {
    private func collapsed(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }

    @Test func shortTextIsOnePart() {
        #expect(TextSplitter.split("Jesus wept.", maxCharacters: 50) == ["Jesus wept."])
        #expect(TextSplitter.split("  Jesus   wept. ", maxCharacters: 50) == ["Jesus wept."])
        #expect(TextSplitter.split("", maxCharacters: 50) == [])
    }

    @Test func nonPositiveLimitMeansNoLimit() {
        let text = "one two three four five"
        #expect(TextSplitter.split(text, maxCharacters: 0) == [text])
        #expect(TextSplitter.split(text, maxCharacters: -5) == [text])
    }

    @Test func prefersSentenceBoundaries() {
        let parts = TextSplitter.split("The first sentence is here. The second sentence is here.", maxCharacters: 40)
        #expect(parts == ["The first sentence is here.", "The second sentence is here."])
    }

    @Test func fallsBackToClauseBoundaries() {
        let parts = TextSplitter.split("In the beginning of days, there was light over the deep waters", maxCharacters: 40)
        #expect(parts.first == "In the beginning of days,")
        #expect(parts.count == 2)
    }

    @Test func fallsBackToAnySpaceAndNeverCutsAWord() {
        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        let parts = TextSplitter.split(text, maxCharacters: 20)
        #expect(parts.allSatisfy { $0.count <= 20 })
        #expect(collapsed(parts.joined(separator: " ")) == text)
        let words = Set(text.split(separator: " ").map(String.init))
        for part in parts { for w in part.split(separator: " ") { #expect(words.contains(String(w))) } }
    }

    @Test func aWordLongerThanTheLimitStaysWhole() {
        let parts = TextSplitter.split("a supercalifragilistic b", maxCharacters: 8)
        #expect(parts.contains("supercalifragilistic"))
        #expect(collapsed(parts.joined(separator: " ")) == "a supercalifragilistic b")
    }

    @Test func partsAreBalancedRatherThanGreedy() {
        // 3 sentences of about 30 characters with a 70 limit: two parts, not 70 + a stub.
        let text = "This is the first sentence now. This is the second sentence now. This is the third sentence now."
        let parts = TextSplitter.split(text, maxCharacters: 70)
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.count <= 70 })
    }

    @Test func vietnameseTextSplitsOnWhitespaceAndPunctuation() {
        let text = "Đức Chúa Trời yêu thương thế gian, đến nỗi đã ban Con một của Ngài. Hầu cho hễ ai tin Con ấy không bị hư mất."
        let parts = TextSplitter.split(text, maxCharacters: 70)
        #expect(parts.count == 2)
        #expect(parts[0].hasSuffix("của Ngài."))
        #expect(parts.allSatisfy { $0.count <= 70 })
        #expect(collapsed(parts.joined(separator: " ")) == text)
    }

    @Test func closingQuotesAfterAFullStopStayWithTheSentence() {
        let parts = TextSplitter.split("He said, \u{201C}Come here.\u{201D} Then he left the room quietly.", maxCharacters: 32)
        #expect(parts.first == "He said, \u{201C}Come here.\u{201D}")
    }

    @Test func splitIntoAGivenNumberOfParts() {
        let text = "One two three four. Five six seven eight. Nine ten eleven twelve."
        let parts = TextSplitter.split(text, into: 3)
        #expect(parts == ["One two three four.", "Five six seven eight.", "Nine ten eleven twelve."])
        #expect(TextSplitter.split(text, into: 1) == [text])
        #expect(TextSplitter.split("a b", into: 4) == ["a", "b", "", ""])
        #expect(TextSplitter.split("", into: 2) == ["", ""])
    }

    @Test func everyFixtureVerseSurvivesAnyLimit() {
        for (_, _, _, verse) in Fixtures.kjvVerses {
            for limit in [10, 17, 25, 40, 63, 80, 120] {
                let parts = TextSplitter.split(verse, maxCharacters: limit)
                #expect(!parts.isEmpty)
                #expect(parts.allSatisfy { !$0.isEmpty })
                #expect(collapsed(parts.joined(separator: " ")) == collapsed(verse), "\(limit): \(verse)")
                let longest = verse.split(separator: " ").map(\.count).max() ?? 0
                #expect(parts.allSatisfy { $0.count <= max(limit, longest) })
            }
        }
    }
}
