// LIB-004b: speed on a synthetic full-size translation (31,102 verses, filler text). Numbers are printed for the report;
// the limits are generous so a slow machine or a debug build does not fail them, but a quadratic mistake would.
import Testing
import Foundation
import ScriptureEngine
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore

private typealias F = StoreFixtures

@Suite struct ScriptureStorePerformanceTests {
    @Test func importFetchAndSearchOnAFullSizeTranslation() async throws {
        let url = F.tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = try LibraryStore.open(at: url)
        let store = ScriptureStore(library: library)
        let file = F.syntheticFull()
        let clock = ContinuousClock()

        let importTime = try await clock.measure { _ = try await store.importTranslation(file, replaceExisting: false) }
        print("LIB-004b perf (\(library.scriptureSearchUsesFTS5 ? "FTS5" : "LIKE"), file-backed, debug build): import 31,102 verses \(importTime)")
        #expect(importTime < .seconds(30))

        var verses: [StoredVerse] = []
        // Best of five: the whole suite runs in parallel, and one slow turn on a busy machine is not a slow fetch.
        var fetch = Duration.seconds(3600)
        for _ in 0..<5 {
            let once = try await clock.measure { verses = try await store.verses(in: [F.range("PSA", 119, 1, 119, 176)], translationCode: "syn") }
            fetch = min(fetch, once)
        }
        print("LIB-004b perf: fetch Psalm 119 (176 verses) \(fetch)")
        #expect(verses.count == 176 && fetch < .seconds(1))

        var hits = ScriptureSearchResult(hits: [], truncated: false)
        let common = try await clock.measure { hits = try await store.search("light water", translationCode: "syn", limit: 50) }
        print("LIB-004b perf: search 'light water' limit 50: \(hits.hits.count) hits, truncated \(hits.truncated), \(common)")
        #expect(hits.hits.count == 50 && common < .seconds(2))

        var none = ScriptureSearchResult(hits: [], truncated: false)
        let miss = try await clock.measure { none = try await store.search("zzzz", translationCode: "syn", limit: 50) }
        print("LIB-004b perf: search with no match \(miss)")
        #expect(none.hits.isEmpty && miss < .seconds(2))

        var phrase = ScriptureSearchResult(hits: [], truncated: false)
        let phraseTime = try await clock.measure { phrase = try await store.search("\"fill the line\"", translationCode: "syn", limit: 50) }
        print("LIB-004b perf: phrase search matching every verse, limit 50: \(phrase.hits.count) hits, \(phraseTime)")
        #expect(phrase.hits.count == 50 && phraseTime < .seconds(2))

        let replace = try await clock.measure { _ = try await store.importTranslation(file, replaceExisting: true) }
        print("LIB-004b perf: replace the same translation \(replace)")
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("LIB-004b perf: library file after import and replace: \(size / 1024) KiB (WAL not checkpointed)")
        try library.close()
    }
}
