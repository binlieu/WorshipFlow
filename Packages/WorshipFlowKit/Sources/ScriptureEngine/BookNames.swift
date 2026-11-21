// LIB-004: book names and abbreviations, English and Vietnamese, and the matcher that resolves typed text.
//
// Vietnamese names and the `viAbbreviation` column are the forms of the 1925 Vietnamese text, taken from the
// owner's database export (`AI/reports/bible-db-books.tsv`). Names marked "extra" below are variants seen in
// another edition of the 1925/1926 text or in common use; they are accepted when typing but never displayed.
import Foundation
import Domain

public enum ScriptureLanguage: String, Sendable, Codable, CaseIterable {
    case english, vietnamese

    /// "vi", "vi-VN" -> Vietnamese; everything else English.
    public init(languageTag: String) {
        self = languageTag.lowercased().hasPrefix("vi") ? .vietnamese : .english
    }
}

public enum BookMatch: Equatable, Sendable {
    case book(BookID)
    /// More than one book fits. Candidates are in canon order. The matcher never guesses.
    case ambiguous([BookID])
    case unknown
}

/// Which language a typed name is read in.
public enum MatchContext: Sendable {
    /// No preference. Text with Vietnamese diacritics is read as Vietnamese. When an English and a Vietnamese
    /// reading name different books the result is ambiguous.
    case auto
    /// English names first; Vietnamese only when English finds nothing.
    case english
    /// Vietnamese names and abbreviations first; English only when Vietnamese finds nothing.
    case vietnamese
}

public enum BookNames {
    struct Entry {
        var english: [String]           // first is the display name
        var englishAbbreviations: [String]
        var vietnamese: [String]        // first is the display name (1925 text)
        var viAbbreviation: String      // the owner's abbreviation
        var viExtra: [String] = []
    }

    public static func displayName(_ id: BookID, _ language: ScriptureLanguage) -> String? {
        guard let entry = table[id] else { return nil }
        switch language {
        case .english: return entry.english.first
        case .vietnamese: return entry.vietnamese.first
        }
    }

    /// The owner's short Vietnamese form of the 1925 text (for example `sa`, `thi`, `1co`).
    public static func vietnameseAbbreviation(_ id: BookID) -> String? { table[id]?.viAbbreviation }

    /// Exact keys that point at more than one book inside one language. Must be empty.
    static func conflictingAliases() -> [String] {
        var out: [String] = []
        for index in [index(for: .english), index(for: .vietnamese)] {
            for (key, books) in index.exact where books.count > 1 { out.append(key) }
        }
        return out.sorted()
    }

    // MARK: Matching index

    struct Index {
        var exact: [String: Set<BookID>] = [:]
        /// Exact keys that exist only as the owner's short abbreviation (not a name).
        var abbreviationOnly: Set<String> = []
        var prefixes: [(key: String, book: BookID)] = []
    }

    static func index(for language: ScriptureLanguage) -> Index {
        language == .english ? englishIndex : vietnameseIndex
    }

    static func key(_ text: String) -> String {
        let folded = SearchFolding.fold(text)
        var tokens = folded.split(separator: " ").map(String.init)
        if tokens.count > 1, let n = numerals[tokens[0]] { tokens[0] = n }
        return tokens.joined()
    }

    private static let numerals: [String: String] = [
        "1": "1", "i": "1", "1st": "1", "first": "1",
        "2": "2", "ii": "2", "2nd": "2", "second": "2",
        "3": "3", "iii": "3", "3rd": "3", "third": "3",
    ]

    private static let englishIndex: Index = {
        var index = Index()
        for (book, entry) in table {
            for name in entry.english + entry.englishAbbreviations {
                let k = key(name)
                index.exact[k, default: []].insert(book)
                index.prefixes.append((k, book))
            }
        }
        return index
    }()

    private static let vietnameseIndex: Index = {
        var index = Index()
        var nameKeys: Set<String> = []
        for (book, entry) in table {
            for name in entry.vietnamese + entry.viExtra {
                let k = key(name)
                nameKeys.insert(k)
                index.exact[k, default: []].insert(book)
                index.prefixes.append((k, book))
            }
        }
        for (book, entry) in table {
            let k = key(entry.viAbbreviation)
            index.exact[k, default: []].insert(book)
            if !nameKeys.contains(k) { index.abbreviationOnly.insert(k) }
        }
        return index
    }()

