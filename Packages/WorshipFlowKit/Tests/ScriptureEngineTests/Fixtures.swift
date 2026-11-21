// LIB-004: test fixtures. The only Bible text in the repository: a few King James Version verses (public domain
// in the United States), under 30 in all. The "second translation" is synthetic placeholder text, not scripture.
import Foundation
@testable import ScriptureEngine

enum Fixtures {
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
        id: "kjv-fixture", name: "King James Version (test fixture)", language: "en", abbreviation: "KJV",
        copyright: "Public domain in the United States", license: "Public domain", sourceURL: nil,
        isPublicDomain: true, versificationNote: "KJV versification", versification: "KJV", ownerApproval: nil)

    static func file(_ verses: [(String, Int, Int, String)] = kjvVerses, metadata: TranslationMetadata = kjvMetadata) -> TranslationFile {
        var file = TranslationFile(metadata: metadata, books: [:])
        for (book, c, v, text) in verses { file.setVerse(text, book: BookID(book), chapter: c, verse: v) }
        return file
    }

    static func kjv() -> Translation {
        TranslationLoader.validate(file()).translation
    }

    /// Placeholder text for a second translation: "[B] JHN 3:16 second text" style, not scripture.
    static func second(language: String = "vi", skipping: Set<String> = []) -> Translation {
        var file = TranslationFile(metadata: TranslationMetadata(id: "second", name: "Second (synthetic)", language: language,
                                                               abbreviation: language == "vi" ? "TH2" : "SEC"), books: [:])
        for (book, c, v, _) in kjvVerses where !skipping.contains("\(book) \(c):\(v)") {
            let text = language == "vi" ? "Câu thử \(book) \(c):\(v) của bản thứ hai." : "Second text \(book) \(c):\(v)."
            file.setVerse(text, book: BookID(book), chapter: c, verse: v)
        }
        return TranslationLoader.validate(file).translation
    }

    /// A synthetic translation covering the whole table: filler text with a few repeated words, built for
    /// size checks and search timing. Not scripture.
    static func syntheticFull(versification: Versification = .kjv, books: ArraySlice<Book> = Canon.books[...]) -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(id: "synthetic", name: "Synthetic", language: "en", abbreviation: "SYN"), books: [:])
        let words = ["light", "water", "mercy", "shepherd", "kingdom", "peace", "truth", "bread", "voice", "mountain",
                     "river", "faith", "grace", "temple", "servant", "garden", "stone", "fire", "wind", "morning"]
        var n = 0
        for book in books {
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
}
