// CUE-001 (AUTO-12): calendar scheduling. Foundation only.
//
// Rules, in short:
// - A weekly event is a wall-clock time (hour, minute) in a named time zone on chosen weekdays.
// - A time that does not exist on a spring-forward day fires at the first valid minute after the gap. A time that
//   occurs twice on a fall-back day fires once, at its first occurrence.
// - `due(after:upTo:)` looks at the window (after, upTo]. An occurrence later than the grace period (measured to
//   `upTo`) is skipped and reported, never run late. Each occurrence is handled once: the engine remembers the last one.
import Foundation

public enum Weekday: Int, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// Same numbering as `Calendar.component(.weekday, ...)`.
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

public struct ScheduledEvent: Sendable, Equatable, Codable, Identifiable {
    /// CUE-002a: the stored format version. A missing version reads as 1.
    public static let currentVersion = 1

    public enum Timing: Sendable, Equatable, Codable {
        case once(Date)
        case weekly(weekdays: Set<Weekday>, hour: Int, minute: Int, timeZoneID: String)
    }

    public enum Payload: Sendable, Equatable, Codable {
        case actions([CueAction])
        case macro(UUID)
    }

    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var timing: Timing
    public var payload: Payload
    /// Occurrences at or before this instant are ignored. Set it to "now" when an event is created or switched on, so a
    /// time earlier today does not fire at once.
    public var activeFrom: Date

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, timing: Timing, payload: Payload, activeFrom: Date = .distantPast) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.timing = timing
        self.payload = payload
        self.activeFrom = activeFrom
    }

    private enum CodingKeys: String, CodingKey { case version, id, name, isEnabled, timing, payload, activeFrom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        timing = try c.decode(Timing.self, forKey: .timing)
        payload = try c.decode(Payload.self, forKey: .payload)
        activeFrom = try c.decodeIfPresent(Date.self, forKey: .activeFrom) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(timing, forKey: .timing)
        try c.encode(payload, forKey: .payload)
        try c.encode(activeFrom, forKey: .activeFrom)
    }

    public var cueActions: [CueAction] {
        switch payload {
        case .actions(let a): return a
        case .macro(let id): return [.runMacro(id)]
        }
    }

    /// Operator-readable problems that stop the event from working.
    public var validationIssues: [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("The event needs a name.") }
        out.append(contentsOf: timingIssues)
        if case .actions(let a) = payload, a.isEmpty { out.append("The event has no actions.") }
        return out
    }

    private var timingIssues: [String] {
        guard case .weekly(let days, let hour, let minute, let tz) = timing else { return [] }
        var out: [String] = []
        if days.isEmpty { out.append("Choose at least one weekday.") }
        if !(0...23).contains(hour) { out.append("The hour must be 0 to 23.") }
        if !(0...59).contains(minute) { out.append("The minute must be 0 to 59.") }
        if TimeZone(identifier: tz) == nil { out.append("Unknown time zone \u{201C}\(tz)\u{201D}.") }
        return out
    }

    /// The instants in (after, upTo] at which the event is due, oldest first. Ignores `isEnabled` and what was already
    /// fired; honours `activeFrom`. `calendar` supplies the Gregorian day arithmetic; its own time zone is not used,
    /// because each event names its own zone. A non-Gregorian calendar is replaced by the Gregorian one.
    public func occurrences(after: Date, upTo: Date, calendar: Calendar) -> [Date] {
        let from = max(after, activeFrom)
        guard from < upTo else { return [] }
        switch timing {
        case .once(let d):
            return d > from && d <= upTo ? [d] : []
        case .weekly(let days, let hour, let minute, let tzID):
            guard timingIssues.isEmpty, let tz = TimeZone(identifier: tzID) else { return [] }
            var cal = calendar.identifier == .gregorian ? calendar : Calendar(identifier: .gregorian)
            cal.timeZone = tz
            guard var day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: from)),
                  let last = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: upTo)) else { return [] }
            var out: [Date] = []
            while day <= last {
                let c = cal.dateComponents([.year, .month, .day, .weekday], from: day)
                if let y = c.year, let m = c.month, let d = c.day, let w = c.weekday.flatMap(Weekday.init(rawValue:)), days.contains(w) {
                    let t = LocalTime.instant(year: y, month: m, day: d, hour: hour, minute: minute, in: tz)
                    if t > from && t <= upTo { out.append(t) }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
            return Array(Set(out)).sorted()
        }
    }
}

