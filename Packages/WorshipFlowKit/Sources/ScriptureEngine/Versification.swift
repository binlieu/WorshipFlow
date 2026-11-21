// LIB-004: a versification is the table of how many chapters and verses each book has in one translation.
// Chapter and verse boundaries differ between translations, so validation and pairing use the table of the
// translation in question. Two tables are built in: KJV and VI1925 (the 1925 Vietnamese text).
import Foundation

public struct Versification: Sendable, Equatable {
    public struct Chapter: Sendable, Equatable {
        /// Verses that exist in the chapter.
        public var count: Int
        /// Highest verse number. Larger than `count` when the chapter has a gap in its numbering.
        public var highest: Int
        public init(count: Int, highest: Int) { self.count = count; self.highest = highest }
    }

    public let id: String
    public let books: [BookID: [Chapter]]

    public init(id: String, books: [BookID: [Chapter]]) {
        self.id = id
        self.books = books
    }

    /// Standard English (KJV) versification: 1,189 chapters, 31,102 verses.
    public static let kjv = Versification(
        id: "KJV",
        books: Dictionary(uniqueKeysWithValues: Canon.books.map { book in
            (book.id, book.verseCounts.map { Chapter(count: $0, highest: $0) })
        }))

    /// The 1925 Vietnamese text: 1,189 chapters, 31,081 verses.
    public static let vi1925: Versification = {
        var books: [BookID: [Chapter]] = [:]
        for (code, counts) in vi1925Counts {
            books[BookID(code)] = counts.map { Chapter(count: $0, highest: $0) }
        }
        for (code, chapter, highest) in vi1925Gaps {
            books[BookID(code)]?[chapter - 1].highest = highest
        }
        return Versification(id: "VI1925", books: books)
    }()

    /// A built-in table by id, ignoring case.
    public static func named(_ id: String) -> Versification? {
        switch id.uppercased() {
        case "KJV": return .kjv
        case "VI1925": return .vi1925
        default: return nil
        }
    }

    public func chapterCount(book: BookID) -> Int? { books[book]?.count }

    /// How many verses exist in the chapter. Nil when the book or chapter does not exist.
    public func verseCount(book: BookID, chapter: Int) -> Int? { chapterInfo(book, chapter)?.count }

    /// The highest valid verse number in the chapter; this is what reference validation uses.
    public func highestVerse(book: BookID, chapter: Int) -> Int? { chapterInfo(book, chapter)?.highest }

    private func chapterInfo(_ book: BookID, _ chapter: Int) -> Chapter? {
        guard let chapters = books[book], chapter >= 1, chapter <= chapters.count else { return nil }
        return chapters[chapter - 1]
    }

    public var totalChapters: Int { books.values.reduce(0) { $0 + $1.count } }
    public var totalVerses: Int { books.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } } }

    /// This table, widened where `highest` has more chapters or more verses. Never narrows.
    /// Used for a translation that numbers a few verses past the table it names.
    public func extended(with highest: [BookID: [Int]]) -> Versification {
        var out = books
        for (book, verses) in highest {
            var chapters = out[book] ?? []
            for (index, top) in verses.enumerated() {
                if index < chapters.count {
                    if top > chapters[index].highest {
                        chapters[index].highest = top
                        chapters[index].count = max(chapters[index].count, top)
                    }
                } else {
                    chapters.append(Chapter(count: top, highest: top))
                }
            }
            out[book] = chapters
        }
        return Versification(id: id + "+", books: out)
    }

    public struct Difference: Sendable, Equatable {
        public let book: BookID
        public let chapter: Int
        public let a: Chapter
        public let b: Chapter
    }

    /// Chapters whose verse counts differ, in canon order. A chapter missing from one table counts as different.
    public static func differences(_ a: Versification, _ b: Versification) -> [Difference] {
        var out: [Difference] = []
        for book in Canon.books {
            let x = a.books[book.id] ?? [], y = b.books[book.id] ?? []
            for index in 0..<max(x.count, y.count) {
                let cx = index < x.count ? x[index] : Chapter(count: 0, highest: 0)
                let cy = index < y.count ? y[index] : Chapter(count: 0, highest: 0)
                if cx != cy { out.append(Difference(book: book.id, chapter: index + 1, a: cx, b: cy)) }
            }
        }
        return out
    }
}
