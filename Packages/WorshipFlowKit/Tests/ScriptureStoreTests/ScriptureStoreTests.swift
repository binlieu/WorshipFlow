// LIB-004b: storing translations in the church library. Synthetic text and the KJV fixture only.
import Testing
import Foundation
import ScriptureEngine
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore

private typealias F = StoreFixtures

private struct Injected: Error {}

@Suite struct ScriptureStoreTests {
    private func makeStore(backend: LibraryStore.SearchBackend? = nil) throws -> (LibraryStore, ScriptureStore) {
        let library = try LibraryStore.inMemory(forcing: backend)
        return (library, ScriptureStore(library: library))
    }

    private func counts(_ library: LibraryStore) async throws -> (translations: Int, verses: Int, indexed: Int) {
        try await library.scriptureRead { db in
            let t = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureTranslation") ?? -1
            let v = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureVerse") ?? -1
            let i = try db.tableExists("scriptureSearch") ? (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureSearch") ?? -1) : 0
            return (t, v, i)
        }
    }

    // MARK: Import and read back

    @Test func emptyStoreHasNoTranslations() async throws {
        let (_, store) = try makeStore()
        #expect(try await store.translations().isEmpty)
    }

    @Test func importStoresMetadataAndEveryVerse() async throws {
        let (library, store) = try makeStore()
        let result = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        #expect(result.replaced == false)
        #expect(result.report.verseCount == 11)
        let list = try await store.translations()
        let t = try #require(list.first)
        #expect(list.count == 1)
        #expect(t == result.translation)
        #expect(t.code == "kjv" && t.name == "King James Version (test fixture)" && t.language == "en" && t.abbreviation == "KJV")
        #expect(t.copyright == "Public domain in the United States" && t.licence == "Public domain" && t.sourceDescription == "test fixture")
        #expect(t.isPublicDomain && t.versificationID == "KJV" && t.versificationNote == "KJV versification")
        #expect(t.ownerApproval == OwnerApproval(approved: true, date: "2026-11-20", note: "fixture"))
        #expect(t.verseCount == 11)
        #expect(abs(t.importedAt.timeIntervalSinceNow) < 60)
        #expect(t.metadata.id == "kjv" && t.metadata.license == "Public domain" && t.metadata.sourceURL == "test fixture")
        let c = try await counts(library)
        #expect(c.translations == 1 && c.verses == 11)
        #expect(c.indexed == (library.scriptureSearchUsesFTS5 ? 11 : 0))
    }

    @Test func versesComeBackExactlyInRangeAndCanonOrder() async throws {
        let (_, store) = try makeStore()
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        let one = try await store.verses(in: [F.range("JHN", 3, 16, 3, 16)], translationCode: "kjv")
        #expect(one == [StoredVerse(ref: F.ref("JHN", 3, 16), text: F.kjvVerses[6].3)])
        // A range across a chapter boundary returns only the verses that exist.
        let across = try await store.verses(in: [F.range("GEN", 1, 2, 1, 40)], translationCode: "kjv")
        #expect(across.map(\.ref) == [F.ref("GEN", 1, 2), F.ref("GEN", 1, 3)])
        // Several ranges come back in the order asked, each in canon order; a verse asked twice is returned twice.
        let many = try await store.verses(in: [F.range("PSA", 23, 1, 23, 2), F.range("GEN", 1, 1, 1, 1), F.range("PSA", 23, 2, 23, 2)],
                                          translationCode: "KJV")
        #expect(many.map(\.ref) == [F.ref("PSA", 23, 1), F.ref("PSA", 23, 2), F.ref("GEN", 1, 1), F.ref("PSA", 23, 2)])
        #expect(try await store.verses(in: [F.range("JHN", 5, 1, 5, 5)], translationCode: "kjv").isEmpty)
        #expect(try await store.verses(in: [], translationCode: "kjv").isEmpty)
    }

    @Test func unknownTranslationCodeIsAnErrorNotAnEmptyResult() async throws {
        let (_, store) = try makeStore()
        await #expect(throws: ScriptureStoreError.notFound("nope")) {
            _ = try await store.verses(in: [F.range("JHN", 3, 16, 3, 16)], translationCode: "nope")
        }
        await #expect(throws: ScriptureStoreError.notFound("nope")) { _ = try await store.search("god", translationCode: "nope", limit: 5) }
        await #expect(throws: ScriptureStoreError.notFound("nope")) { _ = try await store.versification(for: "nope") }
        await #expect(throws: ScriptureStoreError.notFound("nope")) { try await store.deleteTranslation(code: "nope") }
    }

