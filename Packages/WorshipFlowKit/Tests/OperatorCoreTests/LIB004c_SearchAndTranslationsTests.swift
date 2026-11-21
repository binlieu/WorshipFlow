// LIB-004c items 6 and 7: searching verse text, and the translations screen (list, import with progress, remove after asking).
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct LIB004c_SearchAndTranslationsTests {
    // MARK: search

    @Test func aVietnameseWordTypedWithoutDiacriticsFindsTheVerse() async throws {
        let r = try await L4C.rig()
        await r.scripture.setPrimary("vi-test")
        await r.scripture.search("binh an")
        let first = try #require(r.scripture.searchResults.first)
        #expect(first.reference == "Giăng 3:16")
        #expect(first.snippet.contains("bình an"))
        #expect(r.scripture.searchResults.count == 1)
        await r.scripture.search("DAN chien")
        #expect(r.scripture.searchResults.first?.reference == "Giăng 3:16")
    }

    @Test func englishSearchListsEveryVerseWithItsReferenceInCanonOrder() async throws {
        let r = try await L4C.rig()
        await r.scripture.search("lantern")
        #expect(r.scripture.searchResults.count == 18)
        #expect(r.scripture.searchResults.first?.reference == "John 3:1" && r.scripture.searchResults.last?.reference == "John 3:18")
        #expect(r.scripture.searchTruncated == false)
        await r.scripture.search("zzzzqq")
        #expect(r.scripture.searchResults.isEmpty && r.scripture.searchMessage?.contains("Nothing found") == true)
        await r.scripture.search("   ")
        #expect(r.scripture.searchResults.isEmpty && r.scripture.searchMessage == nil)
    }

    @Test func choosingAResultOpensItsPassageInPreview() async throws {
        let r = try await L4C.rig()
        await r.scripture.setPrimary("vi-test")
        await r.scripture.search("binh an")
        let row = try #require(r.scripture.searchResults.first)
        await r.scripture.openSearchResult(row)
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.first?.verses.first == VerseRef(book: BookID("JHN"), chapter: 3, verse: 16))
        #expect(r.scripture.referenceText == "Giăng 3:16")
        #expect(r.workspace.show.previewDeck?.slides == passage.contents)
        #expect(r.workspace.show.liveDeck == nil)
    }

    @Test func searchWithNothingInstalledSaysSo() async throws {
        let r = try await L4C.rig(install: [])
        await r.scripture.search("light")
        #expect(r.scripture.searchResults.isEmpty)
        #expect(r.scripture.searchMessage?.contains("Import") == true)
    }

    // MARK: the translations screen

    func write(_ file: TranslationFile) throws -> URL {
        let url = L4C.temp("translation.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.encoded().write(to: url)
        return url
    }

    @Test func theListShowsNameLanguageVerseCountAndTheCopyrightLineTheFileCarried() async throws {
        let r = try await L4C.rig()
        let rows = r.scripture.translations
        let en = try #require(rows.first { $0.code == "en-test" })
        #expect(en.name == "English test text" && en.language == "en" && en.verseCount == 18 + 3 + 1 + 3)
        #expect(en.copyright == "Invented for tests. No rights reserved.")
        let line = TranslationRow.copyrightLine(en)
        #expect(line == "Invented for tests. No rights reserved.")
        var bare = en
        bare.copyright = nil
        #expect(TranslationRow.copyrightLine(bare).contains("No copyright line"))
        #expect(TranslationRow.languageName("vi") == "Vietnamese" && TranslationRow.languageName("en") == "English")
    }

    @Test func importingAFileAddsItAndSaysWhatHappened() async throws {
        let r = try await L4C.rig(install: [])
        let url = try write(L4C.english())
        await r.scripture.importTranslation(from: url)
        #expect(r.scripture.translations.map(\.code) == ["en-test"])
        guard case .finished(let message) = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(message.contains("English test text") && message.contains("25"), Comment(rawValue: message))
        #expect(r.scripture.primaryCode == "en-test", "the first translation becomes the primary")
        await r.scripture.show("Psalm 23:1")
        #expect(r.scripture.passage != nil)
    }

    @Test func importingTheSameCodeAgainAsksBeforeReplacing() async throws {
        let r = try await L4C.rig(install: [L4C.english()])
        let url = try write(L4C.english(name: "Renamed text"))
        await r.scripture.importTranslation(from: url)
        #expect(r.scripture.importState == .needsReplace(code: "en-test", name: "Renamed text"))
        #expect(r.scripture.translations.first?.name == "English test text", "nothing changed yet")
        await r.scripture.confirmReplace()
        #expect(r.scripture.translations.first?.name == "Renamed text")
        guard case .finished = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        // And saying no leaves it as it was.
        await r.scripture.importTranslation(from: try write(L4C.english(name: "Third name")))
        r.scripture.cancelReplace()
        #expect(r.scripture.importState == .idle && r.scripture.translations.first?.name == "Renamed text")
    }

    @Test func aFileThatIsNotATranslationGivesAPlainMessageAndChangesNothing() async throws {
        let r = try await L4C.rig(install: [L4C.english()])
        let url = L4C.temp("notes.txt")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("just some words".utf8).write(to: url)
        await r.scripture.importTranslation(from: url)
        guard case .failed(let message) = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(message.contains("notes.txt") && message.contains("translation"), Comment(rawValue: message))
        #expect(r.scripture.translations.count == 1)
    }

    @Test func aMissingFileGivesAPlainMessage() async throws {
        let r = try await L4C.rig(install: [])
        await r.scripture.importTranslation(from: L4C.temp("nothing-here.json"))
        guard case .failed(let message) = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(message.contains("nothing-here.json"))
    }

    @Test func progressIsReportedWhileAnImportRuns() async throws {
        let r = try await L4C.rig(install: [])
        var seen: [ScriptureImportState] = []
        r.scripture.onImportState = { seen.append($0) }
        await r.scripture.importTranslation(from: try write(L4C.english()))
        let running = seen.compactMap { state -> (Int, Int)? in if case .running(let d, let t) = state { return (d, t) }; return nil }
        #expect(!running.isEmpty)
        #expect(running.last.map { $0.0 <= $0.1 } == true)
        if case .finished = seen.last { } else { Issue.record("\(String(describing: seen.last))") }
    }
}
