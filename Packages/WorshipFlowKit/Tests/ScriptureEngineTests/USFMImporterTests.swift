// LIB-004: USFM import for one book. The fixture is hand-written and uses King James Version wording.
import Testing
@testable import ScriptureEngine

@Suite struct USFMImporterTests {
    static let genesis = #"""
    \id GEN Genesis (fixture)
    \ide UTF-8
    \h Genesis
    \toc1 The First Book of Moses
    \mt1 Genesis
    \c 1
    \s1 The Creation
    \r (John 1:1-5)
    \p
    \v 1 In the beginning \w God|lemma="elohim" strong="H430"\w* created the heaven and the earth.\f + \fr 1:1 \ft Or \+w the heavens\+w*\f*
    \v 2 And the earth was without form, and void; and darkness was upon the face of the deep.
    \q1 And the Spirit of God moved upon the face of the waters.\x - \xo 1:2 \xt Isa 40:13\x*
    \v 3 And God said, \add Let there be light\add*: and there was light.
    """#

    @Test func importsVersesAndStripsNotesWordMarkersAndHeadings() {
        let result = USFMImporter.importBook(Self.genesis)
        #expect(result.book == BookID("GEN"))
        #expect(result.chapters[1]?[1] == "In the beginning God created the heaven and the earth.")
        #expect(result.chapters[1]?[2] == "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters.")
        #expect(result.chapters[1]?[3] == "And God said, Let there be light: and there was light.")
        #expect(result.report.verseCount == 3)
        #expect(result.report.chapterCount == 1)
        #expect(result.report.notesStripped == 2)
        #expect(result.report.unknownMarkers.isEmpty)
        // Headings, titles and file header lines are skipped and counted, never shown.
        #expect(result.report.ignoredMarkers["s1"] == 1)
        #expect(result.report.ignoredMarkers["r"] == 1)
        #expect(result.report.ignoredMarkers["h"] == 1)
        #expect(result.report.ignoredMarkers["toc1"] == 1)
        let all = result.chapters.values.flatMap { $0.values }.joined()
        #expect(!all.contains("\\"))
        #expect(!all.contains("Creation"))
        #expect(!all.contains("lemma"))
        #expect(!all.contains("1:1"))
    }

    @Test func unknownMarkersAreDroppedAndCounted() {
        let usfm = "\\id JHN\n\\c 3\n\\p\n\\v 16 For God so loved the world,\n\\blah\nthat he gave his only begotten Son.\\zcustom* \\zthing\n\\v 17 Next."
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[3]?[16] == "For God so loved the world, that he gave his only begotten Son.")
        #expect(result.chapters[3]?[17] == "Next.")
        #expect(result.report.unknownMarkers["blah"] == 1)
        #expect(result.report.unknownMarkers["zthing"] == 1)
        let all = result.chapters[3]?.values.joined() ?? ""
        #expect(!all.contains("\\") && !all.contains("blah"))
    }

    @Test func verseBridgesDuplicatesAndLetters() {
        let usfm = "\\id JHN\n\\c 3\n\\p\n\\v 1-2 Bridged text.\n\\v 3a First half\n\\v 4 Four.\n\\v 4 Four again."
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[3]?[1] == "Bridged text.")
        #expect(result.chapters[3]?[2] == nil)
        #expect(result.chapters[3]?[3] == "First half")
        #expect(result.chapters[3]?[4] == "Four.")
        #expect(result.report.bridgedVerses == ["3:1-2"])
        #expect(result.report.duplicateVerses == ["3:4"])
    }

    @Test func poetryParagraphsAreJoinedWithASingleSpace() {
        let usfm = "\\id PSA\n\\c 23\n\\q1\n\\v 1 The LORD is my shepherd;\n\\q2 I shall not want.\n\\b\n\\q1\n\\v 2 He maketh me to lie down in green pastures:\n\\q2 he leadeth me beside the still waters."
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[23]?[1] == "The LORD is my shepherd; I shall not want.")
        #expect(result.chapters[23]?[2] == "He maketh me to lie down in green pastures: he leadeth me beside the still waters.")
    }

    @Test func psalmTitlesAndRemarksAreIgnored() {
        let usfm = "\\id PSA\n\\c 23\n\\d A Psalm of David.\n\\rem a remark\n\\q1\n\\v 1 The LORD is my shepherd;\n\\sp Speaker\n\\q2 I shall not want."
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[23]?[1] == "The LORD is my shepherd; I shall not want.")
        #expect(result.report.ignoredMarkers["d"] == 1)
        #expect(result.report.ignoredMarkers["rem"] == 1)
    }

    @Test func nestedAndUnclosedNotesDoNotLeakText() {
        let usfm = "\\id JHN\n\\c 1\n\\p\n\\v 1 Alpha\\f + \\fr 1.1 \\fq quoted \\ft a note\\f* beta\\x - \\xo 1.1 \\xt Gen 1:1\\x* gamma.\n\\v 2 Delta\\f + \\ft never closed\n\\v 3 Epsilon."
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[1]?[1] == "Alpha beta gamma.")
        #expect(result.chapters[1]?[2] == "Delta")
        #expect(result.chapters[1]?[3] == "Epsilon.")
        #expect(result.report.warnings.contains { $0.contains("not closed") })
    }

    @Test func characterStylesAreUnwrappedAndNonBreakingSpacesBecomeSpaces() {
        let usfm = "\\id JHN\n\\c 1\n\\p\n\\v 1 \\nd LORD\\nd* said \\wj Come\\wj*, \\+w see|strong=\"G1\"\\+w*~now \\qs Selah\\qs*.\\fig x|src=\"y\"\\fig*\\ca 2\\ca*\\va 3\\va*"
        let result = USFMImporter.importBook(usfm)
        #expect(result.chapters[1]?[1] == "LORD said Come, see now Selah.")
    }

    @Test func emptyAndStructurelessInput() {
        let empty = USFMImporter.importBook("")
        #expect(empty.book == nil)
        #expect(empty.chapters.isEmpty)
        #expect(empty.report.warnings.contains { $0.contains("\\id") })
        let junk = USFMImporter.importBook("just some words with no markers")
        #expect(junk.chapters.isEmpty)
    }

    @Test func versesBeforeAChapterMarkerAreReportedNotLost() {
        let result = USFMImporter.importBook("\\id JUD\n\\p\n\\v 3 Beloved.")
        #expect(result.chapters[1]?[3] == "Beloved.")
        #expect(result.report.warnings.contains { $0.contains("chapter") })
    }

    @Test func aSecondBookIsNotMixedIn() {
        let result = USFMImporter.importBook("\\id JHN\n\\c 1\n\\p\n\\v 1 One.\n\\id MRK\n\\c 1\n\\p\n\\v 1 Two.")
        #expect(result.book == BookID("JHN"))
        #expect(result.chapters[1]?[1] == "One.")
        #expect(result.report.warnings.contains { $0.contains("second") })
    }

    @Test func unrecognisedBookCodeIsReported() {
        let result = USFMImporter.importBook("\\id XYZ\n\\c 1\n\\p\n\\v 1 One.")
        #expect(result.book == nil)
        #expect(result.report.warnings.contains { $0.contains("XYZ") })
        #expect(result.chapters[1]?[1] == "One.")
    }

    @Test func importedBookGoesIntoATranslationFile() throws {
        let result = USFMImporter.importBook(Self.genesis)
        var file = TranslationFile(metadata: TranslationMetadata(id: "t", name: "T", language: "en", abbreviation: "T"), books: [:])
        try file.add(result)
        let loaded = TranslationLoader.validate(file)
        #expect(loaded.translation.text(for: VerseRef(book: BookID("GEN"), chapter: 1, verse: 3))?.hasSuffix("there was light.") == true)
        #expect(throws: TranslationLoadError.self) { try file.add(USFMImporter.importBook("")) }
    }
}
