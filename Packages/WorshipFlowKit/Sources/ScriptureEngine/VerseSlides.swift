// LIB-004: verses -> slides.
//
// Rules:
//  - Verses are listed from the ranges in the order given, using the primary translation's verse-count table.
//    A verse the primary translation lacks is skipped and reported.
//  - One verse per slide by default; up to `versesPerSlide` verses may share a slide while the text stays within
//    `maxCharacters` (when set). A verse longer than the limit is split at sentence, then clause, then word
//    boundaries into parts shown as "John 3:16a", "John 3:16b".
//  - The second translation is paired by book, chapter and verse number. A verse it lacks leaves that side of
//    the slide empty and is reported. When a verse is split, both sides are split into the same number of parts,
//    decided by whichever side needs more.
import Foundation
import Domain

public enum VerseNumberStyle: Sendable, Equatable {
    case none
    /// "16 For God so loved ..."
    case plain
    /// "¹⁶ For God so loved ..."
    case superscript
}

public struct SlideOptions: Sendable, Equatable {
    /// Values below 1 act as 1.
    public var versesPerSlide: Int
    /// Longest text on one slide, counted in characters of either side. Nil or 0 means no limit.
    public var maxCharacters: Int?
    public var verseNumbers: VerseNumberStyle
    /// Put between verses that share a slide.
    public var verseSeparator: String

    public init(versesPerSlide: Int = 1, maxCharacters: Int? = nil, verseNumbers: VerseNumberStyle = .none, verseSeparator: String = " ") {
        self.versesPerSlide = versesPerSlide
        self.maxCharacters = maxCharacters
        self.verseNumbers = verseNumbers
        self.verseSeparator = verseSeparator
    }
}

public struct ScriptureSlide: Sendable, Equatable {
    public var content: SlideContent
    /// Reference text in the primary translation's language, for example "John 3:16" or "John 3:16a".
    public var reference: String
    /// Reference in the second translation's language ("Giăng 3:16"); nil when that side is empty.
    public var secondaryReference: String?
    public var verses: [VerseRef]
    /// For a slide that shows part of a verse: 0 for "a", and how many parts the verse has.
    public var partIndex: Int?
    public var partCount: Int?

    /// LIB-004c: public so the app's model and its tests can make a slide without building a whole passage.
    public init(content: SlideContent, reference: String, secondaryReference: String?, verses: [VerseRef],
                partIndex: Int?, partCount: Int?) {
        self.content = content
        self.reference = reference
        self.secondaryReference = secondaryReference
        self.verses = verses
        self.partIndex = partIndex
        self.partCount = partCount
    }
}

public struct SlideBuildReport: Sendable, Equatable {
    public var missingInPrimary: [VerseRef] = []
    public var missingInSecondary: [VerseRef] = []
    public var messages: [String] = []
}

public struct ScripturePresentation: Sendable, Equatable {
    public var title: String
    public var slides: [ScriptureSlide]
    public var report: SlideBuildReport
}

