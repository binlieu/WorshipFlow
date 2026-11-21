// CUE-002b (item 6): the schedule editor's draft and the words for times. Foundation and CueEngine only.
import Foundation
import CueEngine

public struct ScheduleDraft: Equatable, Sendable {
    public enum Repeat: Sendable, Equatable { case once, weekly }

    public var id: UUID?
    public var name = ""
    public var isEnabled = true
    public var repeats: Repeat = .weekly
    public var date = Date()
    public var weekdays: Set<Weekday> = [.sunday]
    public var hour = 9
    public var minute = 0
    public var timeZoneID: String
    public var macroID: UUID?
    /// The event runs a list of actions written elsewhere; editing here keeps that list as it is.
    public var keptActions: [CueAction]?
    public var keepsActions: Bool { keptActions != nil }

    public init(timeZoneID: String = TimeZone.current.identifier) { self.timeZoneID = timeZoneID }

    public init(event: ScheduledEvent) {
        id = event.id
        name = event.name
        isEnabled = event.isEnabled
        switch event.timing {
        case .once(let d): repeats = .once; date = d; timeZoneID = TimeZone.current.identifier
        case .weekly(let days, let h, let m, let tz): repeats = .weekly; weekdays = days; hour = h; minute = m; timeZoneID = tz
        }
        switch event.payload {
        case .macro(let id): macroID = id
        case .actions(let a): keptActions = a
        }
    }

    private var timing: ScheduledEvent.Timing {
        repeats == .once ? .once(date) : .weekly(weekdays: weekdays, hour: hour, minute: minute, timeZoneID: timeZoneID)
    }

    private var payload: ScheduledEvent.Payload? {
        if let keptActions { return .actions(keptActions) }
        return macroID.map { .macro($0) }
    }

    /// Operator-readable reasons the event cannot work yet.
    public var problems: [String] {
        var out: [String] = []
        if payload == nil { out.append("Choose a macro to run.") }
        let probe = ScheduledEvent(name: name, timing: timing, payload: payload ?? .macro(UUID()))
        out = probe.validationIssues + out
        return out
    }

    public func build() -> ScheduledEvent? {
        guard problems.isEmpty, let payload else { return nil }
        return ScheduledEvent(id: id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), isEnabled: isEnabled,
                              timing: timing, payload: payload)
    }
}

public enum ScheduleText {
    private static let short = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static func formatter(_ format: String, _ calendar: Calendar, zone: TimeZone? = nil) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = zone ?? calendar.timeZone
        f.dateFormat = format
        return f
    }

    public static func timing(_ timing: ScheduledEvent.Timing, calendar: Calendar) -> String {
        switch timing {
        case .once(let date): return formatter("d MMM yyyy HH:mm", calendar).string(from: date)
        case .weekly(let days, let h, let m, _):
            let time = String(format: "%02d:%02d", h, m)
            if days.count == 7 { return "Every day \(time)" }
            let names = Weekday.allCases.filter(days.contains).map { short[$0.rawValue - 1] }
            return "\(names.joined(separator: ", ")) \(time)"
        }
    }

    /// "today 09:00", "tomorrow 09:00", "Sun 22 Nov 09:00".
    public static func next(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = formatter("HH:mm", calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow \(time)" }
        return formatter("EEE d MMM HH:mm", calendar).string(from: date)
    }
}