    /// Numbered books with the number removed, so "Cor" can report 1 and 2 Corinthians.
    static let unnumberedPrefixes: [(key: String, book: BookID)] = {
        var out: [(String, BookID)] = []
        for (book, entry) in table {
            for name in entry.english + entry.vietnamese + entry.viExtra {
                let k = key(name)
                if let first = k.first, first.isNumber { out.append((String(k.dropFirst()), book)) }
            }
        }
        return out
    }()

    // MARK: Table

    // swiftlint:disable line_length
    static let table: [BookID: Entry] = {
        var out: [BookID: Entry] = [:]
        for (code, entry) in rows { out[BookID(code)] = entry }
        return out
    }()

    private static let rows: [(String, Entry)] = [
        ("GEN", Entry(english: ["Genesis"], englishAbbreviations: ["Gen", "Gn", "Ge"], vietnamese: ["Sáng-thế Ký"], viAbbreviation: "sa")),
        ("EXO", Entry(english: ["Exodus"], englishAbbreviations: ["Ex", "Exo", "Exod"], vietnamese: ["Xuất Ê-díp-tô Ký"], viAbbreviation: "xu", viExtra: ["Xuất Ai-cập"])),
        ("LEV", Entry(english: ["Leviticus"], englishAbbreviations: ["Lev", "Le", "Lv"], vietnamese: ["Lê-vi Ký"], viAbbreviation: "le")),
        ("NUM", Entry(english: ["Numbers"], englishAbbreviations: ["Num", "Nu", "Nm", "Nb"], vietnamese: ["Dân-số Ký"], viAbbreviation: "dan")),
        ("DEU", Entry(english: ["Deuteronomy"], englishAbbreviations: ["Deut", "Dt", "De"], vietnamese: ["Phục-truyền Luật-lệ Ký"], viAbbreviation: "phu")),
        ("JOS", Entry(english: ["Joshua"], englishAbbreviations: ["Josh", "Jos", "Jsh"], vietnamese: ["Giô-suê"], viAbbreviation: "gios")),
        ("JDG", Entry(english: ["Judges"], englishAbbreviations: ["Judg", "Jdg", "Jg", "Jdgs"], vietnamese: ["Các Quan Xét"], viAbbreviation: "cac", viExtra: ["Quan Án"])),
        ("RUT", Entry(english: ["Ruth"], englishAbbreviations: ["Ru", "Rth"], vietnamese: ["Ru-tơ"], viAbbreviation: "ru")),
        ("1SA", Entry(english: ["1 Samuel"], englishAbbreviations: ["1 Sam", "1 Sm", "1 Sa", "1 S"], vietnamese: ["1 Sa-mu-ên"], viAbbreviation: "1sa")),
        ("2SA", Entry(english: ["2 Samuel"], englishAbbreviations: ["2 Sam", "2 Sm", "2 Sa", "2 S"], vietnamese: ["2 Sa-mu-ên"], viAbbreviation: "2sa")),
        ("1KI", Entry(english: ["1 Kings"], englishAbbreviations: ["1 Kgs", "1 Ki", "1 Kin", "1 K"], vietnamese: ["1 Các Vua"], viAbbreviation: "1vua")),
        ("2KI", Entry(english: ["2 Kings"], englishAbbreviations: ["2 Kgs", "2 Ki", "2 Kin", "2 K"], vietnamese: ["2 Các Vua"], viAbbreviation: "2vua")),
        ("1CH", Entry(english: ["1 Chronicles"], englishAbbreviations: ["1 Chron", "1 Chr", "1 Ch"], vietnamese: ["1 Sử-ký"], viAbbreviation: "1su", viExtra: ["1 Lịch Sử"])),
        ("2CH", Entry(english: ["2 Chronicles"], englishAbbreviations: ["2 Chron", "2 Chr", "2 Ch"], vietnamese: ["2 Sử-ký"], viAbbreviation: "2su", viExtra: ["2 Lịch Sử"])),
        ("EZR", Entry(english: ["Ezra"], englishAbbreviations: ["Ezr"], vietnamese: ["E-xơ-ra"], viAbbreviation: "exo", viExtra: ["Ê-xơ-ra"])),
        ("NEH", Entry(english: ["Nehemiah"], englishAbbreviations: ["Neh", "Ne"], vietnamese: ["Nê-hê-mi"], viAbbreviation: "ne")),
        ("EST", Entry(english: ["Esther"], englishAbbreviations: ["Est", "Esth"], vietnamese: ["Ê-xơ-tê"], viAbbreviation: "et")),
        ("JOB", Entry(english: ["Job"], englishAbbreviations: ["Jb"], vietnamese: ["Gióp"], viAbbreviation: "giop")),
        ("PSA", Entry(english: ["Psalms", "Psalm"], englishAbbreviations: ["Ps", "Psa", "Pss", "Pslm"], vietnamese: ["Thi-thiên"], viAbbreviation: "thi")),
        ("PRO", Entry(english: ["Proverbs"], englishAbbreviations: ["Prov", "Pro", "Prv", "Pr"], vietnamese: ["Châm-ngôn"], viAbbreviation: "ch")),
        ("ECC", Entry(english: ["Ecclesiastes"], englishAbbreviations: ["Eccles", "Eccl", "Ecc", "Ec", "Qoheleth"], vietnamese: ["Truyền-đạo"], viAbbreviation: "tr", viExtra: ["Giáo Huấn"])),
        ("SNG", Entry(english: ["Song of Solomon", "Song of Songs", "Canticles", "Canticle of Canticles"], englishAbbreviations: ["Song", "SOS", "Sg", "Cant"], vietnamese: ["Nhã-ca"], viAbbreviation: "nha", viExtra: ["Tình Ca"])),
        ("ISA", Entry(english: ["Isaiah"], englishAbbreviations: ["Isa", "Is"], vietnamese: ["Ê-sai"], viAbbreviation: "es")),
        ("JER", Entry(english: ["Jeremiah"], englishAbbreviations: ["Jer", "Je", "Jr"], vietnamese: ["Giê-rê-mi"], viAbbreviation: "gie")),
        ("LAM", Entry(english: ["Lamentations"], englishAbbreviations: ["Lam", "La"], vietnamese: ["Ca-thương"], viAbbreviation: "ca", viExtra: ["Ai Ca"])),
        ("EZK", Entry(english: ["Ezekiel"], englishAbbreviations: ["Ezek", "Eze", "Ezk"], vietnamese: ["Ê-xê-chi-ên"], viAbbreviation: "exe", viExtra: ["Ê-xê-chiên"])),
        ("DAN", Entry(english: ["Daniel"], englishAbbreviations: ["Dan", "Da", "Dn"], vietnamese: ["Đa-ni-ên"], viAbbreviation: "da", viExtra: ["Đa-niên"])),
        ("HOS", Entry(english: ["Hosea"], englishAbbreviations: ["Hos", "Ho"], vietnamese: ["Ô-sê"], viAbbreviation: "os")),
        ("JOL", Entry(english: ["Joel"], englishAbbreviations: ["Jl"], vietnamese: ["Giô-ên"], viAbbreviation: "gio")),
        ("AMO", Entry(english: ["Amos"], englishAbbreviations: ["Am"], vietnamese: ["A-mốt"], viAbbreviation: "am")),
        ("OBA", Entry(english: ["Obadiah"], englishAbbreviations: ["Obad", "Ob", "Oba"], vietnamese: ["Áp-đia"], viAbbreviation: "ap")),
        ("JON", Entry(english: ["Jonah"], englishAbbreviations: ["Jnh", "Jon"], vietnamese: ["Giô-na"], viAbbreviation: "gion")),
        ("MIC", Entry(english: ["Micah"], englishAbbreviations: ["Mic", "Mc"], vietnamese: ["Mi-chê"], viAbbreviation: "mi", viExtra: ["Mi-ca"])),
        ("NAM", Entry(english: ["Nahum"], englishAbbreviations: ["Nah", "Na"], vietnamese: ["Na-hum"], viAbbreviation: "na", viExtra: ["Na-hâm"])),
        ("HAB", Entry(english: ["Habakkuk"], englishAbbreviations: ["Hab", "Hb"], vietnamese: ["Ha-ba-cúc"], viAbbreviation: "ha")),
        ("ZEP", Entry(english: ["Zephaniah"], englishAbbreviations: ["Zeph", "Zep", "Zp"], vietnamese: ["Sô-phô-ni"], viAbbreviation: "so", viExtra: ["Xô-phô-ni"])),
        ("HAG", Entry(english: ["Haggai"], englishAbbreviations: ["Hag", "Hg"], vietnamese: ["A-ghê"], viAbbreviation: "ag", viExtra: ["A-gai"])),
        ("ZEC", Entry(english: ["Zechariah"], englishAbbreviations: ["Zech", "Zec", "Zc"], vietnamese: ["Xa-cha-ri"], viAbbreviation: "xa")),
        ("MAL", Entry(english: ["Malachi"], englishAbbreviations: ["Mal", "Ml"], vietnamese: ["Ma-la-chi"], viAbbreviation: "ma")),
        ("MAT", Entry(english: ["Matthew"], englishAbbreviations: ["Matt", "Mt"], vietnamese: ["Ma-thi-ơ"], viAbbreviation: "mat")),
        ("MRK", Entry(english: ["Mark"], englishAbbreviations: ["Mrk", "Mk", "Mr"], vietnamese: ["Mác"], viAbbreviation: "mac")),
        ("LUK", Entry(english: ["Luke"], englishAbbreviations: ["Luk", "Lk"], vietnamese: ["Lu-ca"], viAbbreviation: "lu")),
        ("JHN", Entry(english: ["John"], englishAbbreviations: ["Jn", "Jhn"], vietnamese: ["Giăng"], viAbbreviation: "gi")),
        ("ACT", Entry(english: ["Acts", "Acts of the Apostles"], englishAbbreviations: ["Ac"], vietnamese: ["Công-vụ các Sứ-đồ"], viAbbreviation: "cong")),
        ("ROM", Entry(english: ["Romans"], englishAbbreviations: ["Rom", "Ro", "Rm"], vietnamese: ["Rô-ma"], viAbbreviation: "ro", viExtra: ["La-mã"])),
        ("1CO", Entry(english: ["1 Corinthians"], englishAbbreviations: ["1 Cor", "1 Co"], vietnamese: ["1 Cô-rinh-tô"], viAbbreviation: "1co")),
        ("2CO", Entry(english: ["2 Corinthians"], englishAbbreviations: ["2 Cor", "2 Co"], vietnamese: ["2 Cô-rinh-tô"], viAbbreviation: "2co")),
        ("GAL", Entry(english: ["Galatians"], englishAbbreviations: ["Gal", "Ga"], vietnamese: ["Ga-la-ti"], viAbbreviation: "ga")),
        ("EPH", Entry(english: ["Ephesians"], englishAbbreviations: ["Eph", "Ephes"], vietnamese: ["Ê-phê-sô"], viAbbreviation: "eph")),
        ("PHP", Entry(english: ["Philippians"], englishAbbreviations: ["Php"], vietnamese: ["Phi-líp"], viAbbreviation: "phi")),
        ("COL", Entry(english: ["Colossians"], englishAbbreviations: ["Col"], vietnamese: ["Cô-lô-se"], viAbbreviation: "co")),
        ("1TH", Entry(english: ["1 Thessalonians"], englishAbbreviations: ["1 Thess", "1 Thes", "1 Th"], vietnamese: ["1 Tê-sa-lô-ni-ca"], viAbbreviation: "1te")),
        ("2TH", Entry(english: ["2 Thessalonians"], englishAbbreviations: ["2 Thess", "2 Thes", "2 Th"], vietnamese: ["2 Tê-sa-lô-ni-ca"], viAbbreviation: "2te")),
        ("1TI", Entry(english: ["1 Timothy"], englishAbbreviations: ["1 Tim", "1 Ti"], vietnamese: ["1 Ti-mô-thê"], viAbbreviation: "1ti")),
        ("2TI", Entry(english: ["2 Timothy"], englishAbbreviations: ["2 Tim", "2 Ti"], vietnamese: ["2 Ti-mô-thê"], viAbbreviation: "2ti")),
        ("TIT", Entry(english: ["Titus"], englishAbbreviations: ["Tit"], vietnamese: ["Tít"], viAbbreviation: "tit")),
        ("PHM", Entry(english: ["Philemon"], englishAbbreviations: ["Phm", "Philem", "Pm"], vietnamese: ["Phi-lê-môn"], viAbbreviation: "phil")),
        ("HEB", Entry(english: ["Hebrews"], englishAbbreviations: ["Heb"], vietnamese: ["Hê-bơ-rơ"], viAbbreviation: "he")),
        ("JAS", Entry(english: ["James"], englishAbbreviations: ["Jas", "Jm"], vietnamese: ["Gia-cơ"], viAbbreviation: "gia")),
        ("1PE", Entry(english: ["1 Peter"], englishAbbreviations: ["1 Pet", "1 Pe", "1 Pt"], vietnamese: ["1 Phi-e-rơ"], viAbbreviation: "1phi", viExtra: ["1 Phia-rơ"])),
        ("2PE", Entry(english: ["2 Peter"], englishAbbreviations: ["2 Pet", "2 Pe", "2 Pt"], vietnamese: ["2 Phi-e-rơ"], viAbbreviation: "2phi", viExtra: ["2 Phia-rơ"])),
        ("1JN", Entry(english: ["1 John"], englishAbbreviations: ["1 Jn", "1 Jo", "1 Joh", "1 Jhn"], vietnamese: ["1 Giăng"], viAbbreviation: "1gi")),
        ("2JN", Entry(english: ["2 John"], englishAbbreviations: ["2 Jn", "2 Jo", "2 Joh", "2 Jhn"], vietnamese: ["2 Giăng"], viAbbreviation: "2gi")),
        ("3JN", Entry(english: ["3 John"], englishAbbreviations: ["3 Jn", "3 Jo", "3 Joh", "3 Jhn"], vietnamese: ["3 Giăng"], viAbbreviation: "3gi")),
        ("JUD", Entry(english: ["Jude"], englishAbbreviations: ["Jde"], vietnamese: ["Giu-đe"], viAbbreviation: "giu")),
        ("REV", Entry(english: ["Revelation", "Revelations", "The Revelation"], englishAbbreviations: ["Rev", "Re"], vietnamese: ["Khải-huyền"], viAbbreviation: "kh", viExtra: ["Khải-thị"])),
    ]
}

