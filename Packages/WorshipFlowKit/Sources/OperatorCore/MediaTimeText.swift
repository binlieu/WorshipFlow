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

/// FIX-Y (MEDIA; REVIEW-5 L4): what leaving (or pressing Return in) a mark or marker time field does. The field shows a time to a tenth of a second, so a
/// stored 12.37 reads "00:12.4": leaving the field untouched must not write 12.4. A time is written only when the operator typed something that is not
/// what the field showed for the stored time.
public enum TimeFieldEdit: Equatable, Sendable {
    case unchanged
    case set(Double)
    case clear
    /// The text is no time: the field goes back to the stored value.
    case invalid

    public static func edit(text: String, stored: Double?, emptyClears: Bool) -> TimeFieldEdit {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return emptyClears ? (stored == nil ? .unchanged : .clear) : .invalid }
        guard let value = MediaTimeText.parse(trimmed) else { return .invalid }
        if let stored, abs(value - stored) <= 0.0005 { return .unchanged }      
        if let stored, trimmed == MediaTimeText.format(stored) { return .unchanged }
        return .set(value)
    }
}