public enum VerseSlides {
    public static func build(ranges: [VerseRange], primary: Translation, secondary: Translation? = nil,
                             options: SlideOptions = SlideOptions()) -> ScripturePresentation {
        var report = SlideBuildReport()
        let limit = (options.maxCharacters ?? 0) > 0 ? (options.maxCharacters ?? 0) : nil
        let perSlide = max(options.versesPerSlide, 1)

        // Verses with their rendered text on each side.
        var items: [Item] = []
        for range in ranges {
            for ref in range.verses(in: primary.versification) {
                guard let text = primary.text(for: ref) else { report.missingInPrimary.append(ref); continue }
                var second: String?
                if let secondary {
                    if let t = secondary.text(for: ref) { second = number(t, ref, options.verseNumbers) }
                    else { report.missingInSecondary.append(ref) }
                }
                items.append(Item(ref: ref, primary: number(text, ref, options.verseNumbers), secondary: second))
            }
        }

        // Group.
        var groups: [[Item]] = []
        for item in items {
            if var current = groups.last, current.count < perSlide, fits(current + [item], options.verseSeparator, limit) {
                current.append(item)
                groups[groups.count - 1] = current
            } else {
                groups.append([item])
            }
        }

        var slides: [ScriptureSlide] = []
        for group in groups {
            let refs = group.map(\.ref)
            let joinedPrimary = group.map(\.primary).joined(separator: options.verseSeparator)
            let secondTexts = group.compactMap(\.secondary)
            let joinedSecondary: String? = secondTexts.isEmpty ? nil : secondTexts.joined(separator: options.verseSeparator)

            if group.count == 1, let limit, needsSplit(joinedPrimary, joinedSecondary, limit) {
                let ref = refs[0]
                let k = max(TextSplitter.split(joinedPrimary, maxCharacters: limit).count,
                            joinedSecondary.map { TextSplitter.split($0, maxCharacters: limit).count } ?? 1)
                let primaryParts = parts(joinedPrimary, k, limit)
                let secondaryParts = joinedSecondary.map { parts($0, k, limit) }
                for index in 0..<k {
                    let range = VerseRange(ref)
                    slides.append(ScriptureSlide(
                        content: SlideContent(primary: primaryParts[index], secondary: secondaryParts.flatMap { $0[index].isEmpty ? nil : $0[index] }),
                        reference: ReferenceFormatter.format(range, language: primary.language, versification: primary.versification, part: index),
                        secondaryReference: secondary.flatMap { s in
                            (secondaryParts?[index].isEmpty ?? true) ? nil : ReferenceFormatter.format(range, language: s.language, versification: s.versification, part: index)
                        },
                        verses: refs, partIndex: index, partCount: k))
                }
            } else {
                slides.append(ScriptureSlide(
                    content: SlideContent(primary: joinedPrimary, secondary: joinedSecondary),
                    reference: format(refs, primary),
                    secondaryReference: secondary.flatMap { s in joinedSecondary == nil ? nil : format(refs, s) },
                    verses: refs, partIndex: nil, partCount: nil))
            }
        }

        // Report text.
        if !report.missingInPrimary.isEmpty {
            report.messages.append("\(primary.metadata.abbreviation) has no text for \(list(report.missingInPrimary, primary.versification, primary.language)); skipped.")
        }
        if let secondary, !report.missingInSecondary.isEmpty {
            report.messages.append("\(secondary.metadata.abbreviation) has no text for \(list(report.missingInSecondary, secondary.versification, primary.language)); that side of the slide is empty.")
        }

        let names = [primary.metadata.abbreviation] + (secondary.map { [$0.metadata.abbreviation] } ?? [])
        let reference = ReferenceFormatter.format(ranges, language: primary.language, versification: primary.versification)
        let title = reference.isEmpty ? "" : "\(reference) (\(names.joined(separator: " / ")))"
        return ScripturePresentation(title: title, slides: slides, report: report)
    }

    // MARK: Helpers

    private struct Item { var ref: VerseRef; var primary: String; var secondary: String? }

    /// True when the verses together stay within the limit on both sides.
    private static func fits(_ group: [Item], _ separator: String, _ limit: Int?) -> Bool {
        guard let limit else { return true }
        let p = group.map(\.primary).joined(separator: separator).count
        let s = group.compactMap(\.secondary).joined(separator: separator).count
        return max(p, s) <= limit
    }

    /// `k` parts: the natural split when it already has `k`, otherwise an even split into `k`.
    private static func parts(_ text: String, _ k: Int, _ limit: Int) -> [String] {
        let natural = TextSplitter.split(text, maxCharacters: limit)
        return natural.count == k ? natural : TextSplitter.split(text, into: k)
    }

    private static func number(_ text: String, _ ref: VerseRef, _ style: VerseNumberStyle) -> String {
        switch style {
        case .none: return text
        case .plain: return "\(ref.verse) \(text)"
        case .superscript: return superscript(ref.verse) + " " + text
        }
    }

    private static func superscript(_ n: Int) -> String {
        let digits: [Character: String] = ["0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}", "4": "\u{2074}",
                                           "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}", "8": "\u{2078}", "9": "\u{2079}"]
        return String(n).map { digits[$0] ?? String($0) }.joined()
    }

    private static func format(_ refs: [VerseRef], _ translation: Translation) -> String {
        ReferenceFormatter.format(mergeRuns(refs, translation.versification), language: translation.language, versification: translation.versification)
    }

    /// Consecutive verses become one range; gaps start a new one.
    private static func mergeRuns(_ refs: [VerseRef], _ versification: Versification) -> [VerseRange] {
        var out: [VerseRange] = []
        for ref in refs {
            if let last = out.last, last.book == ref.book, isNext(last.end, ref, versification) {
                out[out.count - 1].end = ref
            } else {
                out.append(VerseRange(ref))
            }
        }
        return out
    }

    private static func isNext(_ a: VerseRef, _ b: VerseRef, _ v: Versification) -> Bool {
        if a.chapter == b.chapter { return b.verse == a.verse + 1 }
        return b.chapter == a.chapter + 1 && b.verse == 1 && a.verse == v.highestVerse(book: a.book, chapter: a.chapter)
    }

    /// Operator-facing list of references, in the primary translation's language.
    private static func list(_ refs: [VerseRef], _ versification: Versification, _ language: ScriptureLanguage) -> String {
        ReferenceFormatter.format(mergeRuns(refs, versification), language: language, versification: versification)
    }

    private static func needsSplit(_ primary: String, _ secondary: String?, _ limit: Int) -> Bool {
        primary.count > limit || (secondary?.count ?? 0) > limit
    }
}
