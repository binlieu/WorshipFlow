// STAGE-001a: time text built by hand so it never depends on the user's locale. Foundation only.
import Foundation

public enum TimeFormat {
    /// `m:ss` or `h:mm:ss`, with a leading minus below zero. Fractions round toward the later second, so a
    /// countdown shows `0:00` only at zero.
    public static func clock(seconds: TimeInterval) -> String {
        let limit = 99.0 * 3600 + 3599
        let clamped = seconds.isNaN ? 0 : min(limit, max(-limit, seconds))
        let whole = Int(clamped.rounded(.up))
        let total = abs(whole)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        let sign = whole < 0 ? "-" : ""
        if h > 0 { return "\(sign)\(h):\(pad(m)):\(pad(s))" }
        return "\(sign)\(m):\(pad(s))"
    }

    /// `14:05`, `14:05:09`, `2:05 PM` or `2:05:09 PM` in the given calendar's time zone.
    public static func timeOfDay(_ date: Date, calendar: Calendar, twentyFourHour: Bool, showSeconds: Bool) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        let tail = showSeconds ? ":\(pad(second))" : ""
        if twentyFourHour { return "\(pad(hour)):\(pad(minute))\(tail)" }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):\(pad(minute))\(tail) \(hour < 12 ? "AM" : "PM")"
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
