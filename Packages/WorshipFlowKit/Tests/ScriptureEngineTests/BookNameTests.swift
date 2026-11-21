// LIB-004: book-name matching in English and Vietnamese.
import Testing
@testable import ScriptureEngine

extension BookMatch {
    /// For expectations written in any order: ambiguity lists are always in canon order.
    var sortedCanon: BookMatch {
        if case .ambiguous(let ids) = self { return .ambiguous(ids.sorted()) }
        return self
    }
}

@Suite struct BookNameTests {
    private func id(_ s: String) -> BookMatch { .book(BookID(s)) }

    @Test func englishNamesAndAbbreviations() {
        let cases: [(String, String)] = [
            ("Genesis", "GEN"), ("Gen", "GEN"), ("Gn", "GEN"), ("GENESIS", "GEN"), ("gen.", "GEN"),
            ("1 Cor", "1CO"), ("1Co", "1CO"), ("I Corinthians", "1CO"), ("1st Corinthians", "1CO"),
            ("First Corinthians", "1CO"), ("II Kings", "2KI"), ("2 Kgs", "2KI"), ("III John", "3JN"), ("3Jn", "3JN"),
            ("Song of Songs", "SNG"), ("Song of Solomon", "SNG"), ("Canticles", "SNG"), ("Song", "SNG"),
            ("Ps", "PSA"), ("Psalm", "PSA"), ("Psalms", "PSA"), ("Pss", "PSA"),
            ("Rev", "REV"), ("Revelation", "REV"), ("Jn", "JHN"), ("John", "JHN"), ("Joh", "JHN"),
            ("Jon", "JON"), ("Jonah", "JON"), ("Jude", "JUD"), ("Judg", "JDG"), ("Judges", "JDG"),
            ("Phm", "PHM"), ("Php", "PHP"), ("Philippians", "PHP"), ("Philem", "PHM"),
            ("Ex", "EXO"), ("Exod", "EXO"), ("Mal", "MAL"), ("Mark", "MRK"), ("Mar", "MRK"),
            ("Is", "ISA"), ("Isa", "ISA"), ("Acts", "ACT"), ("1 Sam", "1SA"), ("2 Chron", "2CH"),
        ]
        for (text, code) in cases {
            #expect(BookMatcher.match(text) == id(code), "\(text)")
        }
    }

    @Test func ambiguityIsReportedNotGuessed() {
        #expect(BookMatcher.match("Phil") == .ambiguous([BookID("PHP"), BookID("PHM")]))
        #expect(BookMatcher.match("Jud") == .ambiguous([BookID("JDG"), BookID("JUD")]))
        #expect(BookMatcher.match("Jo") == .ambiguous(["JOS", "JOB", "JOL", "JON", "JHN"].map { BookID($0) }))
        // A numbered book written without its number.
        #expect(BookMatcher.match("Cor") == .ambiguous([BookID("1CO"), BookID("2CO")]))
        #expect(BookMatcher.match("Samuel") == .ambiguous([BookID("1SA"), BookID("2SA")]))
    }

    @Test func unknownNames() {
        #expect(BookMatcher.match("Foo") == .unknown)
        #expect(BookMatcher.match("") == .unknown)
        #expect(BookMatcher.match("   ") == .unknown)
        #expect(BookMatcher.match("3") == .unknown)
    }