/// Wall-clock to instant conversion that does not depend on how Foundation resolves times that do not exist or
/// repeat. Uses only the zone's offset at a given instant.
enum LocalTime {
    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The instant at which the zone's clock first shows this date and time. A time inside a spring-forward gap gives the
    /// instant the gap ends (the first valid minute). A time that occurs twice gives the first occurrence.
    static func instant(year: Int, month: Int, day: Int, hour: Int, minute: Int, in tz: TimeZone) -> Date {
        let local = daysFromCivil(year: year, month: month, day: day) * 86_400 + hour * 3_600 + minute * 60
        func offset(_ t: Int) -> Int { tz.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(t))) }

        let before = offset(local - 86_400)
        let after = offset(local + 86_400)
        let valid = Set([local - before, local - after]).filter { $0 + offset($0) == local }
        if let first = valid.min() { return Date(timeIntervalSince1970: TimeInterval(first)) }

        // The time falls in a gap: find the second at which the offset changes.
        var lo = local - 86_400, hi = local + 86_400
        if offset(lo) == offset(hi) { return Date(timeIntervalSince1970: TimeInterval(local - before)) }   // cannot happen; stay total
        let startOffset = offset(lo)
        while hi - lo > 1 {
            let mid = lo + (hi - lo) / 2
            if offset(mid) == startOffset { lo = mid } else { hi = mid }
        }
        return Date(timeIntervalSince1970: TimeInterval(hi))
    }
}

public struct DueOccurrence: Sendable, Equatable {
    public var event: ScheduledEvent
    public var occurrence: Date
    public var actions: [CueAction] { event.cueActions }
}

public struct SkippedOccurrence: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// Seconds between the scheduled time and the moment it was noticed.
        case missed(by: TimeInterval)
        /// A later occurrence of the same event was also due and fired instead.
        case supersededByLater
    }

    public var eventID: UUID
    public var eventName: String
    public var occurrence: Date
    public var reason: Reason
    /// Zone used to show the time in `message`.
    var displayZoneID: String

    public var message: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: displayZoneID) ?? .gmt
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let when = f.string(from: occurrence)
        switch reason {
        case .missed(let late):
            let minutes = Int(late / 60)
            let by = minutes >= 1 ? "\(minutes) min" : "\(Int(late)) s"
            return "\u{201C}\(eventName)\u{201D} (\(when)) was missed by \(by) and was not run."
        case .supersededByLater:
            return "\u{201C}\(eventName)\u{201D} (\(when)) was skipped because a later run of it was also due."
        }
    }
}

public struct ScheduleDue: Sendable, Equatable {
    /// Oldest first; events with the same time in list order.
    public var fire: [DueOccurrence]
    public var skipped: [SkippedOccurrence]
    public init(fire: [DueOccurrence] = [], skipped: [SkippedOccurrence] = []) {
        self.fire = fire
        self.skipped = skipped
    }
}

/// CUE-002a: what the engine remembers between runs, apart from its events: the grace period, the last occurrence
/// handled per event, and the latest check. The store keeps the events one per row and this in a single row.
public struct ScheduleEngineState: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var gracePeriod: TimeInterval
    public var lastHandled: [UUID: Date]
    public var lastCheckedAt: Date?

    public init(gracePeriod: TimeInterval = ScheduleEngine.defaultGracePeriod, lastHandled: [UUID: Date] = [:], lastCheckedAt: Date? = nil) {
        self.gracePeriod = gracePeriod
        self.lastHandled = lastHandled
        self.lastCheckedAt = lastCheckedAt
    }

    private struct Handled: Codable { var event: UUID; var at: Date }
    private enum CodingKeys: String, CodingKey { case version, gracePeriod, lastHandled, lastCheckedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gracePeriod = try c.decodeIfPresent(TimeInterval.self, forKey: .gracePeriod) ?? ScheduleEngine.defaultGracePeriod
        let entries = try c.decodeIfPresent([Handled].self, forKey: .lastHandled) ?? []
        lastHandled = Dictionary(entries.map { ($0.event, $0.at) }, uniquingKeysWith: { a, b in max(a, b) })
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(gracePeriod, forKey: .gracePeriod)
        // A dictionary keyed by UUID would be written as a flat array; a list of entries in a fixed order reads better.
        try c.encode(lastHandled.sorted { $0.key.uuidString < $1.key.uuidString }.map { Handled(event: $0.key, at: $0.value) }, forKey: .lastHandled)
        try c.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
    }
}

public struct ScheduleEngine: Sendable, Equatable, Codable {
    public static let defaultGracePeriod: TimeInterval = 300
    /// CUE-002a: the stored format version of the whole engine. A missing version reads as 1.
    public static let currentVersion = 1

