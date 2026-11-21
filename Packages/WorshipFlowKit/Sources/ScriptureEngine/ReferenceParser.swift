// LIB-004: reference text -> verse ranges, with operator-readable problems. Never throws, never corrects silently.
import Foundation

public struct ReferenceProblem: Error, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case empty, missingBook, unknownBook, ambiguousBook, missingLocation
        case chapterOutOfRange, verseOutOfRange, backwards, syntax
    }
    public var kind: Kind
    /// Plain-language text for the operator, for example "John 3 has 36 verses".
    public var message: String
    /// The piece of the input the problem is about.
    public var input: String
    /// For an ambiguous book name: the books it could mean, in canon order.
    public var candidates: [BookID]

    public init(kind: Kind, message: String, input: String, candidates: [BookID] = []) {
        self.kind = kind
        self.message = message
        self.input = input
        self.candidates = candidates
    }
}

public struct ParseOutcome: Equatable, Sendable {
    /// The ranges that were valid. Adjacent or overlapping neighbours in the same book are merged; order is kept.
    public var ranges: [VerseRange]
    public var problems: [ReferenceProblem]
    public var isValid: Bool { problems.isEmpty && !ranges.isEmpty }

    /// LIB-004c: public so a passage that is read from ranges (a stored playlist item) can be described like a typed one.
    public init(ranges: [VerseRange], problems: [ReferenceProblem] = []) {
        self.ranges = ranges
        self.problems = problems
    }
}

public struct ReferenceParser: Sendable {
    /// Language of the book names in messages.
    public var language: ScriptureLanguage
    /// Table that decides which chapters and verses exist.
    public var versification: Versification
    /// How typed book names are read.
    public var context: MatchContext

    public init(language: ScriptureLanguage = .english, versification: Versification = .kjv, context: MatchContext = .auto) {
        self.language = language
        self.versification = versification
        self.context = context
    }

    public func parse(_ text: String) -> ParseOutcome {
        var ranges: [VerseRange] = []
        var problems: [ReferenceProblem] = []
        var previousBook: BookID?
        var sawChunk = false

        for rawChunk in text.split(whereSeparator: { $0 == ";" || $0.isNewline }) {
            let chunk = Self.trim(String(rawChunk))
            if chunk.isEmpty { continue }
            sawChunk = true
            switch parseChunk(chunk, previousBook: previousBook) {
            case .success(let (book, parsed)):
                previousBook = book
                ranges.append(contentsOf: parsed)
            case .failure(let problem):
                problems.append(problem)
            }
        }
        if !sawChunk {
            problems.append(ReferenceProblem(kind: .empty, message: "Type a reference such as John 3:16.", input: text))
        }
        return ParseOutcome(ranges: merge(ranges), problems: problems)
    }

    // MARK: Chunk

    private func parseChunk(_ chunk: String, previousBook: BookID?) -> Result<(BookID, [VerseRange]), ReferenceProblem> {
        let chars = Array(chunk)
        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

        var bookEnd = 0
        var hasBook = true
        if let first = chars.first, isDigit(first) {
            var j = 0
            while j < chars.count, isDigit(chars[j]) { j += 1 }
            var k = j
            while k < chars.count, chars[k] == " " || chars[k] == "." { k += 1 }
            if k < chars.count, chars[k].isLetter { bookEnd = j } else { hasBook = false }
        }
        guard hasBook else {
            guard let previousBook else {
                return .failure(ReferenceProblem(kind: .missingBook, message: "“\(chunk)” has no book name. Start with a book, for example John \(chunk).", input: chunk))
            }
            return evaluate(book: previousBook, locator: chunk, input: chunk)
        }
        var k = bookEnd
        while k < chars.count, !isDigit(chars[k]) { k += 1 }
        let bookText = String(chars[0..<k]).trimmingCharacters(in: .whitespaces)
        let locator = String(chars[k...]).trimmingCharacters(in: .whitespaces)

        switch BookMatcher.match(bookText, context: context) {
        case .unknown:
            return .failure(ReferenceProblem(kind: .unknownBook, message: "“\(Self.cleanName(bookText))” is not a book name I know.", input: chunk))
        case .ambiguous(let books):
            let names = books.map { BookNames.displayName($0, language) ?? $0.rawValue }
            let list = names.count == 2 ? "\(names[0]) or \(names[1])" : names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
            return .failure(ReferenceProblem(kind: .ambiguousBook, message: "“\(Self.cleanName(bookText))” could be \(list). Type more of the name.", input: chunk, candidates: books))
        case .book(let book):
            return evaluate(book: book, locator: locator, input: chunk)
        }
    }