    @Test func vietnameseAndStackedDiacriticsRoundTripByteForByte() async throws {
        let (_, store) = try makeStore()
        _ = try await store.importTranslation(F.vietnameseFile(), replaceExisting: false)
        let got = try await store.verses(in: [F.range("PSA", 23, 1, 23, 2), F.range("JHN", 3, 16, 3, 17)], translationCode: "vi-test")
        let expected = [F.vietnamese[2], F.vietnamese[3], F.vietnamese[0], F.vietnamese[1]].map(\.3)
        #expect(got.map(\.text) == expected)
        // Equal as Swift strings is not enough: the scalars must be the same (no silent normalisation).
        for (a, b) in zip(got.map(\.text), expected) { #expect(Array(a.unicodeScalars) == Array(b.unicodeScalars)) }
        #expect(got[1].text.unicodeScalars.contains("\u{0323}"))
    }

    @Test func verseTextWithTabsNewlinesBackslashesAndQuotesRoundTrips() async throws {
        let (_, store) = try makeStore()
        let nasty = "tab\there\nnew line \\ back\\slash \"double\" 'single' %_ ; -- DROP TABLE scriptureVerse"
        var file = F.kjvFile()
        file.setVerse(nasty, book: BookID("JUD"), chapter: 1, verse: 1)
        _ = try await store.importTranslation(file, replaceExisting: false)
        let got = try await store.verses(in: [F.range("JUD", 1, 1, 1, 1)], translationCode: "kjv")
        #expect(got.first?.text == nasty)
    }

    // MARK: Duplicates, replace, failure

    @Test func reimportingWithoutReplaceFailsAndChangesNothing() async throws {
        let (library, store) = try makeStore()
        let first = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        var changed = F.kjvFile()
        changed.setVerse("DIFFERENT", book: BookID("GEN"), chapter: 1, verse: 1)
        await #expect(throws: ScriptureStoreError.alreadyExists("kjv")) {
            _ = try await store.importTranslation(changed, replaceExisting: false)
        }
        // The code is unique ignoring case.
        await #expect(throws: ScriptureStoreError.alreadyExists("KJV")) {
            _ = try await store.importTranslation(F.kjvFile(code: "KJV"), replaceExisting: false)
        }
        #expect(try await store.translations() == [first.translation])
        #expect(try await store.verses(in: [F.range("GEN", 1, 1, 1, 1)], translationCode: "kjv").first?.text == F.kjvVerses[0].3)
        let c = try await counts(library)
        #expect(c.translations == 1 && c.verses == 11)
    }

    @Test func replaceSwapsTheTextKeepsTheIdAndUpdatesSearch() async throws {
        let (library, store) = try makeStore()
        let first = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        var changed = TranslationFile(metadata: F.kjvMetadata, books: [:])
        changed.metadata.name = "Renamed"
        changed.setVerse("Brand new zebra words", book: BookID("GEN"), chapter: 1, verse: 1)
        changed.setVerse("Second verse", book: BookID("GEN"), chapter: 1, verse: 2)
        let second = try await store.importTranslation(changed, replaceExisting: true)
        #expect(second.replaced)
        #expect(second.translation.id == first.translation.id)
        #expect(second.translation.name == "Renamed" && second.translation.verseCount == 2)
        let c = try await counts(library)
        #expect(c.translations == 1 && c.verses == 2 && c.indexed == (library.scriptureSearchUsesFTS5 ? 2 : 0))
        #expect(try await store.search("zebra", translationCode: "kjv", limit: 5).hits.map(\.ref) == [F.ref("GEN", 1, 1)])
        #expect(try await store.search("shepherd", translationCode: "kjv", limit: 5).hits.isEmpty)
    }

    @Test func replacingWithoutAnExistingTranslationJustImports() async throws {
        let (_, store) = try makeStore()
        let r = try await store.importTranslation(F.kjvFile(), replaceExisting: true)
        #expect(r.replaced == false)
        #expect(try await store.translations().count == 1)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func aFailedImportLeavesNothingBehind(_ backend: LibraryStore.SearchBackend) async throws {
        let library = try LibraryStore.inMemory(forcing: backend)
        let store = ScriptureStore(library: library, afterBatch: { written in if written >= 4 { throw Injected() } }, batchSize: 2)
        await #expect(throws: Injected.self) { _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false) }
        let c = try await counts(library)
        #expect(c.translations == 0 && c.verses == 0 && c.indexed == 0)
        #expect(try await ScriptureStore(library: library).translations().isEmpty)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func aFailedReplaceKeepsTheOldTranslationWhole(_ backend: LibraryStore.SearchBackend) async throws {
        let library = try LibraryStore.inMemory(forcing: backend)
        let good = ScriptureStore(library: library)
        let first = try await good.importTranslation(F.kjvFile(), replaceExisting: false)
        let failing = ScriptureStore(library: library, afterBatch: { written in if written >= 2 { throw Injected() } }, batchSize: 1)
        var other = TranslationFile(metadata: F.kjvMetadata, books: [:])
        for n in 1...5 { other.setVerse("new \(n)", book: BookID("EXO"), chapter: 1, verse: n) }
        await #expect(throws: Injected.self) { _ = try await failing.importTranslation(other, replaceExisting: true) }
        #expect(try await good.translations() == [first.translation])
        let c = try await counts(library)
        #expect(c.verses == 11 && c.indexed == (library.scriptureSearchUsesFTS5 ? 11 : 0))
        #expect(try await good.verses(in: [F.range("JHN", 11, 35, 11, 35)], translationCode: "kjv").first?.text == "Jesus wept.")
        #expect(try await good.search("shepherd", translationCode: "kjv", limit: 3).hits.count == 1)
    }

    @Test func aTranslationWithNoVersesIsRefused() async throws {
        let (library, store) = try makeStore()
        let empty = TranslationFile(metadata: F.kjvMetadata, books: ["GEN": ["1": ["1": "   "]], "XXX": ["1": ["1": "x"]]])
        await #expect(throws: ScriptureStoreError.emptyTranslation) { _ = try await store.importTranslation(empty, replaceExisting: false) }
        #expect(try await counts(library).translations == 0)
    }

    @Test func blankCodeNameOrLanguageIsRefused() async throws {
        let (library, store) = try makeStore()
        for mutate in [{ (m: inout TranslationMetadata) in m.id = "  " }, { m in m.name = "" }, { m in m.language = " " }, { m in m.abbreviation = "" }] {
            var file = F.kjvFile()
            mutate(&file.metadata)
            await #expect(throws: ScriptureStoreError.self) { _ = try await store.importTranslation(file, replaceExisting: false) }
        }
        #expect(try await counts(library).translations == 0)
    }

    @Test func deleteRemovesVersesAndIndexAndLeavesOtherTranslations() async throws {
        let (library, store) = try makeStore()
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        _ = try await store.importTranslation(F.vietnameseFile(), replaceExisting: false)
        try await store.deleteTranslation(code: "KJV")
        #expect(try await store.translations().map(\.code) == ["vi-test"])
        let c = try await counts(library)
        #expect(c.translations == 1 && c.verses == F.vietnamese.count && c.indexed == (library.scriptureSearchUsesFTS5 ? F.vietnamese.count : 0))
        #expect(try await store.search("duc chua troi", translationCode: "vi-test", limit: 5).hits.count == 1)
        // The code can be used again afterwards.
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        #expect(try await store.translations().count == 2)
    }

    @Test func progressIsReportedInOrderAndEndsAtTheTotal() async throws {
        let (_, store) = try makeStore()
        let box = ProgressBox()
        let file = F.syntheticFull()
        _ = try await store.importTranslation(file, replaceExisting: false) { box.add($0) }
        let seen = box.all
        #expect(seen.count > 10)
        #expect(seen.map(\.versesDone) == seen.map(\.versesDone).sorted())
        #expect(seen.last?.versesDone == 31_102 && seen.last?.versesTotal == 31_102)
        #expect(seen.first?.versesDone == 0)
    }

    // MARK: Versification

    @Test func builtInAndOwnTablesRoundTrip() async throws {
        let (_, store) = try makeStore()
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        var vi = F.vietnameseFile(code: "vi", versification: "VI1925")
        vi.setVerse("x", book: BookID("REV"), chapter: 12, verse: 18)     // the 1925 table has 18 verses there
        _ = try await store.importTranslation(vi, replaceExisting: false)
        #expect(try await store.versification(for: "kjv") == .kjv)
        #expect(try await store.versification(for: "VI") == .vi1925)
        #expect(try await store.translations().first { $0.code == "vi" }?.versificationID == "VI1925")

        // A file with its own table, and one numbered past its table (the loader widens the table to "KJV+").
        var own = TranslationFile(metadata: TranslationMetadata(id: "own", name: "Own", language: "en", abbreviation: "OWN", versification: "OWN-TABLE",
                                                              versificationTable: ["GEN": [[2, 2], [0, 0], [2, 4]]]), books: [:])
        own.setBook(BookID("GEN"), chapters: [1: [1: "a", 2: "b"], 3: [1: "c", 4: "d"]])
        _ = try await store.importTranslation(own, replaceExisting: false)
        let table = try await store.versification(for: "own")
        #expect(table.id == "OWN-TABLE")
        #expect(table.books[BookID("GEN")] == [.init(count: 2, highest: 2), .init(count: 0, highest: 0), .init(count: 2, highest: 4)])

        var wide = F.kjvFile(code: "wide")
        wide.setVerse("extra", book: BookID("3JN"), chapter: 1, verse: 15)
        _ = try await store.importTranslation(wide, replaceExisting: false)
        let widened = try await store.versification(for: "wide")
        #expect(widened.highestVerse(book: BookID("3JN"), chapter: 1) == 15)
        #expect(widened.highestVerse(book: BookID("JHN"), chapter: 3) == 36)
    }

    // MARK: Persistence on disk

    @Test func importSurvivesCloseAndReopenAndSharesTheLibraryFile() async throws {
        let url = F.tempURL()
        let library = try LibraryStore.open(at: url)
        let store = ScriptureStore(library: library)
        // A song written through the same store while a translation is imported.
        let lib = try await library.createLibrary(name: "Songs")
        async let imported = store.importTranslation(F.syntheticFull(), replaceExisting: false)
        async let song = library.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        let (r, s) = try await (imported, song)
        #expect(r.translation.verseCount == 31_102)
        try library.close()

        let reopened = try LibraryStore.open(at: url)
        let again = ScriptureStore(library: reopened)
        #expect(try await again.translations().map(\.verseCount) == [31_102])
        #expect(try await reopened.search("grace", limit: 5).map(\.presentationID) == [s.id])
        #expect(try await again.search("shepherd", translationCode: "syn", limit: 3).hits.count == 3)
        try reopened.close()
    }

    @Test func oldLibraryFileGetsTheTablesWhenOpenedNormally() async throws {
        let url = F.tempURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v6")
        try old.close()
        let library = try LibraryStore.open(at: url)
        let store = ScriptureStore(library: library)
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        #expect(try await store.translations().count == 1)
        try library.close()
    }

    @Test func aStoreOnAVersionBeforeV7IsAClearErrorNotACrash() async throws {
        let library = try LibraryStore.open(at: F.tempURL(), migratingUpTo: "v6")
        let store = ScriptureStore(library: library)
        await #expect(throws: ScriptureStoreError.libraryNeedsUpdate) { _ = try await store.translations() }
        await #expect(throws: ScriptureStoreError.libraryNeedsUpdate) { _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false) }
        try library.close()
    }
}

final class ProgressBox: @unchecked Sendable {   // test helper: guarded by a lock
    private let lock = NSLock()
    private var items: [ScriptureImportProgress] = []
    func add(_ p: ScriptureImportProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [ScriptureImportProgress] { lock.lock(); defer { lock.unlock() }; return items }
}
