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

    /// A table from its stored form: book code -> `[count, highest]` per chapter (see `tableRepresentation`).
    /// Nil when a book is not in the canon, a chapter is not a pair, or a count is negative or above its highest verse.
    public init?(id: String, table: [String: [[Int]]]) {
        var books: [BookID: [Chapter]] = [:]
        for (code, rows) in table {
            let book = BookID(code)
            guard Canon.book(book) != nil else { return nil }
            var chapters: [Chapter] = []
            for row in rows {
                guard row.count == 2, row[0] >= 0, row[0] <= row[1] else { return nil }
                chapters.append(Chapter(count: row[0], highest: row[1]))
            }
            books[book] = chapters
        }
        self.init(id: id, books: books)
    }

    /// Book code -> `[count, highest]` per chapter: the form kept in a translation file and in the library.
    public var tableRepresentation: [String: [[Int]]] {
        Dictionary(uniqueKeysWithValues: books.map { ($0.key.rawValue, $0.value.map { [$0.count, $0.highest] }) })
    }

    /// The table a set of verses implies: for each book that has any verse, chapters 1 to the highest chapter present;
    /// a chapter has the number of verses present and the highest verse number present, and a chapter with no verses
    /// is `[0, 0]`. Used to describe a translation that follows no built-in table.
    public static func derived(id: String, from refs: some Sequence<VerseRef>) -> Versification {
        var counts: [BookID: [Int: (count: Int, highest: Int)]] = [:]
        var seen = Set<VerseRef>()
        for ref in refs where ref.chapter >= 1 && ref.verse >= 1 && seen.insert(ref).inserted {
            var entry = counts[ref.book, default: [:]][ref.chapter] ?? (0, 0)
            entry.count += 1
            entry.highest = max(entry.highest, ref.verse)
            counts[ref.book, default: [:]][ref.chapter] = entry
        }
        var books: [BookID: [Chapter]] = [:]
        for (book, chapters) in counts {
            let top = chapters.keys.max() ?? 0
            books[book] = (1...max(top, 1)).map { number in
                chapters[number].map { Chapter(count: $0.count, highest: $0.highest) } ?? Chapter(count: 0, highest: 0)
            }
        }
        return Versification(id: id, books: books)
    }

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