    public var events: [ScheduledEvent]
    public var gracePeriod: TimeInterval
    /// Per event, the last occurrence that was fired or reported as skipped. Nothing at or before it is looked at again.
    public private(set) var lastHandled: [UUID: Date]
    /// The latest `upTo` seen. Saved with the engine so a relaunch can look at the time the app was closed.
    public private(set) var lastCheckedAt: Date?

    public init(events: [ScheduledEvent] = [], gracePeriod: TimeInterval = ScheduleEngine.defaultGracePeriod) {
        self.events = events
        self.gracePeriod = gracePeriod
        self.lastHandled = [:]
        self.lastCheckedAt = nil
    }

    /// An engine restored from storage: the events and what was remembered about them.
    public init(events: [ScheduledEvent], state: ScheduleEngineState) {
        self.events = events
        self.gracePeriod = state.gracePeriod
        self.lastHandled = state.lastHandled
        self.lastCheckedAt = state.lastCheckedAt
    }

    /// Everything the engine remembers besides its events.
    public var state: ScheduleEngineState {
        ScheduleEngineState(gracePeriod: gracePeriod, lastHandled: lastHandled, lastCheckedAt: lastCheckedAt)
    }

    private enum CodingKeys: String, CodingKey { case version, events, state }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let events = try c.decodeIfPresent([ScheduledEvent].self, forKey: .events) ?? []
        let state = try c.decodeIfPresent(ScheduleEngineState.self, forKey: .state) ?? ScheduleEngineState()
        self.init(events: events, state: state)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(events, forKey: .events)
        try c.encode(state, forKey: .state)
    }

    /// Events that cannot work as they are, with operator-readable reasons.
    public func problems() -> [UUID: [String]] {
        var out: [UUID: [String]] = [:]
        for e in events {
            let issues = e.validationIssues
            if !issues.isEmpty { out[e.id] = issues }
        }
        return out
    }

    /// Switching an event on restarts it from `now`, so times that passed while it was off do not fire.
    public mutating func setEnabled(_ enabled: Bool, for id: UUID, now: Date) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        if enabled && !events[i].isEnabled { events[i].activeFrom = now }
        events[i].isEnabled = enabled
    }

    /// The events to run for the window (after, upTo], and the ones skipped. Call it from a timer, and again on wake.
    public mutating func due(after: Date, upTo: Date, calendar: Calendar) -> ScheduleDue {
        lastCheckedAt = max(lastCheckedAt ?? upTo, upTo)
        guard after < upTo else { return ScheduleDue() }

        var fire: [(index: Int, due: DueOccurrence)] = []
        var skipped: [(index: Int, item: SkippedOccurrence)] = []

        for (index, event) in events.enumerated() where event.isEnabled {
            let from = max(after, lastHandled[event.id] ?? .distantPast)
            let occurrences = event.occurrences(after: from, upTo: upTo, calendar: calendar)
            guard let newest = occurrences.last else { continue }
            lastHandled[event.id] = newest

            let zone: String
            if case .weekly(_, _, _, let tz) = event.timing { zone = tz } else { zone = calendar.timeZone.identifier }
            let eligible = occurrences.filter { upTo.timeIntervalSince($0) < gracePeriod }
            for o in occurrences {
                if o == eligible.last {
                    fire.append((index, DueOccurrence(event: event, occurrence: o)))
                } else {
                    let reason: SkippedOccurrence.Reason = eligible.contains(o) ? .supersededByLater : .missed(by: upTo.timeIntervalSince(o))
                    skipped.append((index, SkippedOccurrence(eventID: event.id, eventName: event.name, occurrence: o, reason: reason, displayZoneID: zone)))
                }
            }
        }

        func order<T>(_ a: (index: Int, T), _ b: (index: Int, T), _ ta: Date, _ tb: Date) -> Bool {
            ta != tb ? ta < tb : a.index < b.index
        }
        fire.sort { order($0, $1, $0.due.occurrence, $1.due.occurrence) }
        skipped.sort { order($0, $1, $0.item.occurrence, $1.item.occurrence) }
        return ScheduleDue(fire: fire.map(\.due), skipped: skipped.map(\.item))
    }

    /// `due` for the time since the last check. The first call only records the baseline.
    public mutating func poll(now: Date, calendar: Calendar) -> ScheduleDue {
        guard let last = lastCheckedAt else {
            lastCheckedAt = now
            return ScheduleDue()
        }
        return due(after: last, upTo: now, calendar: calendar)
    }
}
