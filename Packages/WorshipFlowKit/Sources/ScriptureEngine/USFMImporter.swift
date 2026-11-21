// LIB-004: import one book from USFM text.
//
// Kept: verse text from \v, with poetry and paragraph breaks joined by one space; character styles such as
// \w ... \w*, \nd, \add, \wj, \qs are unwrapped (word attributes after "|" are dropped).
// Stripped with their content: footnotes \f ... \f*, cross references \x ... \x*, figures, alternate and
// published verse numbers.
// Skipped and counted in `ignoredMarkers`: headings, titles, running headers, remarks and other lines that are
// not verse text (\s, \r, \d, \h, \toc, \mt, \rem ...). Psalm titles (\d) are therefore not kept.
// Dropped and counted in `unknownMarkers`: any marker this importer does not know. The marker itself is never
// shown; the words after it are kept, because they may be scripture.
import Foundation

public struct USFMImportReport: Equatable, Sendable {
    public var verseCount = 0
    public var chapterCount = 0
    /// Footnotes and cross references removed.
    public var notesStripped = 0
    /// Known markers whose text is not verse text, by marker name as written.
    public var ignoredMarkers: [String: Int] = [:]
    public var unknownMarkers: [String: Int] = [:]
    /// Verse numbers that appeared twice, as "chapter:verse". The first text is kept.
    public var duplicateVerses: [String] = []
    /// Verse bridges such as `\v 1-2`, as "chapter:1-2". The text is stored at the first number.
    public var bridgedVerses: [String] = []
    public var warnings: [String] = []
}

public struct USFMImportResult: Sendable {
    /// Nil when there was no `\id` line or its code is not one of the 66 books.
    public var book: BookID?
    /// chapter -> verse -> text.
    public var chapters: [Int: [Int: String]]
    public var report: USFMImportReport
}

public enum USFMImporter {
    private static let noteMarkers: Set<String> = ["f", "fe", "ef", "x", "ex"]
    private static let stripWithContent: Set<String> = ["fig", "ca", "va", "vp", "rq"]
    private static let paragraphMarkers: Set<String> = [
        "p", "m", "mi", "pi", "pc", "pr", "pm", "pmo", "pmc", "pmr", "nb", "b", "q", "qr", "qc", "qm", "li", "lim",
        "lh", "lf", "ph", "cls", "tr", "th", "thr", "tc", "tcr",
    ]
    private static let ignoredLineMarkers: Set<String> = [
        "ide", "usfm", "h", "toc", "mt", "mte", "ms", "mr", "s", "sr", "r", "sp", "d", "rem", "sts", "cl", "cd", "cp",
        "imt", "is", "ip", "ipi", "im", "imi", "ipq", "imq", "ipr", "iq", "ili", "iot", "io", "iex", "imte", "ie",
        "periph", "restore", "lit", "qa", "esb", "esbe", "ts", "sd", "cat",
    ]
    private static let characterStyles: Set<String> = [
        "w", "wg", "wh", "wa", "nd", "add", "wj", "tl", "bk", "k", "qt", "sc", "pn", "png", "addpn", "ord", "dc",
        "sls", "em", "bd", "it", "bdit", "no", "sig", "qs", "qac", "litl", "lik", "jmp", "rb", "rt", "pro", "ndx",
        "ior", "iqt", "fv", "fk", "fl", "fw", "fm", "xt", "xo", "xk", "xq", "xta", "ft", "fr", "fq", "fqa",
    ]
    private static let attributeStyles: Set<String> = ["w", "wg", "wh", "wa", "rb", "jmp"]

    private enum Pending { case none, bookCode, chapter, verse }