public enum BookMatcher {
    /// Resolves typed book text. Ignores case, diacritics, hyphens, full stops and spacing, accepts a leading
    /// number as 1, I, 1st or First, and accepts a unique prefix. Exact names and abbreviations beat prefixes.
    public static func match(_ text: String, context: MatchContext = .auto) -> BookMatch {
        let q = BookNames.key(text)
        guard q.contains(where: { $0.isLetter }) else { return .unknown }

        var effective = context
        if context == .auto, hasDiacritics(text) { effective = .vietnamese }

        switch effective {
        case .english:
            return result(lookup(q, .english) ?? lookup(q, .vietnamese) ?? unnumbered(q))
        case .vietnamese:
            return result(lookup(q, .vietnamese) ?? lookup(q, .english) ?? unnumbered(q))
        case .auto:
            let en = BookNames.index(for: .english), vi = BookNames.index(for: .vietnamese)
            let exactEn = en.exact[q] ?? [], exactVi = vi.exact[q] ?? []
            if !exactEn.isEmpty || !exactVi.isEmpty {
                var set = exactEn.union(exactVi)
                // A Vietnamese short form that is also the start of other English names is not safe to guess.
                if exactEn.isEmpty, vi.abbreviationOnly.contains(q) {
                    let prefixEn = prefixSet(q, en)
                    if !prefixEn.isEmpty, !prefixEn.isSubset(of: exactVi) { set.formUnion(prefixEn) }
                }
                return result(set)
            }
            let set = prefixSet(q, en).union(prefixSet(q, vi))
            return result(set.isEmpty ? unnumbered(q) : set)
        }
    }

    private static func lookup(_ q: String, _ language: ScriptureLanguage) -> Set<BookID>? {
        let index = BookNames.index(for: language)
        if let exact = index.exact[q], !exact.isEmpty { return exact }
        let prefix = prefixSet(q, index)
        return prefix.isEmpty ? nil : prefix
    }

    private static func prefixSet(_ q: String, _ index: BookNames.Index) -> Set<BookID> {
        Set(index.prefixes.filter { $0.key.hasPrefix(q) }.map(\.book))
    }

    private static func unnumbered(_ q: String) -> Set<BookID> {
        Set(BookNames.unnumberedPrefixes.filter { $0.key.hasPrefix(q) }.map(\.book))
    }

    private static func result(_ set: Set<BookID>) -> BookMatch {
        switch set.count {
        case 0: return .unknown
        case 1: return .book(set.first ?? BookID(""))
        default: return .ambiguous(set.sorted())
        }
    }

    private static func hasDiacritics(_ text: String) -> Bool {
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { return true }
            if scalar == "\u{0111}" || scalar == "\u{0110}" { return true }
        }
        return false
    }
}
