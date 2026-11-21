// LIB-004: a loaded translation and the loader that validates a file.
import Foundation

public struct Translation: Sendable {
    public let metadata: TranslationMetadata
    /// The verse-count table this text follows, widened if the text numbers verses past it.
    public let versification: Versification
    let verses: [BookID: [Int: [Int: String]]]

    public var language: ScriptureLanguage { ScriptureLanguage(languageTag: metadata.language) }
    public var verseCount: Int { verses.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }

    public func text(for ref: VerseRef) -> String? { verses[ref.book]?[ref.chapter]?[ref.verse] }

    /// Every verse in canon order.
    public func allVerses() -> [(ref: VerseRef, text: String)] {
        var out: [(VerseRef, String)] = []
        out.reserveCapacity(verseCount)
        for book in verses.keys.sorted() {
            guard let chapters = verses[book] else { continue }
            for chapter in chapters.keys.sorted() {
                guard let items = chapters[chapter] else { continue }
                for verse in items.keys.sorted() {
                    if let text = items[verse] { out.append((VerseRef(book: book, chapter: chapter, verse: verse), text)) }
                }
            }
        }
        return out
    }
}

public enum TranslationCoverage: Equatable, Sendable {
    case complete
    case newTestamentOnly
    case oldTestamentOnly
    case partial(books: Int)
}

/// What the loader found. Counts, not exceptions: a damaged verse never blocks the rest.
public struct TranslationReport: Equatable, Sendable {
    public var bookCount = 0
    /// Chapters with at least one verse.
    public var chapterCount = 0
    public var verseCount = 0
    public var coverage: TranslationCoverage = .partial(books: 0)
    /// Book keys that are not USFM codes of the 66 books. Their verses are skipped.
    public var unknownBooks: [String] = []
    /// Chapter or verse keys that are not numbers ("3:1" style), as "JHN chapter y" / "JHN 3 verse x".
    public var invalidKeys: [String] = []
    /// Verses written twice under different spellings of the same number ("16" and "016"), as "JHN 3:16".
    public var duplicateVerses: [String] = []
    public var emptyVerseCount = 0
    /// For each present book, chapters of its table that have no verses. Absent books are not listed.
    public var missingChapters: [String: [Int]] = [:]
    public var missingChapterCount: Int { missingChapters.values.reduce(0) { $0 + $1.count } }
    /// Verses missing from chapters that are present.
    public var missingVerseCount = 0
    /// Verses past the end of the table the file names; kept, and the table is widened.
    public var versesBeyondTable = 0
    /// Operator-readable summary lines. Empty for a clean, complete translation.
    public var messages: [String] = []
}

public struct LoadedTranslation: Sendable {
    public let translation: Translation
    public let report: TranslationReport
}