    @Test func vietnameseNamesIgnoreDiacriticsHyphensAndCase() {
        let cases: [(String, String)] = [
            ("Sáng Thế Ký", "GEN"), ("Sáng-thế Ký", "GEN"), ("sang the ky", "GEN"), ("Sáng", "GEN"),
            ("Xuất Ê-díp-tô Ký", "EXO"), ("Xuất Ai-cập", "EXO"), ("Xuất", "EXO"),
            ("Thi Thiên", "PSA"), ("Thi-thiên", "PSA"), ("Thi", "PSA"),
            ("Ma-thi-ơ", "MAT"), ("Mat", "MAT"), ("Mác", "MRK"), ("Lu-ca", "LUK"),
            ("Giăng", "JHN"), ("1 Giăng", "1JN"), ("I Giăng", "1JN"), ("2 Giăng", "2JN"), ("3 Giăng", "3JN"),
            ("Công Vụ", "ACT"), ("Công-vụ các Sứ-đồ", "ACT"), ("Rô-ma", "ROM"), ("La-mã", "ROM"),
            ("Khải Huyền", "REV"), ("Khải-huyền", "REV"), ("Khải-thị", "REV"),
            ("1 Sa-mu-ên", "1SA"), ("II Sa-mu-ên", "2SA"), ("1 Các Vua", "1KI"), ("2 Sử-ký", "2CH"),
            ("1 Cô-rinh-tô", "1CO"), ("Ê-phê-sô", "EPH"), ("Phi-líp", "PHP"), ("Phi-lê-môn", "PHM"),
            ("1 Phi-e-rơ", "1PE"), ("1 Phia-rơ", "1PE"), ("Hê-bơ-rơ", "HEB"), ("Gia-cơ", "JAS"),
            ("Giu-đe", "JUD"), ("Tít", "TIT"), ("Gióp", "JOB"), ("Châm-ngôn", "PRO"),
            ("Nhã-ca", "SNG"), ("Tình ca", "SNG"), ("Ca-thương", "LAM"), ("Ai ca", "LAM"),
            ("Truyền-đạo", "ECC"), ("Giáo huấn", "ECC"), ("Quan án", "JDG"), ("Các Quan Xét", "JDG"),
            ("Phục-truyền Luật-lệ Ký", "DEU"), ("Dân-số Ký", "NUM"), ("Ê-xê-chi-ên", "EZK"),
            ("Đa-ni-ên", "DAN"), ("A-ghê", "HAG"), ("A-gai", "HAG"), ("Áp-đia", "OBA"), ("Na-hum", "NAM"),
        ]
        for (text, code) in cases {
            #expect(BookMatcher.match(text) == id(code), "\(text)")
        }
    }

    @Test func vietnameseQueryWithDiacriticsPrefersVietnameseNames() {
        // The diacritic says it is Vietnamese: "Ê-xơ" is the owner's abbreviation `exo`, which is Ezra.
        #expect(BookMatcher.match("Ê-xơ") == id("EZR"))
        #expect(BookMatcher.match("Ê-xơ-ra") == id("EZR"))
        #expect(BookMatcher.match("Ê-xơ-tê") == id("EST"))
        #expect(BookMatcher.match("Ê-xê") == id("EZK"))
    }

