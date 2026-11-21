// LIB-004b: turns the rows of one database version into a translation file and says what is wrong with them.
//
// Books are mapped by `book_order` (1...66) to the canon. A row is skipped, and counted in the report, when its book is
// outside 1...66, its chapter or verse number is below 1, or its text is empty. A verse that appears twice keeps the
// first row; if the second text differs, that is reported separately because it means the database disagrees with itself.
// Gaps (verse numbers missing below the highest verse of a chapter, chapters missing below the highest chapter of a book)
// are reported, not filled in. Nothing is normalised: text is written exactly as read.
import Foundation
import Domain
import ScriptureEngine

struct ExportMetadata: Equatable {
    var id: String?
    var name: String?
    var language: String?
    var abbreviation: String?
    var copyright: String?
    var licence: String?
    var source: String?
    var isPublicDomain = false
    var ownerApproved = false
    var ownerApprovalDate: String?
    var ownerApprovalNote: String?
    /// "KJV", "VI1925" or "derived"; nil decides from the data.
    var versification: String?
}

struct ExportReport: Equatable {
    var versionCode = ""
    var rowsRead = 0
    var verseCount = 0
    var bookCount = 0
    var chapterCount = 0
    var skippedBadBook: [Int: Int] = [:]
    var skippedBadNumber = 0
    var emptyVerses: [String] = []
    var duplicates: [String] = []
    var conflictingDuplicates: [String] = []
    /// "GEN 3: 5, 9" style: verse numbers missing below the highest verse of a chapter.
    var verseGaps: [String] = []
    var chapterGaps: [String] = []
    var versification = ""
    var versificationReason = ""
    var nullTexts = 0
    var suspectedMojibake = 0
    var bookNameMismatches: [String] = []
    var partial = false

    var hasProblems: Bool {
        !skippedBadBook.isEmpty || skippedBadNumber > 0 || !emptyVerses.isEmpty || !duplicates.isEmpty || !conflictingDuplicates.isEmpty
            || !verseGaps.isEmpty || !chapterGaps.isEmpty || suspectedMojibake > 0 || !bookNameMismatches.isEmpty
    }

    /// Lines for the operator: what was found, in plain language, worst things first.
    var lines: [String] {
        var out = ["Version \(versionCode): \(rowsRead) rows read, \(verseCount) verses in \(bookCount) books (\(chapterCount) chapters) written."]
        if partial { out.append("Partial translation: \(bookCount) of 66 books.") }
        out.append("Verse numbering: \(versification) (\(versificationReason)).")
        if !conflictingDuplicates.isEmpty { out.append("PROBLEM: \(conflictingDuplicates.count) verses appear twice with different text (the first was kept): \(Self.sample(conflictingDuplicates)).") }
        if !duplicates.isEmpty { out.append("\(duplicates.count) verses appear twice with the same text (one kept): \(Self.sample(duplicates)).") }
        if !skippedBadBook.isEmpty {
            let total = skippedBadBook.values.reduce(0, +)
            out.append("\(total) rows skipped because book_order is not 1 to 66 (found: \(skippedBadBook.keys.sorted().map(String.init).joined(separator: ", "))).")
        }
        if skippedBadNumber > 0 { out.append("\(skippedBadNumber) rows skipped because the chapter or verse number is below 1.") }
        if !emptyVerses.isEmpty { out.append("\(emptyVerses.count) verses are empty and were skipped: \(Self.sample(emptyVerses)).") }
        if nullTexts > 0 { out.append("\(nullTexts) of those are NULL in the database.") }
        if !chapterGaps.isEmpty { out.append("Chapters missing inside books: \(Self.sample(chapterGaps)).") }
        if !verseGaps.isEmpty { out.append("\(verseGaps.count) chapters have verse numbers missing: \(Self.sample(verseGaps)).") }
        if suspectedMojibake > 0 { out.append("WARNING: \(suspectedMojibake) verses contain character pairs typical of text stored in the wrong character set (such as “Ã” or “á»”). Check the database's character set before using this file.") }
        for line in bookNameMismatches.prefix(5) { out.append("WARNING: \(line)") }
        if bookNameMismatches.count > 5 { out.append("WARNING: \(bookNameMismatches.count - 5) more books have names that differ from the canon.") }
        if !hasProblems { out.append("No empty verses, duplicates or gaps found.") }
        return out
    }

    private static func sample(_ items: [String]) -> String {
        let shown = items.prefix(8).joined(separator: "; ")
        return items.count > 8 ? shown + "; and \(items.count - 8) more" : shown
    }
}

enum TranslationExporter {
    static let notStated = "not stated"

