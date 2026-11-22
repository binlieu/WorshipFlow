// FIX-T item 1 (SYS): conversions of a stored or measured number that cannot trap. A media duration read from a library or a program
// package may be any Double (a damaged file, a hand-made package); `Int(Double)` traps outside the Int range and on NaN. Foundation only.
import Foundation

extension Int {
    /// The whole number nearest zero, held to the Int range. NaN is 0, infinity is `Int.max` or `Int.min`. Never traps.
    public init(saturating value: Double) {
        if value.isNaN { self = 0 }
        else if value >= Double(Int.max) { self = Int.max }
        else if value <= Double(Int.min) { self = Int.min }
        else { self = Int(value) }
    }
}

/// Text for lengths and readouts built from numbers that may be absurd. Every function is total.
public enum MediaClock {
    /// What a length shows when the stored number is no length (not a number, negative, or longer than `longest`).
    public static let unknown = "–:–"
    /// Longer than this is not a media length; 100 hours.
    public static let longest = 360_000.0

    /// `m:ss`, or `h:mm:ss` from an hour up: the length of a clip on a tile or a row. "–:–" for a number that is no length.
    public static func length(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds <= longest else { return unknown }
        let s = Int(saturating: seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// `mm:ss` of a cue's length or position. Below zero is 00:00; a number that is no length is "–:–".
    public static func cue(_ seconds: Double) -> String {
        guard !seconds.isNaN, seconds <= longest else { return unknown }
        let s = Int(saturating: max(0, seconds).rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "00:11.4": minutes, seconds and tenths of a playback position. A number that is no position reads 00:00.0.
    public static func tenths(_ seconds: Double) -> String {
        let t = seconds.isNaN ? 0 : min(longest, max(0, seconds))
        let whole = Int(saturating: t)
        return String(format: "%02d:%02d.%d", whole / 60, whole % 60, Int(saturating: (t - Double(whole)) * 10))
    }

    /// A fraction as a whole percent ("46%"). NaN is 0%; the number is not limited to 0...1 but cannot trap.
    public static func percent(_ fraction: Double) -> String {
        let p = Int(saturating: (fraction * 100).rounded())
        return "\(p)%"
    }
}
