// LIB-004: keyword search inside loaded translations.
import Foundation
import Testing
@testable import ScriptureEngine

@Suite struct ScriptureSearchTests {
    private let index = ScriptureSearchIndex(Fixtures.kjv())
    private func refs(_ query: String, limit: Int = 50) -> [String] {
        index.search(query, limit: limit).hits.map { "\($0.ref.book.rawValue) \($0.ref.chapter):\($0.ref.verse)" }
    }

    @Test func allWordsMustMatchInAnyOrder() {
        #expect(refs("God world") == ["JHN 3:16", "JHN 3:17"])
        #expect(refs("world God") == ["JHN 3:16", "JHN 3:17"])
        #expect(refs("shepherd") == ["PSA 23:1"])
    }

    @Test func resultsFollowCanonOrder() {
        #expect(refs("God") == ["GEN 1:1", "GEN 1:2", "GEN 1:3", "JHN 3:16", "JHN 3:17", "JHN 3:18", "ROM 8:28"])
    }

    @Test func quotedPhrasesMatchConsecutiveWords() {
        #expect(refs("\"only begotten\"") == ["JHN 3:16", "JHN 3:18"])
        #expect(refs("\"begotten only\"") == [])
        #expect(refs("begotten only") == ["JHN 3:16", "JHN 3:18"])
        #expect(refs("\"only begotten\" condemned") == ["JHN 3:18"])
        // An unclosed quote runs to the end of the query.
        #expect(refs("\"only begotten") == ["JHN 3:16", "JHN 3:18"])
    }

    @Test func caseAndPunctuationAreFolded() {
        #expect(refs("GOD") == refs("god"))
        // An apostrophe separates words ("name's" is "name" and "s"); a quoted phrase keeps them together.
        #expect(refs("\"name's\"") == ["PSA 23:3"])
        #expect(refs("  the,   LORD!  ") == ["PSA 23:1"])
    }

    @Test func vietnameseIsMatchedWithoutDiacritics() {
        let vi = ScriptureSearchIndex(Fixtures.second())
        #expect(vi.search("cau thu JHN").hits.count == 4)
        #expect(vi.search("CÂU THỬ").hits.count == 11)
        #expect(vi.search("ban thu hai \"JHN 3:16\"").hits.count == 1)
        #expect(vi.search("bản").hits.count == 11)
    }

    @Test func wordsMatchFromTheirStartNotTheirMiddle() {
        #expect(refs("lov").count == 2)      // loved, love
        #expect(refs("ove") == [])
        #expect(refs("everlast") == ["JHN 3:16"])
    }

    @Test func limitAndTruncation() {
        let r = index.search("God", limit: 2)
        #expect(r.hits.count == 2)
        #expect(r.truncated)
        #expect(r.hits.map(\.ref.verse) == [1, 2])
        let all = index.search("God", limit: 7)
        #expect(all.hits.count == 7)
        #expect(all.truncated == false)
        #expect(index.search("God", limit: 0).hits.isEmpty)
    }

    @Test func emptyAndPunctuationQueriesFindNothingAndDoNotCrash() {
        #expect(refs("") == [])
        #expect(refs("   ") == [])
        #expect(refs("\"\"") == [])
        #expect(refs("!!! ...") == [])
        #expect(refs("\"") == [])
    }

    @Test func snippetsCentreOnTheFirstMatch() {
        let hit = index.search("condemned", limit: 5, snippetLength: 40).hits
        #expect(hit.map(\.ref.verse) == [18])
        let snippet = hit[0].snippet
        #expect(snippet.contains("condemned"))
        #expect(snippet.hasPrefix("\u{2026}"))
        #expect(snippet.count <= 40 + 20)
        // A short verse is returned whole.
        let short = ScriptureSearchIndex(Fixtures.kjv()).search("wept").hits[0]
        #expect(short.snippet == "Jesus wept.")
        #expect(short.text == "Jesus wept.")
    }

    @Test func snippetOfAPhraseStartsAtThePhrase() {
        let hit = index.search("\"begotten Son\"", limit: 5, snippetLength: 30).hits[0]
        #expect(hit.snippet.contains("begotten Son"))
    }

    @Test func fullSizeSearchIsFast() {
        let full = TranslationLoader.validate(Fixtures.syntheticFull()).translation
        #expect(full.verseCount == 31102)
        let t0 = Date()
        let big = ScriptureSearchIndex(full)
        let built = Date().timeIntervalSince(t0)
        #expect(big.verseCount == 31102)

        func timed<T>(_ body: () -> T) -> (T, Double) {
            let start = Date()
            let value = body()
            return (value, Date().timeIntervalSince(start))
        }
        let (common, tCommon) = timed { big.search("mercy peace", limit: 50) }
        let (rare, tRare) = timed { big.search("\"light and servant\" chapter", limit: 50) }
        let (none, tNone) = timed { big.search("zzzz nothing", limit: 50) }
        let (worst, tWorst) = timed { big.search("the", limit: 100_000) }
        let elapsed = tCommon + tRare + tNone + tWorst
        print("LIB-004 search timing (debug build): index build \(built)s for 31102 verses; limit-50 search \(tCommon)s; phrase \(tRare)s; no match (full scan) \(tNone)s; every verse matches \(tWorst)s (\(worst.hits.count) hits)")
        #expect(common.hits.count == 50 && common.truncated)
        #expect(!rare.hits.isEmpty)
        #expect(none.hits.isEmpty)
        #expect(worst.hits.count == 31102)
        #expect(elapsed < 10.0)
        #expect(built < 20.0)
        // Order is canon order.
        let order = common.hits.map(\.ref)
        #expect(order == order.sorted())
    }
}
