// SYS-001 / ADR-0004 decision 8: the one rule that folds text for search. Foundation only.
import Foundation

public enum SearchFolding {
    /// Lowercases, strips combining marks, maps đ and Đ to d, turns every run of
    /// non-alphanumeric characters into one space, and trims the result.
    /// Applied to stored text and to queries so both sides always agree.
    public static func fold(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in decomposed.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark || category == .spacingMark || category == .enclosingMark {
                continue
            }
            let mapped: Unicode.Scalar = (scalar == "\u{0111}" || scalar == "\u{0110}") ? "d" : scalar
            if isLetterOrNumber(mapped.properties.generalCategory) {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(mapped)
            } else {
                pendingSpace = true
            }
        }
        return String(out)
    }

    private static func isLetterOrNumber(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}