    // MARK: Locator

    private enum Token: Equatable { case number(Int), colon, dash, comma }

    private func tokenize(_ locator: String) -> Result<[Token], ReferenceProblem> {
        let chars = Array(locator)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isASCII && c.isNumber {
                var j = i
                while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
                guard let value = Int(String(chars[i..<j])), value < 1_000_000 else {
                    return .failure(ReferenceProblem(kind: .syntax, message: "The number \(String(chars[i..<j])) is too large.", input: locator))
                }
                tokens.append(.number(value))
                i = j
                continue
            }
            switch c {
            case ":": tokens.append(.colon)
            case ".":
                if case .number? = tokens.last, i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isNumber {
                    tokens.append(.colon)
                } else {
                    return .failure(syntax(locator, "Unexpected “.” in “\(locator)”."))
                }
            case "-", "\u{2013}", "\u{2014}", "\u{2011}", "\u{2212}": tokens.append(.dash)
            case ",": tokens.append(.comma)
            case " ", "\t", "\u{00A0}": break
            default: return .failure(syntax(locator, "Unexpected “\(c)” in “\(locator)”. Use a form like 3:16-18."))
            }
            i += 1
        }
        return .success(tokens)
    }

    private func syntax(_ input: String, _ message: String) -> ReferenceProblem {
        ReferenceProblem(kind: .syntax, message: message, input: input)
    }

    private func evaluate(book: BookID, locator: String, input: String) -> Result<(BookID, [VerseRange]), ReferenceProblem> {
        let name = BookNames.displayName(book, language) ?? book.rawValue
        let chapterCount = versification.chapterCount(book: book) ?? 0
        if locator.isEmpty {
            let what = chapterCount == 1 ? "which verse (it has \(versification.highestVerse(book: book, chapter: 1) ?? 0) verses)" : "which chapter (it has \(chapterCount) chapters)"
            return .failure(ReferenceProblem(kind: .missingLocation, message: "\(name) needs \(what). For example \(name) \(chapterCount == 1 ? "1" : "3").", input: input))
        }
        let tokens: [Token]
        switch tokenize(locator) {
        case .success(let t): tokens = t
        case .failure(let p): return .failure(ReferenceProblem(kind: p.kind, message: p.message, input: input))
        }
        func bad(_ message: String) -> Result<(BookID, [VerseRange]), ReferenceProblem> {
            .failure(syntax(input, message))
        }

        var pos = 0
        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        func number() -> Int? {
            if case .number(let n)? = peek() { pos += 1; return n }
            return nil
        }
        func take(_ t: Token) -> Bool {
            if peek() == t { pos += 1; return true }
            return false
        }

        // Each item: (startChapter, startVerse or nil for a whole chapter, endChapter, endVerse or nil).
        var items: [(Int, Int?, Int, Int?)] = []
        var chapterContext: Int? = chapterCount == 1 ? 1 : nil

        repeat {
            guard let n1 = number() else { return bad("Expected a number in “\(input)”.") }
            if take(.colon) {
                guard let v1 = number() else { return bad("Expected a verse number after “\(n1):” in “\(input)”.") }
                var endChapter = n1, endVerse = v1
                if take(.dash) {
                    guard let n2 = number() else { return bad("The range in “\(input)” is incomplete.") }
                    if take(.colon) {
                        guard let v2 = number() else { return bad("Expected a verse number after “\(n2):” in “\(input)”.") }
                        endChapter = n2; endVerse = v2
                    } else {
                        endVerse = n2
                    }
                }
                chapterContext = n1
                items.append((n1, v1, endChapter, endVerse))
            } else if let chapter = chapterContext {
                var endChapter = chapter, endVerse = n1
                if take(.dash) {
                    guard let n2 = number() else { return bad("The range in “\(input)” is incomplete.") }
                    if take(.colon) {
                        guard let v2 = number() else { return bad("Expected a verse number after “\(n2):” in “\(input)”.") }
                        endChapter = n2; endVerse = v2
                    } else {
                        endVerse = n2
                    }
                }
                items.append((chapter, n1, endChapter, endVerse))
            } else {
                var endChapter = n1
                if take(.dash) {
                    guard let n2 = number() else { return bad("The range in “\(input)” is incomplete.") }
                    endChapter = n2
                }
                items.append((n1, nil, endChapter, nil))
            }
        } while take(.comma)
        if pos < tokens.count { return bad("Could not read “\(input)”. Use a form like 3:16-18.") }

        var ranges: [VerseRange] = []
        for (c1, v1, c2, v2) in items {
            for chapter in [c1, c2] {
                if chapter < 1 {
                    return .failure(ReferenceProblem(kind: .chapterOutOfRange, message: "Chapter numbers start at 1 (“\(input)”).", input: input))
                }
                if chapter > chapterCount {
                    return .failure(ReferenceProblem(kind: .chapterOutOfRange,
                                                     message: "\(name) has \(chapterCount) chapter\(chapterCount == 1 ? "" : "s").", input: input))
                }
            }
            if c2 < c1 {
                return .failure(ReferenceProblem(kind: .backwards, message: "“\(input)” runs backwards: chapter \(c2) comes before chapter \(c1).", input: input))
            }
            let highestEnd = versification.highestVerse(book: book, chapter: c2) ?? 0
            let startVerse = v1 ?? 1
            let endVerse = v2 ?? highestEnd
            for (chapter, verse) in [(c1, startVerse), (c2, endVerse)] {
                if verse < 1 {
                    return .failure(ReferenceProblem(kind: .verseOutOfRange, message: "Verse numbers start at 1 (“\(input)”).", input: input))
                }
                let highest = versification.highestVerse(book: book, chapter: chapter) ?? 0
                if verse > highest {
                    let who = chapterCount == 1 ? name : "\(name) \(chapter)"
                    return .failure(ReferenceProblem(kind: .verseOutOfRange, message: "\(who) has \(highest) verse\(highest == 1 ? "" : "s").", input: input))
                }
            }
            if c1 == c2, endVerse < startVerse {
                return .failure(ReferenceProblem(kind: .backwards, message: "“\(input)” runs backwards: verse \(endVerse) comes before verse \(startVerse).", input: input))
            }
            ranges.append(VerseRange(book: book, startChapter: c1, startVerse: startVerse, endChapter: c2, endVerse: endVerse))
        }
        return .success((book, ranges))
    }

    // MARK: Merging

    private func merge(_ ranges: [VerseRange]) -> [VerseRange] {
        var out: [VerseRange] = []
        for range in ranges {
            if let last = out.last, last.book == range.book, range.start >= last.start, touches(last.end, range.start) {
                out[out.count - 1].end = max(last.end, range.end)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// True when `next` is inside or directly after the verse `end`.
    private func touches(_ end: VerseRef, _ next: VerseRef) -> Bool {
        if next <= end { return true }
        if next.chapter == end.chapter { return next.verse == end.verse + 1 }
        return next.chapter == end.chapter + 1 && next.verse == 1
            && end.verse == versification.highestVerse(book: end.book, chapter: end.chapter)
    }

    // MARK: Text helpers

    private static func trim(_ s: String) -> String {
        var chars = Array(s)
        while let f = chars.first, !(f.isLetter || f.isNumber) { chars.removeFirst() }
        let trailing: Set<Character> = [".", ",", ";", ")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}", " ", "\t", "\u{00A0}"]
        while let l = chars.last, trailing.contains(l) || l.isWhitespace { chars.removeLast() }
        return String(chars)
    }

    private static func cleanName(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: ". ,-"))
    }
}