public enum TranslationLoader {
    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }

    /// Reads and validates JSON. Throws only when the file as a whole cannot be used.
    public static func load(from data: Data) throws -> LoadedTranslation {
        let decoder = JSONDecoder()
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) } catch {
            throw TranslationLoadError.notJSON(describe(error))
        }
        guard header.format == TranslationFile.formatName else { throw TranslationLoadError.wrongFormat(header.format) }
        guard let version = header.version else { throw TranslationLoadError.missingVersion }
        guard version <= TranslationFile.currentVersion else { throw TranslationLoadError.unsupportedVersion(version) }
        do {
            return validate(try decoder.decode(TranslationFile.self, from: data))
        } catch let error as DecodingError {
            throw TranslationLoadError.invalid(describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, let ctx):
            let path = (ctx.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
            return "missing field \(path)"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? ctx.debugDescription : "\(path): \(ctx.debugDescription)"
        @unknown default: return "unreadable"
        }
    }

    /// Checks a decoded file and builds the translation.
    public static func validate(_ file: TranslationFile) -> LoadedTranslation {
        var report = TranslationReport()
        var verses: [BookID: [Int: [Int: String]]] = [:]

        for bookKey in file.books.keys.sorted() {
            guard let chapters = file.books[bookKey] else { continue }
            let book = BookID(bookKey)
            guard Canon.book(book) != nil else { report.unknownBooks.append(bookKey); continue }
            for (chapterKey, chapterNumber) in numbered(Array(chapters.keys)) {
                guard let chapterNumber else { report.invalidKeys.append("\(bookKey) chapter \(chapterKey)"); continue }
                guard let items = chapters[chapterKey] else { continue }
                for (verseKey, verseNumber) in numbered(Array(items.keys)) {
                    guard let verseNumber else { report.invalidKeys.append("\(bookKey) \(chapterNumber) verse \(verseKey)"); continue }
                    let text = (items[verseKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { report.emptyVerseCount += 1; continue }
                    if verses[book]?[chapterNumber]?[verseNumber] != nil {
                        report.duplicateVerses.append("\(bookKey) \(chapterNumber):\(verseNumber)")
                        continue
                    }
                    verses[book, default: [:]][chapterNumber, default: [:]][verseNumber] = text
                }
            }
        }

        // Table in use.
        var table = Versification.kjv
        if let name = file.metadata.versification {
            if let named = Versification.named(name) { table = named } else {
                report.messages.append("The versification “\(name)” is not known; the KJV verse-count table was used.")
            }
        }

        var highest: [BookID: [Int]] = [:]
        for (book, chapters) in verses {
            let top = chapters.keys.max() ?? 0
            var list = Array(repeating: 0, count: top)
            for (chapter, items) in chapters { list[chapter - 1] = items.keys.max() ?? 0 }
            highest[book] = list
            for (chapter, items) in chapters {
                guard let limit = table.highestVerse(book: book, chapter: chapter) else {
                    report.versesBeyondTable += items.count
                    continue
                }
                report.versesBeyondTable += items.keys.filter { $0 > limit }.count
            }
        }
        if report.versesBeyondTable > 0 {
            table = table.extended(with: highest)
            report.messages.append("\(report.versesBeyondTable) verse\(report.versesBeyondTable == 1 ? "" : "s") are numbered beyond the \(file.metadata.versification ?? "KJV") table. They are kept; references to them are accepted for this translation.")
        }

        // Coverage and gaps.
        report.bookCount = verses.count
        report.verseCount = verses.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        report.chapterCount = verses.values.reduce(0) { $0 + $1.count }
        let ot = Canon.books[..<39].filter { verses[$0.id] != nil }.count
        let nt = Canon.books[39...].filter { verses[$0.id] != nil }.count
        if ot + nt == 66 { report.coverage = .complete }
        else if ot == 0 && nt == 27 { report.coverage = .newTestamentOnly }
        else if nt == 0 && ot == 39 { report.coverage = .oldTestamentOnly }
        else { report.coverage = .partial(books: ot + nt) }

        for book in Canon.books {
            guard let chapters = verses[book.id], let tableChapters = table.books[book.id] else { continue }
            var missing: [Int] = []
            for (index, info) in tableChapters.enumerated() {
                let number = index + 1
                guard let items = chapters[number] else { missing.append(number); continue }
                let present = items.keys.filter { $0 >= 1 && $0 <= info.highest }.count
                report.missingVerseCount += max(0, info.count - present)
            }
            if !missing.isEmpty { report.missingChapters[book.id.rawValue] = missing }
        }

        if !report.unknownBooks.isEmpty {
            let n = report.unknownBooks.count
            report.messages.append("Skipped \(n) book\(n == 1 ? "" : "s") that \(n == 1 ? "is" : "are") not in the 66-book canon: \(report.unknownBooks.joined(separator: ", ")).")
        }
        if !report.invalidKeys.isEmpty {
            report.messages.append("\(report.invalidKeys.count) chapter or verse key\(report.invalidKeys.count == 1 ? " is" : "s are") not a number and was skipped.")
        }
        if !report.duplicateVerses.isEmpty {
            report.messages.append("\(report.duplicateVerses.count) duplicate verse\(report.duplicateVerses.count == 1 ? "" : "s") ignored (the first was kept).")
        }
        if report.emptyVerseCount > 0 {
            report.messages.append("\(report.emptyVerseCount) empty verse\(report.emptyVerseCount == 1 ? "" : "s") skipped.")
        }
        switch report.coverage {
        case .complete: break
        case .newTestamentOnly: report.messages.append("Partial translation: New Testament only (27 books).")
        case .oldTestamentOnly: report.messages.append("Partial translation: Old Testament only (39 books).")
        case .partial(let books): report.messages.append("Partial translation: \(books) of 66 books.")
        }
        if report.missingChapterCount > 0 {
            report.messages.append("\(report.missingChapterCount) chapters are missing from books that are present.")
        }
        if report.missingVerseCount > 0 {
            report.messages.append("\(report.missingVerseCount) verses are missing from chapters that are present.")
        }

        let translation = Translation(metadata: file.metadata, versification: table, verses: verses)
        return LoadedTranslation(translation: translation, report: report)
    }

    /// Keys with their numeric value (nil when not a plain decimal number), duplicates ordered so that the plain
    /// spelling ("16") comes before padded spellings ("016").
    private static func numbered(_ keys: [String]) -> [(String, Int?)] {
        keys.map { key -> (String, Int?) in
            if let n = Int(key), n >= 1 { return (key, n) }
            return (key, nil)
        }.sorted { a, b in
            switch (a.1, b.1) {
            case let (x?, y?): return x != y ? x < y : (a.0.count != b.0.count ? a.0.count < b.0.count : a.0 < b.0)
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.0 < b.0
            }
        }
    }
}
