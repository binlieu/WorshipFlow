// UI-007d (MEDIA): a time typed or shown for a mark or a marker. Foundation and Domain only.
import Foundation
import Domain

public enum MediaTimeText {
    /// Reads what an operator types: seconds ("12", "12.5"), minutes and seconds ("1:05", "01:05.5") or hours, minutes and seconds ("1:02:03").
    /// Nil for anything else (empty, a sign, a letter, a minute or second of 60 or more, an exponent, "nan").
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || ($0 == "." && isLast)) }) else { return nil }
            if !isLast, part.contains(".") { return nil }
            guard let value = Double(part), value.isFinite else { return nil }
            if index > 0, value >= 60 { return nil }                     // a minute or a second written as 60 or more
            total = total * 60 + value
        }
        return total <= MediaClock.longest ? total : nil
    }

    /// "01:05.5": minutes, seconds and tenths, rounded to the nearest tenth (never "00:59.10"). A number that is no time reads 00:00.0.
    public static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return MediaClock.tenths(0) }
        let tenths = (min(MediaClock.longest, max(0, seconds)) * 10).rounded() / 10
        return MediaClock.tenths(tenths + 0.001)       // the tenth is shown, not floored from a float that is a hair under it
    }
}