    public static func importBook(_ text: String) -> USFMImportResult {
        var report = USFMImportReport()
        var chapters: [Int: [Int: String]] = [:]
        var book: BookID?
        var idSeen = false
        var currentChapter: Int?
        var currentVerse: Int?
        var buffer = ""
        var inVerseText = false
        var pending = Pending.none
        var token = ""
        var noteSkip: String?
        var milestoneSkip = false
        var openStyles: [String] = []
        var attributeSkip = false
        var warnedNoChapter = false

        func finishVerse() {
            guard let chapter = currentChapter, let verse = currentVerse else { buffer = ""; return }
            let collapsed = buffer.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            buffer = ""
            guard !collapsed.isEmpty else { return }
            if chapters[chapter]?[verse] != nil {
                report.duplicateVerses.append("\(chapter):\(verse)")
                return
            }
            chapters[chapter, default: [:]][verse] = collapsed
        }

        func finishToken() {
            switch pending {
            case .bookCode:
                let code = token.uppercased()
                if Canon.book(BookID(code)) != nil { book = BookID(code) }
                else { report.warnings.append("The book code “\(token)” is not one of the 66 books.") }
            case .chapter:
                finishVerse()
                currentVerse = nil
                if let n = Int(token.prefix(while: { $0.isNumber })), n >= 1 { currentChapter = n }
                else { currentChapter = nil; report.warnings.append("Could not read the chapter number “\(token)”.") }
            case .verse:
                finishVerse()
                let digits = token.prefix(while: { $0.isASCII && $0.isNumber })
                if let n = Int(digits), n >= 1 {
                    if currentChapter == nil {
                        currentChapter = 1
                        if !warnedNoChapter { report.warnings.append("A verse came before any \\c chapter marker; chapter 1 was assumed."); warnedNoChapter = true }
                    }
                    currentVerse = n
                    let rest = token.dropFirst(digits.count)
                    if rest.first == "-" || rest.first == "\u{2013}" {
                        let end = rest.dropFirst().prefix(while: { $0.isASCII && $0.isNumber })
                        if !end.isEmpty { report.bridgedVerses.append("\(currentChapter ?? 1):\(n)-\(end)") }
                    }
                    inVerseText = true
                } else {
                    currentVerse = nil
                    report.warnings.append("Could not read the verse number “\(token)”; its text was skipped.")
                }
            case .none: break
            }
            pending = .none
            token = ""
        }

        let chars = Array(text)
        var i = 0
        var stopped = false
        while i < chars.count, !stopped {
            let ch = chars[i]
            if ch == "\\" {
                var j = i + 1
                if j < chars.count, chars[j] == "*" { milestoneSkip = false; i = j + 1; continue }
                var name = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "+" || chars[j] == "-" {
                    name.append(chars[j]); j += 1
                }
                var closing = false
                if j < chars.count, chars[j] == "*" { closing = true; j += 1 }
                if !closing, j < chars.count, chars[j] == " " || chars[j] == "\n" || chars[j] == "\r" || chars[j] == "\t" { j += 1 }
                i = j
                if pending != .none { finishToken() }

                let plain = name.hasPrefix("+") ? String(name.dropFirst()) : name
                let base = String(plain.reversed().drop(while: { $0.isNumber }).reversed())
                let style = base.isEmpty ? plain : base

                if let open = noteSkip {
                    if closing, style == open { noteSkip = nil; continue }
                    if !closing, ["v", "c", "id"].contains(style) {
                        report.warnings.append("A footnote or cross-reference (\\\(open)) was not closed; it ended at \\\(style).")
                        noteSkip = nil
                    } else { continue }
                }

                if closing {
                    if let last = openStyles.lastIndex(of: style) { openStyles.remove(at: last) }
                    if attributeStyles.contains(style) { attributeSkip = false }
                    continue
                }

                switch style {
                case "id":
                    if idSeen {
                        report.warnings.append("A second \\id line (\(chars[i...].prefix(while: { !$0.isWhitespace }).map(String.init).joined())) was found; reading stopped before it.")
                        stopped = true
                    } else {
                        idSeen = true
                        pending = .bookCode
                        inVerseText = false
                    }
                case "c":
                    pending = .chapter
                    inVerseText = false
                case "v":
                    pending = .verse
                case _ where noteMarkers.contains(style):
                    report.notesStripped += 1
                    noteSkip = style
                case _ where stripWithContent.contains(style):
                    noteSkip = style
                case _ where paragraphMarkers.contains(style):
                    inVerseText = currentVerse != nil
                    if inVerseText { buffer.append(" ") }
                case _ where ignoredLineMarkers.contains(style):
                    report.ignoredMarkers[plain, default: 0] += 1
                    inVerseText = false
                case _ where characterStyles.contains(style):
                    openStyles.append(style)
                case _ where style.hasSuffix("-s") || style.hasSuffix("-e"):
                    milestoneSkip = true
                default:
                    report.unknownMarkers[plain, default: 0] += 1
                }
                continue
            }

            i += 1
            if pending != .none {
                if ch.isWhitespace {
                    if !token.isEmpty { finishToken() }
                } else { token.append(ch) }
                continue
            }
            if noteSkip != nil || milestoneSkip || !inVerseText { continue }
            if ch == "|", openStyles.contains(where: { attributeStyles.contains($0) }) { attributeSkip = true; continue }
            if attributeSkip { continue }
            buffer.append(ch == "~" ? " " : ch)
        }
        if pending != .none { finishToken() }
        finishVerse()

        if !idSeen { report.warnings.insert("The text has no \\id line, so the book is unknown.", at: 0) }
        report.chapterCount = chapters.count
        report.verseCount = chapters.values.reduce(0) { $0 + $1.count }
        if report.verseCount == 0 { report.warnings.append("No verses were found.") }
        return USFMImportResult(book: book, chapters: chapters, report: report)
    }
}
