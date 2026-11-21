// LIB-004b: fixtures for the store tests. The only Bible text is the eleven King James Version verses already allowed
// in ScriptureEngineTests/Fixtures.swift (public domain in the United States). Everything else is synthetic filler.
import Foundation
import ScriptureEngine
import Persistence
@_spi(ScriptureStore) import Persistence
@testable import ScriptureStore

enum StoreFixtures {
    static let kjvVerses: [(String, Int, Int, String)] = [
        ("GEN", 1, 1, "In the beginning God created the heaven and the earth."),
        ("GEN", 1, 2, "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters."),
        ("GEN", 1, 3, "And God said, Let there be light: and there was light."),
        ("PSA", 23, 1, "The LORD is my shepherd; I shall not want."),
        ("PSA", 23, 2, "He maketh me to lie down in green pastures: he leadeth me beside the still waters."),
        ("PSA", 23, 3, "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake."),
        ("JHN", 3, 16, "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
        ("JHN", 3, 17, "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."),
        ("JHN", 3, 18, "He that believeth on him is not condemned: but he that believeth not is condemned already, because he hath not believed in the name of the only begotten Son of God."),
        ("JHN", 11, 35, "Jesus wept."),
        ("ROM", 8, 28, "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."),
    ]

    static let kjvMetadata = TranslationMetadata(
        id: "kjv", name: "King James Version (test fixture)", language: "en", abbreviation: "KJV",
        copyright: "Public domain in the United States", license: "Public domain", sourceURL: "test fixture",
        isPublicDomain: true, versificationNote: "KJV versification", versification: "KJV",
        ownerApproval: OwnerApproval(approved: true, date: "2026-11-20", note: "fixture"))

    static func kjvFile(code: String = "kjv") -> TranslationFile {
        var metadata = kjvMetadata
        metadata.id = code
        var file = TranslationFile(metadata: metadata, books: [:])
        for (book, c, v, text) in kjvVerses { file.setVerse(text, book: BookID(book), chapter: c, verse: v) }
        return file
    }

    /// Synthetic Vietnamese-looking filler with stacked diacritics, in decomposed and precomposed forms. Not scripture.
    static let vietnamese: [(String, Int, Int, String)] = [
        ("JHN", 3, 16, "Đức Chúa Trời ở cùng chúng tôi trong buổi họp tối nay, nhưng câu này chỉ là văn bản thử."),
        ("JHN", 3, 17, "Nguyễn Hoàng đi từ Việt Nam đến chợ, mua bánh mì và nước."),
        ("PSA", 23, 1, "Đức Giê-hô-va không có trong câu này; đây là dòng chữ thử nghiệm thứ ba."),
        // Two combining marks stacked on one base letter (decomposed form), as some databases store them.
        ("PSA", 23, 2, "Ne\u{0302}\u{0323}n ta no\u{0302}\u{0301}i va\u{0309} chu\u{031B}\u{0301}ng."),
    ]

    static func vietnameseFile(code: String = "vi-test", versification: String = "KJV") -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(id: code, name: "Vietnamese test", language: "vi", abbreviation: "VT",
                                                               copyright: "synthetic", license: "synthetic", isPublicDomain: false,
                                                               versification: versification), books: [:])
        for (book, c, v, text) in vietnamese { file.setVerse(text, book: BookID(book), chapter: c, verse: v) }
        return file
    }

    /// A synthetic translation covering the whole table: filler text with repeated words. Not scripture.
    static func syntheticFull(code: String = "syn", versification: Versification = .kjv, language: String = "en") -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(id: code, name: "Synthetic", language: language, abbreviation: "SYN",
                                                               versification: versification.id), books: [:])
        let words = ["light", "water", "mercy", "shepherd", "kingdom", "peace", "truth", "bread", "voice", "mountain",
                     "river", "faith", "grace", "temple", "servant", "garden", "stone", "fire", "wind", "morning"]
        var n = 0
        for book in Canon.books {
            var chapters: [Int: [Int: String]] = [:]
            for (ci, ch) in (versification.books[book.id] ?? []).enumerated() {
                var verses: [Int: String] = [:]
                for v in 1...max(ch.count, 1) where v <= ch.count {
                    n += 1
                    verses[v] = "\(words[n % 20]) and \(words[(n / 7) % 20]) came to the \(words[(n / 3) % 20]) of verse \(v) in chapter \(ci + 1) with many other plain words to fill the line"
                }
                chapters[ci + 1] = verses
            }
            file.setBook(book.id, chapters: chapters)
        }
        return file
    }

    static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    static func ref(_ book: String, _ c: Int, _ v: Int) -> VerseRef { VerseRef(book: BookID(book), chapter: c, verse: v) }
    static func range(_ book: String, _ c1: Int, _ v1: Int, _ c2: Int, _ v2: Int) -> VerseRange {
        VerseRange(book: BookID(book), startChapter: c1, startVerse: v1, endChapter: c2, endVerse: v2)
    }
}