    /// The owner's Vietnamese abbreviations (from the 1925 database export) collide with English ones.
    /// With no language context they are reported as ambiguous; with a context the context wins.
    @Test func vietnameseAbbreviationsThatCollideWithEnglishOnes() {
        func m(_ t: String, _ c: MatchContext) -> BookMatch { BookMatcher.match(t, context: c) }
        // exo: Ezra in Vietnamese, Exodus in English.
        #expect(m("exo", .auto) == .ambiguous([BookID("EXO"), BookID("EZR")]))
        #expect(m("exo", .vietnamese) == id("EZR"))
        #expect(m("exo", .english) == id("EXO"))
        // dan: Dân-số Ký (Numbers) in Vietnamese, Daniel in English.
        #expect(m("dan", .auto) == .ambiguous([BookID("NUM"), BookID("DAN")]))
        #expect(m("dan", .vietnamese) == id("NUM"))
        #expect(m("dan", .english) == id("DAN"))
        // es: Ê-sai (Isaiah) in Vietnamese, Esther in English.
        #expect(m("es", .auto) == .ambiguous([BookID("EST"), BookID("ISA")]).sortedCanon)
        #expect(m("es", .vietnamese) == id("ISA"))
        #expect(m("es", .english) == id("EST"))
        // ma: Ma-la-chi in Vietnamese; in English it is a prefix of Malachi, Matthew and Mark.
        #expect(m("ma", .auto) == .ambiguous([BookID("MAL"), BookID("MAT"), BookID("MRK")]))
        #expect(m("ma", .vietnamese) == id("MAL"))
        #expect(m("ma", .english) == .ambiguous([BookID("MAL"), BookID("MAT"), BookID("MRK")]))
        // phi / phil: Philippians and Philemon in Vietnamese, both prefixes of both in English.
        #expect(m("phi", .auto) == .ambiguous([BookID("PHP"), BookID("PHM")]))
        #expect(m("phi", .vietnamese) == id("PHP"))
        #expect(m("phil", .auto) == .ambiguous([BookID("PHP"), BookID("PHM")]))
        #expect(m("phil", .vietnamese) == id("PHM"))
        #expect(m("phil", .english) == .ambiguous([BookID("PHP"), BookID("PHM")]))
        // mat and mac agree with the English reading, so they are not ambiguous.
        #expect(m("mat", .auto) == id("MAT"))
        #expect(m("mac", .auto) == id("MRK"))
        // gi, gio, gion, gios have no English reading at all.
        #expect(m("gi", .auto) == id("JHN"))
        #expect(m("gio", .auto) == id("JOL"))
        #expect(m("gion", .auto) == id("JON"))
        #expect(m("gios", .auto) == id("JOS"))
        // ha: Ha-ba-cúc in Vietnamese; Habakkuk or Haggai in English.
        #expect(m("ha", .auto) == .ambiguous([BookID("HAB"), BookID("HAG")]))
        #expect(m("ha", .vietnamese) == id("HAB"))
        // ca: Ca-thương in Vietnamese; Canticles in English.
        #expect(m("ca", .vietnamese) == id("LAM"))
        #expect(m("ca", .auto) == .ambiguous([BookID("SNG"), BookID("LAM")]).sortedCanon)
    }

    /// The 66 rows of the owner's `bible-db-books.tsv`: abbreviation, Vietnamese name as spelled in the 1925 text.
    static let ownerRows: [(code: String, abbr: String, name: String)] = [
        ("GEN", "sa", "Sáng-thế Ký"), ("EXO", "xu", "Xuất Ê-díp-tô Ký"), ("LEV", "le", "Lê-vi Ký"),
        ("NUM", "dan", "Dân-số Ký"), ("DEU", "phu", "Phục-truyền Luật-lệ Ký"), ("JOS", "gios", "Giô-suê"),
        ("JDG", "cac", "Các Quan Xét"), ("RUT", "ru", "Ru-tơ"), ("1SA", "1sa", "1 Sa-mu-ên"), ("2SA", "2sa", "2 Sa-mu-ên"),
        ("1KI", "1vua", "1 Các Vua"), ("2KI", "2vua", "2 Các Vua"), ("1CH", "1su", "1 Sử-ký"), ("2CH", "2su", "2 Sử-ký"),
        ("EZR", "exo", "E-xơ-ra"), ("NEH", "ne", "Nê-hê-mi"), ("EST", "et", "Ê-xơ-tê"), ("JOB", "giop", "Gióp"),
        ("PSA", "thi", "Thi-thiên"), ("PRO", "ch", "Châm-ngôn"), ("ECC", "tr", "Truyền-đạo"), ("SNG", "nha", "Nhã-ca"),
        ("ISA", "es", "Ê-sai"), ("JER", "gie", "Giê-rê-mi"), ("LAM", "ca", "Ca-thương"), ("EZK", "exe", "Ê-xê-chi-ên"),
        ("DAN", "da", "Đa-ni-ên"), ("HOS", "os", "Ô-sê"), ("JOL", "gio", "Giô-ên"), ("AMO", "am", "A-mốt"),
        ("OBA", "ap", "Áp-đia"), ("JON", "gion", "Giô-na"), ("MIC", "mi", "Mi-chê"), ("NAM", "na", "Na-hum"),
        ("HAB", "ha", "Ha-ba-cúc"), ("ZEP", "so", "Sô-phô-ni"), ("HAG", "ag", "A-ghê"), ("ZEC", "xa", "Xa-cha-ri"),
        ("MAL", "ma", "Ma-la-chi"), ("MAT", "mat", "Ma-thi-ơ"), ("MRK", "mac", "Mác"), ("LUK", "lu", "Lu-ca"),
        ("JHN", "gi", "Giăng"), ("ACT", "cong", "Công-vụ các Sứ-đồ"), ("ROM", "ro", "Rô-ma"),
        ("1CO", "1co", "1 Cô-rinh-tô"), ("2CO", "2co", "2 Cô-rinh-tô"), ("GAL", "ga", "Ga-la-ti"), ("EPH", "eph", "Ê-phê-sô"),
        ("PHP", "phi", "Phi-líp"), ("COL", "co", "Cô-lô-se"), ("1TH", "1te", "1 Tê-sa-lô-ni-ca"), ("2TH", "2te", "2 Tê-sa-lô-ni-ca"),
        ("1TI", "1ti", "1 Ti-mô-thê"), ("2TI", "2ti", "2 Ti-mô-thê"), ("TIT", "tit", "Tít"), ("PHM", "phil", "Phi-lê-môn"),
        ("HEB", "he", "Hê-bơ-rơ"), ("JAS", "gia", "Gia-cơ"), ("1PE", "1phi", "1 Phi-e-rơ"), ("2PE", "2phi", "2 Phi-e-rơ"),
        ("1JN", "1gi", "1 Giăng"), ("2JN", "2gi", "2 Giăng"), ("3JN", "3gi", "3 Giăng"), ("JUD", "giu", "Giu-đe"),
        ("REV", "kh", "Khải-huyền"),
    ]

