// LIB-004c: a scripture passage as a playlist item. It keeps the reference (book and chapter-and-verse ranges) and the codes of the
// translations, never the words: the words are read from the church's library when the item is opened. Foundation only.
import Foundation

public struct ScriptureItemSpec: Equatable, Codable, Sendable, Hashable {
    /// One run of verses inside a book. `book` is the USFM code ("JHN").
    public struct Range: Equatable, Codable, Sendable, Hashable {
        public var book: String
        public var startChapter: Int
        public var startVerse: Int
        public var endChapter: Int
        public var endVerse: Int

        public init(book: String, startChapter: Int, startVerse: Int, endChapter: Int, endVerse: Int) {
            self.book = book
            self.startChapter = startChapter
            self.startVerse = startVerse
            self.endChapter = endChapter
            self.endVerse = endVerse
        }
    }

    /// What the playlist shows, for example "John 3:16–18 (KJV)". Written when the item was made.
    public var label: String
    public var ranges: [Range]
    /// The library code of the first translation ("kjv").
    public var primaryCode: String
    public var secondaryCode: String?

    public init(label: String, ranges: [Range], primaryCode: String, secondaryCode: String? = nil) {
        self.label = label
        self.ranges = ranges
        self.primaryCode = primaryCode
        self.secondaryCode = secondaryCode
    }

    /// The codes of every translation this item needs.
    public var translationCodes: [String] { [primaryCode] + (secondaryCode.map { [$0] } ?? []) }
}
