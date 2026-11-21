// SYS-001 acceptance tests (PRES-08, ADR-0004 decision 8). Owned by the coordinator: do not modify.
import Testing
@testable import Domain

@Suite struct SearchFoldingTests {
    @Test func foldsTheHymnLine() {
        #expect(SearchFolding.fold("Ân điển lạ lùng thay") == "an dien la lung thay")
    }

    @Test func foldsDWithStroke() {
        #expect(SearchFolding.fold("Đức Chúa Trời") == "duc chua troi")
        #expect(SearchFolding.fold("đ Đ") == "d d")
    }

    /// Every Vietnamese letter, both cases, folds to its base letter.
    @Test func foldsEveryVietnameseLetter() {
        let groups: [(String, String)] = [
            ("a", "àáảãạăằắẳẵặâầấẩẫậÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ"),
            ("e", "èéẻẽẹêềếểễệÈÉẺẼẸÊỀẾỂỄỆ"),
            ("i", "ìíỉĩịÌÍỈĨỊ"),
            ("o", "òóỏõọôồốổỗộơờớởỡợÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ"),
            ("u", "ùúủũụưừứửữựÙÚỦŨỤƯỪỨỬỮỰ"),
            ("y", "ỳýỷỹỵỲÝỶỸỴ"),
            ("d", "đĐ"),
        ]
        for (base, letters) in groups {
            for ch in letters {
                #expect(SearchFolding.fold(String(ch)) == base, "\(ch) should fold to \(base)")
            }
        }
    }

    /// Decomposed input (base letter plus combining marks) folds the same as precomposed.
    @Test func decomposedAndPrecomposedAgree() {
        let precomposed = "điển"
        let decomposed = "đie\u{0302}\u{0309}n"
        #expect(SearchFolding.fold(precomposed) == SearchFolding.fold(decomposed))
        #expect(SearchFolding.fold(decomposed) == "dien")
    }

    @Test func collapsesWhitespaceAndPunctuation() {
        #expect(SearchFolding.fold("  Amazing   Grace,\nhow SWEET — the sound!  ") == "amazing grace how sweet the sound")
    }

    @Test func emptyStaysEmpty() {
        #expect(SearchFolding.fold("") == "")
        #expect(SearchFolding.fold(" \n\t") == "")
    }
}