    @Test func ownerAbbreviationsAndNamesResolveInAVietnameseContext() {
        #expect(Self.ownerRows.count == 66)
        #expect(Self.ownerRows.map(\.code) == Canon.books.map(\.id.rawValue))
        for row in Self.ownerRows {
            #expect(BookMatcher.match(row.abbr, context: .vietnamese) == id(row.code), "abbr \(row.abbr)")
            #expect(BookMatcher.match(row.name, context: .vietnamese) == id(row.code), "name \(row.name)")
            #expect(BookNames.displayName(BookID(row.code), .vietnamese) == row.name, "display \(row.code)")
            #expect(BookNames.vietnameseAbbreviation(BookID(row.code)) == row.abbr, "abbr table \(row.code)")
            // Roman numerals and no hyphens are accepted too.
            let roman = row.name.replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "^1 ", with: "I ", options: .regularExpression)
                .replacingOccurrences(of: "^2 ", with: "II ", options: .regularExpression)
                .replacingOccurrences(of: "^3 ", with: "III ", options: .regularExpression)
            #expect(BookMatcher.match(roman, context: .vietnamese) == id(row.code), "roman \(roman)")
        }
    }

    @Test func displayNames() {
        #expect(BookNames.displayName(BookID("JHN"), .english) == "John")
        #expect(BookNames.displayName(BookID("JHN"), .vietnamese) == "Giăng")
        #expect(BookNames.displayName(BookID("1CO"), .english) == "1 Corinthians")
        #expect(BookNames.displayName(BookID("PSA"), .vietnamese) == "Thi-thiên")
        #expect(BookNames.displayName(BookID("ROM"), .vietnamese) == "Rô-ma")
    }

    @Test func everyBookHasBothDisplayNamesAndTheyResolveToThemselves() {
        for book in Canon.books {
            for language in [ScriptureLanguage.english, .vietnamese] {
                let name = BookNames.displayName(book.id, language)
                #expect(name != nil, "\(book.id) \(language)")
                #expect(BookMatcher.match(name ?? "") == .book(book.id), "\(book.id) \(name ?? "nil")")
            }
        }
    }

    @Test func noTwoBooksShareAnExactAlias() {
        #expect(BookNames.conflictingAliases().isEmpty, "\(BookNames.conflictingAliases())")
    }
}