    /// - Throws: `MySQLError.data` when a required metadata value (language) is missing, or no verse was usable.
    static func build(code: String, versionName: String?, rows: [RawVerse], bookNames: [Int: String] = [:],
                      metadata: ExportMetadata, sourceDescription: String) throws -> (file: TranslationFile, report: ExportReport) {
        guard let language = metadata.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty else {
            throw MySQLError.data("--language is required: the database does not say which language the version is in (for example --language vi).")
        }
        var report = ExportReport()
        report.versionCode = code
        report.rowsRead = rows.count

        var chapters: [BookID: [Int: [Int: String]]] = [:]
        for row in rows {
            guard row.bookOrder >= 1, row.bookOrder <= Canon.books.count else { report.skippedBadBook[row.bookOrder, default: 0] += 1; continue }
            let book = Canon.books[row.bookOrder - 1].id
            guard row.chapter >= 1, row.verse >= 1 else { report.skippedBadNumber += 1; continue }
            let label = "\(book.rawValue) \(row.chapter):\(row.verse)"
            guard let text = row.text else { report.nullTexts += 1; report.emptyVerses.append(label); continue }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { report.emptyVerses.append(label); continue }
            if let first = chapters[book]?[row.chapter]?[row.verse] {
                if first == text { report.duplicates.append(label) } else { report.conflictingDuplicates.append(label) }
                continue
            }
            chapters[book, default: [:]][row.chapter, default: [:]][row.verse] = text
            if looksMisencoded(text) { report.suspectedMojibake += 1 }
        }
        report.verseCount = chapters.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        guard report.verseCount > 0 else {
            throw MySQLError.data("version “\(code)” has no usable verses (\(rows.count) rows read, all skipped). Nothing was written.")
        }
        report.bookCount = chapters.count
        report.chapterCount = chapters.values.reduce(0) { $0 + $1.count }
        report.partial = chapters.count < 66

        // Gaps.
        for book in Canon.books {
            guard let present = chapters[book.id] else { continue }
            let top = present.keys.max() ?? 0
            let missing = (1...max(top, 1)).filter { present[$0] == nil && $0 <= top }
            if !missing.isEmpty { report.chapterGaps.append("\(book.id.rawValue) \(missing.map(String.init).joined(separator: ","))") }
            for chapter in present.keys.sorted() {
                guard let verses = present[chapter], let highest = verses.keys.max() else { continue }
                let absent = (1...highest).filter { verses[$0] == nil }
                if !absent.isEmpty { report.verseGaps.append("\(book.id.rawValue) \(chapter): \(absent.prefix(6).map(String.init).joined(separator: ","))" + (absent.count > 6 ? ",…" : "")) }
            }
        }

        // Book names cross-check (the books table, when the owner's columns were found).
        for (order, name) in bookNames.sorted(by: { $0.key < $1.key }) where order >= 1 && order <= Canon.books.count {
            let canonName = BookNames.displayName(Canon.books[order - 1].id, .english) ?? ""
            if SearchFolding.fold(name) != SearchFolding.fold(canonName) {
                report.bookNameMismatches.append("book_order \(order) is “\(name)” in the database but \(canonName) in the canon; verses are mapped by order.")
            }
        }

        // Versification.
        let refs = chapters.flatMap { book, items in items.flatMap { chapter, verses in verses.keys.map { VerseRef(book: book, chapter: chapter, verse: $0) } } }
        let derived = Versification.derived(id: "DERIVED-\(code)", from: refs)
        var versificationName: String
        var table: [String: [[Int]]]?
        var note: String?
        let requested = metadata.versification?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requested, !requested.isEmpty, requested.lowercased() != "derived" {
            guard let named = Versification.named(requested) else {
                throw MySQLError.data("--versification must be KJV, VI1925 or derived.")
            }
            let mismatches = mismatchedChapters(derived, named)
            versificationName = named.id
            report.versificationReason = "named with --versification; \(mismatches) chapters of the data end at a different verse than the table"
        } else if requested?.lowercased() != "derived", let named = [Versification.kjv, Versification.vi1925].first(where: { mismatchedChapters(derived, $0) == 0 }) {
            versificationName = named.id
            report.versificationReason = "every chapter in the data ends where the \(named.id) table does"
        } else {
            versificationName = derived.id
            table = derived.tableRepresentation
            let kjv = mismatchedChapters(derived, .kjv), vi = mismatchedChapters(derived, .vi1925)
            report.versificationReason = "matches neither built-in table (\(kjv) chapters differ from KJV, \(vi) from VI1925), so the table was derived from the data and is stored in the file"
            note = "Verse-count table derived from the exported data (differs from KJV in \(kjv) chapters, from VI1925 in \(vi))."
        }
        report.versification = versificationName

        var meta = TranslationMetadata(
            id: nonEmpty(metadata.id) ?? code,
            name: nonEmpty(metadata.name) ?? nonEmpty(versionName) ?? code,
            language: language,
            abbreviation: nonEmpty(metadata.abbreviation) ?? code,
            copyright: nonEmpty(metadata.copyright) ?? notStated,
            license: nonEmpty(metadata.licence) ?? notStated,
            sourceURL: nonEmpty(metadata.source) ?? sourceDescription,
            isPublicDomain: metadata.isPublicDomain,
            versificationNote: note,
            versification: versificationName,
            ownerApproval: metadata.ownerApproved ? OwnerApproval(approved: true, date: nonEmpty(metadata.ownerApprovalDate), note: nonEmpty(metadata.ownerApprovalNote)) : nil)
        meta.versificationTable = table

        var file = TranslationFile(metadata: meta, books: [:])
        for (book, items) in chapters { file.setBook(book, chapters: items) }
        return (file, report)
    }

    /// UTF-8 bytes read as Latin-1 leave a letter from U+00C2...U+00F4 followed by a control or symbol from U+0080...U+00BF
    /// ("Ã" + "º", "á" + "»"). Real Vietnamese, English and the like never put those two next to each other.
    static func looksMisencoded(_ text: String) -> Bool {
        var previous: UInt32 = 0
        for scalar in text.unicodeScalars {
            if (0xC2...0xF4).contains(previous), (0x80...0xBF).contains(scalar.value) { return true }
            previous = scalar.value
        }
        return false
    }

    /// Chapters present in `data` whose highest verse differs from the table's (or that the table lacks).
    static func mismatchedChapters(_ data: Versification, _ table: Versification) -> Int {
        var count = 0
        for (book, chapters) in data.books {
            for (index, chapter) in chapters.enumerated() where chapter.highest > 0 {
                if table.books[book].flatMap({ index < $0.count ? $0[index] : nil })?.highest != chapter.highest { count += 1 }
            }
        }
        return count
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
