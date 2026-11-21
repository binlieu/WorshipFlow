// LIB-004: verse references and ranges.
import Foundation

public struct VerseRef: Hashable, Sendable, Codable, Comparable {
    public var book: BookID
    public var chapter: Int
    public var verse: Int

    public init(book: BookID, chapter: Int, verse: Int) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    /// Canon order, then chapter, then verse.
    public static func < (a: VerseRef, b: VerseRef) -> Bool {
        if a.book != b.book { return a.book < b.book }
        if a.chapter != b.chapter { return a.chapter < b.chapter }
        return a.verse < b.verse
    }
}

/// A run of verses inside one book, from `start` to `end` inclusive. May cross chapters.
public struct VerseRange: Hashable, Sendable, Codable {
    public var start: VerseRef
    public var end: VerseRef

    public var book: BookID { start.book }

    public init(start: VerseRef, end: VerseRef) {
        self.start = start
        self.end = end
    }

    public init(book: BookID, startChapter: Int, startVerse: Int, endChapter: Int, endVerse: Int) {
        self.init(start: VerseRef(book: book, chapter: startChapter, verse: startVerse),
                  end: VerseRef(book: book, chapter: endChapter, verse: endVerse))
    }

    public init(_ ref: VerseRef) { self.init(start: ref, end: ref) }

    /// Every verse in the range under `versification`, in order. Verse numbers run 1...highest in each chapter;
    /// the caller decides what to do about numbers a translation does not contain.
    public func verses(in versification: Versification) -> [VerseRef] {
        var out: [VerseRef] = []
        guard start.book == end.book, start <= end else { return out }
        var chapter = start.chapter
        while chapter <= end.chapter {
            guard let highest = versification.highestVerse(book: book, chapter: chapter) else { break }
            let first = chapter == start.chapter ? start.verse : 1
            let last = chapter == end.chapter ? min(end.verse, highest) : highest
            if first <= last { for v in first...last { out.append(VerseRef(book: book, chapter: chapter, verse: v)) } }
            chapter += 1
        }
        return out
    }
}
