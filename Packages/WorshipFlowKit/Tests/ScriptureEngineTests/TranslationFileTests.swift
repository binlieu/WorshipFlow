// LIB-004: the translation file format (JSON, version 1), its loader and the validation report.
import Foundation
import Testing
@testable import ScriptureEngine

@Suite struct TranslationFileTests {
    private func report(_ json: String) throws -> LoadedTranslation {
        try TranslationLoader.load(from: Data(json.utf8))
    }

    private func wrap(_ books: String, meta: String = "") -> String {
        """
        {"format":"worshipflow.translation","version":1,
         "metadata":{"id":"t","name":"T","language":"en","abbreviation":"T"\(meta)},
         "books":\(books)}
        """
    }

    @Test func roundTripThroughJSON() throws {
        let data = try Fixtures.file().encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"format\" : \"worshipflow.translation\""))
        #expect(text.contains("\"version\" : 1"))
        let loaded = try TranslationLoader.load(from: data)
        #expect(loaded.translation.text(for: VerseRef(book: BookID("JHN"), chapter: 3, verse: 16))?.hasPrefix("For God so loved") == true)
        #expect(loaded.translation.metadata == Fixtures.kjvMetadata)
        #expect(loaded.report.verseCount == 11)
        // Encoding is stable, so a file can be diffed.
        #expect(try Fixtures.file().encoded() == data)
    }

    @Test func documentedExampleLoads() throws {
        let json = """
        {
          "format": "worshipflow.translation",
          "version": 1,
          "metadata": {
            "id": "example", "name": "Example", "language": "en", "abbreviation": "EX",
            "copyright": "None", "license": "Public domain", "sourceURL": "https://example.org/",
            "isPublicDomain": true, "versificationNote": "Follows KJV", "versification": "KJV",
            "ownerApproval": {"approved": true, "date": "2026-11-20", "note": "Owner decision"}
          },
          "books": {"JHN": {"3": {"16": "Text.", "17": "More text."}}}
        }
        """
        let loaded = try report(json)
        #expect(loaded.translation.metadata.ownerApproval == OwnerApproval(approved: true, date: "2026-11-20", note: "Owner decision"))
        #expect(loaded.translation.metadata.isPublicDomain)
        #expect(loaded.translation.text(for: VerseRef(book: BookID("JHN"), chapter: 3, verse: 17)) == "More text.")
        #expect(loaded.translation.text(for: VerseRef(book: BookID("JHN"), chapter: 3, verse: 18)) == nil)
    }

    @Test func optionalMetadataHasDefaults() throws {
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"x"}}}"#))
        #expect(loaded.translation.metadata.isPublicDomain == false)
        #expect(loaded.translation.metadata.ownerApproval == nil)
        #expect(loaded.translation.metadata.copyright == nil)
    }

    @Test func notJSONAndWrongFormatAreErrors() {
        #expect(throws: TranslationLoadError.self) { try TranslationLoader.load(from: Data("not json".utf8)) }
        #expect(throws: TranslationLoadError.self) { try TranslationLoader.load(from: Data("[]".utf8)) }
        do {
            _ = try TranslationLoader.load(from: Data(#"{"format":"other","version":1,"metadata":{},"books":{}}"#.utf8))
            Issue.record("expected an error")
        } catch let error as TranslationLoadError {
            #expect(error.message.contains("worshipflow.translation"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func newerVersionIsRefusedWithAClearMessage() {
        do {
            _ = try TranslationLoader.load(from: Data(#"{"format":"worshipflow.translation","version":2,"metadata":{"id":"t","name":"T","language":"en","abbreviation":"T"},"books":{}}"#.utf8))
            Issue.record("expected an error")
        } catch let error as TranslationLoadError {
            #expect(error == .unsupportedVersion(2))
            #expect(error.message.contains("version 2"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func missingMetadataFieldIsReported() {
        do {
            _ = try TranslationLoader.load(from: Data(#"{"format":"worshipflow.translation","version":1,"metadata":{"id":"t"},"books":{}}"#.utf8))
            Issue.record("expected an error")
        } catch let error as TranslationLoadError {
            #expect(error.message.contains("metadata"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func unknownBooksAndBadKeysAreCounted() throws {
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"a","x":"b"},"y":{"1":"c"}},"XYZ":{"1":{"1":"d"}},"john":{"1":{"1":"e"}}}"#))
        #expect(loaded.report.unknownBooks == ["XYZ", "john"])
        #expect(loaded.report.invalidKeys.count == 2)
        #expect(loaded.report.verseCount == 1)
        #expect(loaded.report.messages.contains { $0.contains("2 books") && $0.contains("XYZ") })
    }

    @Test func duplicateVersesAreReportedAndTheFirstIsKept() throws {
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"first","016":"second","17":"other"}}}"#))
        #expect(loaded.report.duplicateVerses == ["JHN 3:16"])
        #expect(loaded.translation.text(for: VerseRef(book: BookID("JHN"), chapter: 3, verse: 16)) == "first")
        #expect(loaded.report.verseCount == 2)
        #expect(loaded.report.messages.contains { $0.contains("1 duplicate") })
    }

    @Test func missingChaptersAndVersesAreCounted() throws {
        // John 3 has 36 verses; only 2 are present. Chapters 2 and 4...21 are missing; chapter 1 is absent too.
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"a","17":"b"}}}"#))
        #expect(loaded.report.missingChapters == ["JHN": Array(1...21).filter { $0 != 3 }])
        #expect(loaded.report.missingChapterCount == 20)
        #expect(loaded.report.missingVerseCount == 34)
        #expect(loaded.report.messages.contains { $0.contains("20 chapters") })
    }

    @Test func emptyVerseTextIsCountedAndNotKept() throws {
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"  ","17":"b"}}}"#))
        #expect(loaded.report.emptyVerseCount == 1)
        #expect(loaded.translation.text(for: VerseRef(book: BookID("JHN"), chapter: 3, verse: 16)) == nil)
    }

    @Test func partialTranslationsAreAllowedAndReportedAsSuch() throws {
        let nt = Fixtures.syntheticFull(books: Canon.books[39...])
        let loadedNT = TranslationLoader.validate(nt)
        #expect(loadedNT.report.coverage == .newTestamentOnly)
        #expect(loadedNT.report.bookCount == 27)
        #expect(loadedNT.report.verseCount == 7957)
        #expect(loadedNT.report.missingChapterCount == 0)
        #expect(loadedNT.report.messages.contains { $0.contains("New Testament only") })

        let ot = TranslationLoader.validate(Fixtures.syntheticFull(books: Canon.books[..<39]))
        #expect(ot.report.coverage == .oldTestamentOnly)

        let some = TranslationLoader.validate(Fixtures.file())
        #expect(some.report.coverage == .partial(books: 4))

        let full = TranslationLoader.validate(Fixtures.syntheticFull())
        #expect(full.report.coverage == .complete)
        #expect(full.report.verseCount == 31102)
        #expect(full.report.chapterCount == 1189)
        #expect(full.report.missingVerseCount == 0)
        #expect(full.report.messages.isEmpty)
    }

    @Test func namedVersificationIsUsedAndOverflowIsReported() throws {
        let json = wrap(#"{"3JN":{"1":{"14":"a","15":"b"}}}"#, meta: #","versification":"KJV""#)
        let kjv = try report(json)
        #expect(kjv.report.versesBeyondTable == 1)
        #expect(kjv.report.messages.contains { $0.contains("beyond") })
        // The verse is kept and the translation's own table is widened to hold it.
        #expect(kjv.translation.text(for: VerseRef(book: BookID("3JN"), chapter: 1, verse: 15)) == "b")
        #expect(kjv.translation.versification.highestVerse(book: BookID("3JN"), chapter: 1) == 15)

        let vi = try report(wrap(#"{"3JN":{"1":{"14":"a","15":"b"}}}"#, meta: #","versification":"VI1925""#))
        #expect(vi.report.versesBeyondTable == 0)
        #expect(vi.translation.versification.id == "VI1925")
    }

    @Test func unknownVersificationFallsBackToKJVWithAMessage() throws {
        let loaded = try report(wrap(#"{"JHN":{"3":{"16":"a"}}}"#, meta: #","versification":"MARS""#))
        #expect(loaded.translation.versification.id == "KJV")
        #expect(loaded.report.messages.contains { $0.contains("MARS") })
    }

    @Test func versesComeBackInCanonOrder() {
        let t = Fixtures.kjv()
        let refs = t.allVerses().map(\.ref)
        #expect(refs == refs.sorted())
        #expect(refs.first == VerseRef(book: BookID("GEN"), chapter: 1, verse: 1))
        #expect(refs.last == VerseRef(book: BookID("ROM"), chapter: 8, verse: 28))
    }

    @Test func ownerApprovalSurvivesARoundTrip() throws {
        var meta = Fixtures.kjvMetadata
        meta.ownerApproval = OwnerApproval(approved: true, date: "2026-11-20", note: "Approved by the owner")
        let file = Fixtures.file(metadata: meta)
        let loaded = try TranslationLoader.load(from: file.encoded())
        #expect(loaded.translation.metadata.ownerApproval?.approved == true)
        #expect(loaded.translation.metadata.ownerApproval?.note == "Approved by the owner")
    }
}
