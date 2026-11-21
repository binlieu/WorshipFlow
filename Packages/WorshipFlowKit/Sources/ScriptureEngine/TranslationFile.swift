// LIB-004: the translation file format. One JSON file per translation, versioned.
//
//   {
//     "format": "worshipflow.translation",
//     "version": 1,
//     "metadata": {
//       "id": "kjv", "name": "King James Version", "language": "en", "abbreviation": "KJV",
//       "copyright": "...", "license": "...", "sourceURL": "https://...",
//       "isPublicDomain": true, "versificationNote": "...", "versification": "KJV",
//       "ownerApproval": {"approved": true, "date": "2026-11-20", "note": "..."}
//     },
//     "books": { "JHN": { "3": { "16": "verse text", "17": "..." } } }
//   }
//
// Book keys are USFM codes (GEN ... REV). Chapter and verse keys are decimal strings. Required metadata:
// id, name, language (a BCP 47 tag such as "en" or "vi"), abbreviation. Everything else is optional.
// `versification` names the table the verse numbers follow ("KJV" when absent, or "VI1925"). LIB-004b: a file that
// follows neither may carry its own table in `metadata.versificationTable` (book code -> one [count, highest] pair per
// chapter, [0, 0] for a chapter the table lacks); `versification` is then only its label.
// A partial translation (a New Testament only, say) is allowed. No Bible text is ever stored in this repository
// except tiny test fixtures; files are supplied by the owner (see docs/features/LIB-004-scripture-engine.md).
import Foundation

/// The owner's decision to use a translation, with the date and a note. Not legal advice; a record.
public struct OwnerApproval: Codable, Equatable, Sendable {
    public var approved: Bool
    /// ISO 8601 date, for example "2026-11-20".
    public var date: String?
    public var note: String?

    public init(approved: Bool, date: String? = nil, note: String? = nil) {
        self.approved = approved
        self.date = date
        self.note = note
    }
}

public struct TranslationMetadata: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// BCP 47 language tag, "en" or "vi".
    public var language: String
    public var abbreviation: String
    public var copyright: String?
    public var license: String?
    public var sourceURL: String?
    public var isPublicDomain: Bool
    public var versificationNote: String?
    /// Name of the verse-count table the text follows: "KJV" (default) or "VI1925".
    public var versification: String?
    public var ownerApproval: OwnerApproval?
    /// Optional own verse-count table (LIB-004b) for a translation that follows neither built-in table: book code ->
    /// one `[count, highest]` pair per chapter. `count` is the number of verses the chapter has, `highest` its last
    /// verse number (larger when numbers are skipped); `[0, 0]` marks a chapter the table does not have. When present
    /// it is used instead of the table `versification` names, which then only labels it.
    public var versificationTable: [String: [[Int]]]?

    public init(id: String, name: String, language: String, abbreviation: String,
                copyright: String? = nil, license: String? = nil, sourceURL: String? = nil,
                isPublicDomain: Bool = false, versificationNote: String? = nil,
                versification: String? = nil, ownerApproval: OwnerApproval? = nil,
                versificationTable: [String: [[Int]]]? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.abbreviation = abbreviation
        self.copyright = copyright
        self.license = license
        self.sourceURL = sourceURL
        self.isPublicDomain = isPublicDomain
        self.versificationNote = versificationNote
        self.versification = versification
        self.ownerApproval = ownerApproval
        self.versificationTable = versificationTable
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, language, abbreviation, copyright, license, sourceURL
        case isPublicDomain, versificationNote, versification, ownerApproval, versificationTable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  language: try c.decode(String.self, forKey: .language),
                  abbreviation: try c.decode(String.self, forKey: .abbreviation),
                  copyright: try c.decodeIfPresent(String.self, forKey: .copyright),
                  license: try c.decodeIfPresent(String.self, forKey: .license),
                  sourceURL: try c.decodeIfPresent(String.self, forKey: .sourceURL),
                  isPublicDomain: try c.decodeIfPresent(Bool.self, forKey: .isPublicDomain) ?? false,
                  versificationNote: try c.decodeIfPresent(String.self, forKey: .versificationNote),
                  versification: try c.decodeIfPresent(String.self, forKey: .versification),
                  ownerApproval: try c.decodeIfPresent(OwnerApproval.self, forKey: .ownerApproval),
                  versificationTable: try c.decodeIfPresent([String: [[Int]]].self, forKey: .versificationTable))
    }
}

public enum TranslationLoadError: Error, Equatable, Sendable {
    case notJSON(String)
    case wrongFormat(String?)
    case missingVersion
    case unsupportedVersion(Int)
    case invalid(String)
    case importFailed(String)

    /// Operator-readable text.
    public var message: String {
        switch self {
        case .notJSON(let detail): return "The file is not valid JSON (\(detail))."
        case .wrongFormat(let found):
            return "This is not a WorshipFlow translation file: the \"format\" field must be \"worshipflow.translation\"" + (found.map { " but is \"\($0)\"." } ?? " but is missing.")
        case .missingVersion: return "The translation file has no \"version\" field."
        case .unsupportedVersion(let v): return "This translation file is version \(v); this build reads version \(TranslationFile.currentVersion). Update the app or re-export the file."
        case .invalid(let detail): return "The translation file is damaged: \(detail)"
        case .importFailed(let detail): return detail
        }
    }
}

/// The stored form. Use `TranslationLoader` to turn it into a checked `Translation`.
public struct TranslationFile: Codable, Equatable, Sendable {
    public static let formatName = "worshipflow.translation"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var metadata: TranslationMetadata
    /// book code -> chapter -> verse -> text, all keys decimal strings.
    public var books: [String: [String: [String: String]]]

    public init(metadata: TranslationMetadata, books: [String: [String: [String: String]]]) {
        self.format = Self.formatName
        self.version = Self.currentVersion
        self.metadata = metadata
        self.books = books
    }

    public mutating func setVerse(_ text: String, book: BookID, chapter: Int, verse: Int) {
        books[book.rawValue, default: [:]][String(chapter), default: [:]][String(verse)] = text
    }

    public mutating func setBook(_ book: BookID, chapters: [Int: [Int: String]]) {
        var out: [String: [String: String]] = [:]
        for (chapter, verses) in chapters {
            out[String(chapter)] = Dictionary(uniqueKeysWithValues: verses.map { (String($0.key), $0.value) })
        }
        books[book.rawValue] = out
    }

    /// Adds a book read by `USFMImporter`. Throws when the USFM had no usable `\id` line.
    public mutating func add(_ result: USFMImportResult) throws {
        guard let book = result.book else {
            throw TranslationLoadError.importFailed("The USFM text has no recognised book (\\id) line, so it cannot be added. " + result.report.warnings.joined(separator: " "))
        }
        setBook(book, chapters: result.chapters)
    }

    /// Stable, human-diffable JSON (sorted keys, indented).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
