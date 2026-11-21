// LIB-004b: the façade the app uses to turn a typed reference into slides, from translations kept in the library.
import Foundation
import Domain
import ScriptureEngine

/// What `ScriptureLibrary.lookup` found.
public struct ScriptureLookup: Sendable {
    /// The parsed reference: ranges, and a problem for each part that could not be read.
    public var outcome: ParseOutcome
    /// Slides for the ranges that were read. Nil when none was. Its `report` lists verses the primary translation lacks
    /// (skipped) and verses the second lacks (that side of the slide is empty).
    public var presentation: ScripturePresentation?
    /// Plain-language notes about pairing: chapters the two translations number differently.
    public var notes: [String]
    public var primary: StoredTranslation
    public var secondary: StoredTranslation?
}

public struct ScriptureLibrary: Sendable {
    public let store: ScriptureStore

    public init(store: ScriptureStore) { self.store = store }

    public func translations() async throws -> [StoredTranslation] { try await store.translations() }

    /// Reads `text` as a reference (for example "John 3:16-18; Ps 23"), reads the verses from the primary translation and
    /// the optional second one, and builds slides with `VerseSlides`.
    ///
    /// - Parameters:
    ///   - uiLanguage: the language of the interface; names in messages and the way abbreviations are read follow it.
    ///     Defaults to the primary translation's language for messages and to `.auto` for reading names.
    ///   - context: overrides how typed book names are read.
    /// - Throws: `ScriptureStoreError.notFound` when a translation code is not in the library.
    public func lookup(_ text: String, primary primaryCode: String, secondary secondaryCode: String? = nil,
                       uiLanguage: ScriptureLanguage? = nil, context: MatchContext? = nil,
                       options: SlideOptions = SlideOptions()) async throws -> ScriptureLookup {
        let primary = try await store.translation(code: primaryCode)
        let primaryTable = try await store.versification(for: primaryCode)
        var second: StoredTranslation?
        var secondTable: Versification?
        if let secondaryCode {
            second = try await store.translation(code: secondaryCode)
            secondTable = try await store.versification(for: secondaryCode)
        }

        let readingContext: MatchContext = context ?? uiLanguage.map { $0 == .vietnamese ? .vietnamese : .english } ?? .auto
        let parser = ReferenceParser(language: uiLanguage ?? ScriptureLanguage(languageTag: primary.language),
                                     versification: primaryTable, context: readingContext)
        let outcome = parser.parse(text)
        guard !outcome.ranges.isEmpty else {
            return ScriptureLookup(outcome: outcome, presentation: nil, notes: [], primary: primary, secondary: second)
        }
        return try await build(outcome: outcome, primary: primary, primaryTable: primaryTable, secondary: second,
                               secondaryTable: secondTable, uiLanguage: uiLanguage, options: options)
    }

    /// LIB-004c: slides for ranges that are already known (a stored playlist item), by the same road as a typed reference.
    /// - Throws: `ScriptureStoreError.notFound` when a translation code is not in the library.
    public func lookup(ranges: [VerseRange], primary primaryCode: String, secondary secondaryCode: String? = nil,
                       uiLanguage: ScriptureLanguage? = nil, options: SlideOptions = SlideOptions()) async throws -> ScriptureLookup {
        let primary = try await store.translation(code: primaryCode)
        let primaryTable = try await store.versification(for: primaryCode)
        var second: StoredTranslation?
        var secondTable: Versification?
        if let secondaryCode {
            second = try await store.translation(code: secondaryCode)
            secondTable = try await store.versification(for: secondaryCode)
        }
        return try await build(outcome: ParseOutcome(ranges: ranges), primary: primary, primaryTable: primaryTable,
                               secondary: second, secondaryTable: secondTable, uiLanguage: uiLanguage, options: options)
    }

    private func build(outcome: ParseOutcome, primary: StoredTranslation, primaryTable: Versification, secondary second: StoredTranslation?,
                       secondaryTable secondTable: Versification?, uiLanguage: ScriptureLanguage?, options: SlideOptions) async throws -> ScriptureLookup {
        // Only the verses of the ranges are read, so a one-verse lookup never loads a whole Bible.
        let primaryVerses = try await store.verses(in: outcome.ranges, translationCode: primary.code)
        let primaryTranslation = Translation(metadata: primary.metadata, versification: primaryTable,
                                             verses: primaryVerses.map { (ref: $0.ref, text: $0.text) })
        var secondTranslation: Translation?
        if let second, let secondTable {
            let rows = try await store.verses(in: outcome.ranges, translationCode: second.code)
            secondTranslation = Translation(metadata: second.metadata, versification: secondTable, verses: rows.map { (ref: $0.ref, text: $0.text) })
        }
        let presentation = VerseSlides.build(ranges: outcome.ranges, primary: primaryTranslation, secondary: secondTranslation, options: options)

        var notes: [String] = []
        if let second, let secondTable, primaryTable != secondTable {
            notes = Self.numberingNotes(ranges: outcome.ranges, primary: primary, primaryTable: primaryTable,
                                        second: second, secondTable: secondTable,
                                        language: uiLanguage ?? ScriptureLanguage(languageTag: primary.language))
        }
        return ScriptureLookup(outcome: outcome, presentation: presentation, notes: notes, primary: primary, secondary: second)
    }

    /// One note per chapter inside the ranges where the two tables disagree. Pairing is by verse number, so the verses
    /// shown together in such a chapter may not be the same verse.
    static func numberingNotes(ranges: [VerseRange], primary: StoredTranslation, primaryTable: Versification,
                               second: StoredTranslation, secondTable: Versification, language: ScriptureLanguage) -> [String] {
        var wanted: [BookID: Set<Int>] = [:]
        for range in ranges {
            for ref in range.verses(in: primaryTable) { wanted[ref.book, default: []].insert(ref.chapter) }
        }
        var notes: [String] = []
        for difference in Versification.differences(primaryTable, secondTable) where wanted[difference.book]?.contains(difference.chapter) == true {
            let book = BookNames.displayName(difference.book, language) ?? difference.book.rawValue
            notes.append("\(book) \(difference.chapter) is numbered differently: \(primaryTable.id) has \(difference.a.count) verses and \(secondTable.id) has \(difference.b.count). Verses are paired by number, so some pairs may not be the same verse.")
        }
        return notes
    }
}
