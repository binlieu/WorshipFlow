// LIB-004: keyword search inside one loaded translation, in memory.
//
// Query: words separated by spaces must all appear; a phrase in double quotes must appear as consecutive words
// (an unclosed quote runs to the end). Text and query are folded with `SearchFolding` (case, diacritics, đ and
// punctuation ignored), so "cau thu" finds "Câu thử". A word matches the start of any word in the verse
// ("lov" finds "loved"). Results follow canon order and stop at `limit`.
import Foundation
import Domain

public struct ScriptureSearchHit: Equatable, Sendable {
    public let ref: VerseRef
    public let text: String
    private let terms: [String]
    private let snippetLength: Int

    /// `terms` are folded query terms, as returned by `ScriptureSearchIndex.queryTerms`.
    public init(ref: VerseRef, text: String, terms: [String], snippetLength: Int) {
        self.ref = ref
        self.text = text
        self.terms = terms
        self.snippetLength = snippetLength
    }

    /// A short piece of the verse around the first match, with "…" where it was cut. Computed on demand.
    public var snippet: String { ScriptureSearchIndex.snippet(text: text, terms: terms, length: snippetLength) }
}

public struct ScriptureSearchResult: Equatable, Sendable {
    public var hits: [ScriptureSearchHit]
    /// True when more verses matched than `limit` allowed.
    public var truncated: Bool

    public init(hits: [ScriptureSearchHit], truncated: Bool) {
        self.hits = hits
        self.truncated = truncated
    }
}

public struct ScriptureSearchIndex: Sendable {
    private struct Entry: Sendable {
        let ref: VerseRef
        let text: String
        /// " " + folded text, so a word start is a substring starting with a space.
        let padded: String
    }

    private let entries: [Entry]
    public var verseCount: Int { entries.count }

    public init(_ translation: Translation) {
        entries = translation.allVerses().map { Entry(ref: $0.ref, text: $0.text, padded: " " + SearchFolding.fold($0.text)) }
    }

    public func search(_ query: String, limit: Int = 50, snippetLength: Int = 100) -> ScriptureSearchResult {
        let terms = Self.terms(from: query)
        guard !terms.isEmpty, limit > 0 else { return ScriptureSearchResult(hits: [], truncated: false) }
        let needles = terms.map { " " + $0 }
        var hits: [ScriptureSearchHit] = []
        var truncated = false
        for entry in entries {
            var all = true
            for needle in needles where !entry.padded.contains(needle) { all = false; break }
            guard all else { continue }
            if hits.count == limit { truncated = true; break }
            hits.append(ScriptureSearchHit(ref: entry.ref, text: entry.text, terms: terms, snippetLength: snippetLength))
        }
        return ScriptureSearchResult(hits: hits, truncated: truncated)
    }

    // MARK: Query

    /// Folded words and folded phrases (phrases keep single spaces between words). Empty ones are dropped.
    public static func queryTerms(_ query: String) -> [String] { terms(from: query) }

    static func terms(from query: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuote = false
        func flush() {
            let folded = SearchFolding.fold(current)
            current = ""
            if folded.isEmpty { return }
            if inQuote { out.append(folded) } else { out.append(contentsOf: folded.split(separator: " ").map(String.init)) }
        }
        for ch in query {
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                flush()
                inQuote.toggle()
            } else {
                current.append(ch)
            }
        }
        flush()
        return out
    }

    // MARK: Snippet

    static func snippet(text: String, terms: [String], length: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return "" }
        if text.count <= length || words.count == 1 { return words.joined(separator: " ") }
        let folded = words.map { SearchFolding.fold($0) }
        // Position of the first term, found as a run of consecutive words.
        var matchStart = 0
        var matchLength = 1
        if let first = terms.first {
            let termWords = first.split(separator: " ").map(String.init)
            search: for i in 0..<words.count {
                guard !termWords.isEmpty, i + termWords.count <= words.count else { continue }
                var ok = true
                for (offset, tw) in termWords.enumerated() {
                    let f = folded[i + offset]
                    if !(offset == termWords.count - 1 ? f.hasPrefix(tw) : f == tw) { ok = false; break }
                }
                if ok { matchStart = i; matchLength = termWords.count; break search }
            }
        }
        var lo = matchStart, hi = matchStart + matchLength - 1
        func size() -> Int { words[lo...hi].joined(separator: " ").count }
        var left = true
        while size() < length, lo > 0 || hi < words.count - 1 {
            if left, lo > 0 { lo -= 1 } else if hi < words.count - 1 { hi += 1 } else { lo -= 1 }
            left.toggle()
        }
        return (lo > 0 ? "\u{2026}" : "") + words[lo...hi].joined(separator: " ") + (hi < words.count - 1 ? "\u{2026}" : "")
    }
}
