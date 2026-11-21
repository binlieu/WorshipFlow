// LIB-004b: keyword search over stored verses. The same answers as the in-memory ScriptureSearchIndex, on both the
// FTS5 and the LIKE path. Synthetic text and the KJV fixture only.
import Testing
import Foundation
import ScriptureEngine
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore

private typealias F = StoreFixtures

@Suite struct ScriptureStoreSearchTests {
    private func store(_ backend: LibraryStore.SearchBackend) async throws -> ScriptureStore {
        let library = try LibraryStore.inMemory(forcing: backend)
        let store = ScriptureStore(library: library)
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        _ = try await store.importTranslation(F.vietnameseFile(), replaceExisting: false)
        return store
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func foldedSearchFindsVietnameseWithoutDiacritics(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        let hits = try await store.search("duc chua troi", translationCode: "vi-test", limit: 10).hits
        #expect(hits.map(\.ref) == [F.ref("JHN", 3, 16)])
        #expect(hits.first?.text == F.vietnamese[0].3)                          // the original text, not the folded one
        #expect(try await store.search("ĐỨC CHÚA TRỜI", translationCode: "vi-test", limit: 10).hits.count == 1)
        // Stacked combining marks fold like their precomposed form.
        #expect(try await store.search("nen ta noi", translationCode: "vi-test", limit: 10).hits.map(\.ref) == [F.ref("PSA", 23, 2)])
        #expect(try await store.search("nệ", translationCode: "vi-test", limit: 10).hits.map(\.ref) == [F.ref("PSA", 23, 2)])
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func allWordsMustMatchAndWordsMatchByPrefix(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        #expect(try await store.search("god loved", translationCode: "kjv", limit: 10).hits.map(\.ref) == [F.ref("JHN", 3, 16)])
        #expect(try await store.search("lov", translationCode: "kjv", limit: 10).hits.map(\.ref) == [F.ref("JHN", 3, 16), F.ref("ROM", 8, 28)])
        #expect(try await store.search("oved", translationCode: "kjv", limit: 10).hits.isEmpty)     // word start only
        #expect(try await store.search("god zebra", translationCode: "kjv", limit: 10).hits.isEmpty)
        #expect(try await store.search("", translationCode: "kjv", limit: 10).hits.isEmpty)
        #expect(try await store.search("   ...  ", translationCode: "kjv", limit: 10).hits.isEmpty)
        #expect(try await store.search("god", translationCode: "kjv", limit: 0).hits.isEmpty)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func quotedPhrasesNeedConsecutiveWords(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        #expect(try await store.search("\"only begotten son\"", translationCode: "kjv", limit: 10).hits.map(\.ref) == [F.ref("JHN", 3, 16), F.ref("JHN", 3, 18)])
        #expect(try await store.search("\"begotten only\"", translationCode: "kjv", limit: 10).hits.isEmpty)
        #expect(try await store.search("\"the earth\" spirit", translationCode: "kjv", limit: 10).hits.map(\.ref) == [F.ref("GEN", 1, 2)])
        #expect(try await store.search("\"the earth", translationCode: "kjv", limit: 10).hits.count == 2)   // unclosed quote runs to the end
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func resultsFollowCanonOrderAndReportTruncation(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        let all = try await store.search("the", translationCode: "kjv", limit: 50)
        #expect(all.hits.map(\.ref) == all.hits.map(\.ref).sorted())
        #expect(all.truncated == false)
        let two = try await store.search("the", translationCode: "kjv", limit: 2)
        #expect(two.hits.count == 2 && two.truncated)
        #expect(two.hits.map(\.ref) == Array(all.hits.map(\.ref).prefix(2)))
        let exact = try await store.search("the", translationCode: "kjv", limit: all.hits.count)
        #expect(exact.hits.count == all.hits.count && exact.truncated == false)
        #expect(!two.hits[0].snippet.isEmpty)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func searchStaysInsideTheNamedTranslation(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        #expect(try await store.search("god", translationCode: "vi-test", limit: 10).hits.isEmpty)
        #expect(try await store.search("tho", translationCode: "kjv", limit: 10).hits.isEmpty)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func hostileQueriesAreJustWords(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try await store(backend)
        for q in ["\"'; DROP TABLE scriptureVerse; --", "* ( ) OR NEAR AND NOT", "god%", "_od", "a\"b\"c\"", "\\"] {
            _ = try await store.search(q, translationCode: "kjv", limit: 5)
        }
        #expect(try await store.translations().count == 2)
        // Punctuation is a separator after folding, so "god%" is the word "god" and `_od` is the prefix "od", never a wildcard.
        #expect(try await store.search("god%", translationCode: "kjv", limit: 50).hits.map(\.ref) == (try await store.search("god", translationCode: "kjv", limit: 50)).hits.map(\.ref))
        #expect(try await store.search("_od", translationCode: "kjv", limit: 50).hits.isEmpty)
    }

    /// The store and the in-memory index answer alike for a spread of queries on a larger synthetic translation.
    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func sameAnswersAsTheInMemoryIndex(_ backend: LibraryStore.SearchBackend) async throws {
        let library = try LibraryStore.inMemory(forcing: backend)
        let store = ScriptureStore(library: library)
        let file = F.syntheticFull(versification: .kjv)
        let loaded = TranslationLoader.validate(file)
        _ = try await store.importTranslation(file, replaceExisting: false)
        let index = ScriptureSearchIndex(loaded.translation)
        for query in ["light mercy", "\"water and\" river", "shepherd", "fai gra", "verse 12 in chapter 3", "\"of verse 7\"", "zzz", "morning temple wind"] {
            let expected = index.search(query, limit: 40)
            let got = try await store.search(query, translationCode: "syn", limit: 40)
            #expect(got.hits.map(\.ref) == expected.hits.map(\.ref), "\(query)")
            #expect(got.truncated == expected.truncated, "\(query)")
            #expect(got.hits.map(\.snippet) == expected.hits.map(\.snippet), "\(query)")
        }
    }
}
