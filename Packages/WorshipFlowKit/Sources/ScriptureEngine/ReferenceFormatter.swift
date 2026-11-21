// LIB-004: verse ranges -> display text in English or Vietnamese.
import Foundation

public enum ReferenceFormatter {
    /// En dash used for ranges.
    static let dash = "\u{2013}"

    /// "John 3:16–18", "John 3", "John 3–4", "John 3:16–4:2", "Jude 5". `part` adds a letter to a single verse
    /// ("John 3:16a"), for a slide that shows only part of a verse.
    public static func format(_ range: VerseRange, language: ScriptureLanguage = .english,
                              versification: Versification = .kjv, part: Int? = nil) -> String {
        let name = BookNames.displayName(range.book, language) ?? range.book.rawValue
        return name + " " + tail(range, versification, part: part, omitChapter: nil)
    }

    /// Several ranges: "John 3:16, 20–22", "John 3:16; 4:2", "John 3:16; Romans 8:28".
    public static func format(_ ranges: [VerseRange], language: ScriptureLanguage = .english,
                              versification: Versification = .kjv) -> String {
        var out = ""
        var previous: VerseRange?
        for range in ranges {
            if let p = previous, p.book == range.book {
                let sameChapter = isVerseForm(p, versification) && isVerseForm(range, versification)
                    && p.end.chapter == range.start.chapter && range.start.chapter == range.end.chapter
                let single = versification.chapterCount(book: range.book) == 1
                if sameChapter || (single && isVerseForm(range, versification)) {
                    out += ", " + tail(range, versification, part: nil, omitChapter: range.start.chapter)
                } else {
                    out += "; " + tail(range, versification, part: nil, omitChapter: nil)
                }
            } else {
                if !out.isEmpty { out += "; " }
                out += format(range, language: language, versification: versification)
            }
            previous = range
        }
        return out
    }

    private static func isWholeChapters(_ r: VerseRange, _ v: Versification) -> Bool {
        r.start.verse == 1 && r.end.verse == v.highestVerse(book: r.book, chapter: r.end.chapter)
    }

    private static func isVerseForm(_ r: VerseRange, _ v: Versification) -> Bool {
        !isWholeChapters(r, v) || v.chapterCount(book: r.book) == 1
    }

    private static func letter(_ part: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return part >= 0 && part < letters.count ? String(letters[part]) : "(\(part + 1))"
    }

    private static func tail(_ r: VerseRange, _ v: Versification, part: Int?, omitChapter: Int?) -> String {
        let suffix = part.map(letter) ?? ""
        let singleChapter = v.chapterCount(book: r.book) == 1
        if singleChapter {
            if r.start == r.end { return "\(r.start.verse)\(suffix)" }
            return "\(r.start.verse)\(dash)\(r.end.verse)"
        }
        if isWholeChapters(r, v) {
            return r.start.chapter == r.end.chapter ? "\(r.start.chapter)" : "\(r.start.chapter)\(dash)\(r.end.chapter)"
        }
        let startText = omitChapter == r.start.chapter ? "\(r.start.verse)" : "\(r.start.chapter):\(r.start.verse)"
        if r.start == r.end { return startText + suffix }
        if r.start.chapter == r.end.chapter { return "\(startText)\(dash)\(r.end.verse)" }
        return "\(startText)\(dash)\(r.end.chapter):\(r.end.verse)"
    }
}
