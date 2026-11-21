// CUE-001 (AUTO-12): calendar scheduling, sleep and wake, daylight saving. Every expected instant below was worked out
// independently of the implementation (Python zoneinfo and the `date` tool) and is written as UTC.
import Testing
import Foundation
@testable import CueEngine

private func at(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    guard let d = f.date(from: iso) else {
        Issue.record("bad test date \(iso)")
        return .distantPast
    }
    return d
}

private func calendar(_ tz: String = "UTC", _ id: Calendar.Identifier = .gregorian) -> Calendar {
    var c = Calendar(identifier: id)
    c.timeZone = TimeZone(identifier: tz) ?? .gmt
    return c
}

private let ping = CueAction.selectLook(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID())

private func weekly(_ days: Set<Weekday>, _ hour: Int, _ minute: Int, _ tz: String,
                    name: String = "Event", enabled: Bool = true, activeFrom: Date = .distantPast, id: UUID = UUID()) -> ScheduledEvent {
    ScheduledEvent(id: id, name: name, isEnabled: enabled,
                   timing: .weekly(weekdays: days, hour: hour, minute: minute, timeZoneID: tz),
                   payload: .actions([ping]), activeFrom: activeFrom)
}

// MARK: occurrences (pure)

@Suite struct ScheduleOccurrenceTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var days: Set<Weekday>
        var hour: Int
        var minute: Int
        var tz: String
        var after: String
        var upTo: String
        var expected: [String]
        var testDescription: String { name }
    }

    static let every = Set(Weekday.allCases)

    static let table: [Case] = [
        Case(name: "New York daily 10:30 across spring forward keeps 10:30 local",
             days: every, hour: 10, minute: 30, tz: "America/New_York",
             after: "2026-03-07T12:00:00Z", upTo: "2026-03-10T15:00:00Z",
             expected: ["2026-03-07T15:30:00Z", "2026-03-08T14:30:00Z", "2026-03-09T14:30:00Z", "2026-03-10T14:30:00Z"]),
        Case(name: "New York Sundays 10:30 across spring forward",
             days: [.sunday], hour: 10, minute: 30, tz: "America/New_York",
             after: "2026-02-28T00:00:00Z", upTo: "2026-03-16T00:00:00Z",
             expected: ["2026-03-01T15:30:00Z", "2026-03-08T14:30:00Z", "2026-03-15T14:30:00Z"]),
        Case(name: "New York 10:30 across fall back keeps 10:30 local",
             days: [.saturday, .sunday, .monday], hour: 10, minute: 30, tz: "America/New_York",
             after: "2026-10-30T00:00:00Z", upTo: "2026-11-03T00:00:00Z",
             expected: ["2026-10-31T14:30:00Z", "2026-11-01T15:30:00Z", "2026-11-02T15:30:00Z"]),
        Case(name: "New York 02:30 does not exist on spring-forward day: fires at 03:00, the next valid minute",
             days: every, hour: 2, minute: 30, tz: "America/New_York",
             after: "2026-03-07T00:00:00Z", upTo: "2026-03-10T00:00:00Z",
             expected: ["2026-03-07T07:30:00Z", "2026-03-08T07:00:00Z", "2026-03-09T06:30:00Z"]),
        Case(name: "New York 02:59 on spring-forward day also fires at 03:00",
             days: [.sunday], hour: 2, minute: 59, tz: "America/New_York",
             after: "2026-03-08T00:00:00Z", upTo: "2026-03-09T00:00:00Z",
             expected: ["2026-03-08T07:00:00Z"]),
        Case(name: "New York 03:00 on spring-forward day is the first valid minute itself",
             days: [.sunday], hour: 3, minute: 0, tz: "America/New_York",
             after: "2026-03-08T00:00:00Z", upTo: "2026-03-09T00:00:00Z",
             expected: ["2026-03-08T07:00:00Z"]),
        Case(name: "New York 01:30 occurs twice on fall-back day: fires once, at the first",
             days: every, hour: 1, minute: 30, tz: "America/New_York",
             after: "2026-10-31T00:00:00Z", upTo: "2026-11-03T00:00:00Z",
             expected: ["2026-10-31T05:30:00Z", "2026-11-01T05:30:00Z", "2026-11-02T06:30:00Z"]),
        Case(name: "London 01:30 does not exist on 29 March: fires at 02:00 BST",
             days: every, hour: 1, minute: 30, tz: "Europe/London",
             after: "2026-03-28T00:00:00Z", upTo: "2026-03-30T00:00:00Z",
             expected: ["2026-03-28T01:30:00Z", "2026-03-29T01:00:00Z"]),
        Case(name: "London 01:30 occurs twice on 25 October: fires once, at the first",
             days: [.sunday], hour: 1, minute: 30, tz: "Europe/London",
             after: "2026-10-24T00:00:00Z", upTo: "2026-10-27T00:00:00Z",
             expected: ["2026-10-25T00:30:00Z"]),
        Case(name: "Lord Howe moves its clock by 30 minutes: 02:15 on 4 October fires at 02:30 local",
             days: every, hour: 2, minute: 15, tz: "Australia/Lord_Howe",
             after: "2026-10-02T00:00:00Z", upTo: "2026-10-05T00:00:00Z",
             expected: ["2026-10-02T15:45:00Z", "2026-10-03T15:30:00Z", "2026-10-04T15:15:00Z"]),
        Case(name: "Kolkata has no daylight saving: Monday 10:30 is 05:00 UTC",
             days: [.monday], hour: 10, minute: 30, tz: "Asia/Kolkata",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-03T00:00:00Z",
             expected: ["2026-03-02T05:00:00Z"]),
        Case(name: "weekday follows the event's zone: Monday 00:30 in Auckland is still Sunday in UTC",
             days: [.monday], hour: 0, minute: 30, tz: "Pacific/Auckland",
             after: "2026-07-05T00:00:00Z", upTo: "2026-07-06T00:00:00Z",
             expected: ["2026-07-05T12:30:00Z"]),
        Case(name: "weekday follows the event's zone: Sunday 23:30 in Pago Pago is Monday in UTC",
             days: [.sunday], hour: 23, minute: 30, tz: "Pacific/Pago_Pago",
             after: "2026-03-01T12:00:00Z", upTo: "2026-03-03T00:00:00Z",
             expected: ["2026-03-02T10:30:00Z"]),
        Case(name: "Monday Wednesday Friday",
             days: [.monday, .wednesday, .friday], hour: 9, minute: 0, tz: "UTC",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-08T00:00:00Z",
             expected: ["2026-03-02T09:00:00Z", "2026-03-04T09:00:00Z", "2026-03-06T09:00:00Z"]),
        Case(name: "year boundary",
             days: every, hour: 0, minute: 0, tz: "UTC",
             after: "2026-12-30T12:00:00Z", upTo: "2027-01-02T00:00:00Z",
             expected: ["2026-12-31T00:00:00Z", "2027-01-01T00:00:00Z", "2027-01-02T00:00:00Z"]),
        Case(name: "leap day",
             days: every, hour: 12, minute: 0, tz: "UTC",
             after: "2028-02-28T00:00:00Z", upTo: "2028-03-01T13:00:00Z",
             expected: ["2028-02-28T12:00:00Z", "2028-02-29T12:00:00Z", "2028-03-01T12:00:00Z"]),
        Case(name: "after is exclusive and upTo is inclusive",
             days: every, hour: 9, minute: 0, tz: "UTC",
             after: "2026-03-02T09:00:00Z", upTo: "2026-03-04T09:00:00Z",
             expected: ["2026-03-03T09:00:00Z", "2026-03-04T09:00:00Z"]),
        Case(name: "no weekdays chosen", days: [], hour: 9, minute: 0, tz: "UTC",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-08T00:00:00Z", expected: []),
        Case(name: "unknown time zone", days: every, hour: 9, minute: 0, tz: "Mars/Olympus",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-08T00:00:00Z", expected: []),
        Case(name: "hour out of range", days: every, hour: 24, minute: 0, tz: "UTC",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-08T00:00:00Z", expected: []),
        Case(name: "minute out of range", days: every, hour: 9, minute: 60, tz: "UTC",
             after: "2026-03-01T00:00:00Z", upTo: "2026-03-08T00:00:00Z", expected: []),
        Case(name: "empty window", days: every, hour: 9, minute: 0, tz: "UTC",
             after: "2026-03-02T09:00:00Z", upTo: "2026-03-02T09:00:00Z", expected: []),
        Case(name: "backwards window", days: every, hour: 9, minute: 0, tz: "UTC",
             after: "2026-03-05T00:00:00Z", upTo: "2026-03-01T00:00:00Z", expected: []),
    ]

    @Test(arguments: table) func occurrences(_ c: Case) {
        let e = weekly(c.days, c.hour, c.minute, c.tz)
        let got = e.occurrences(after: at(c.after), upTo: at(c.upTo), calendar: calendar())
        #expect(got == c.expected.map(at))
    }

    @Test func theCallersCalendarZoneAndKindDoNotChangeTheResult() {
        let e = weekly(Self.every, 10, 30, "America/New_York")
        let expected = e.occurrences(after: at("2026-03-07T12:00:00Z"), upTo: at("2026-03-10T15:00:00Z"), calendar: calendar())
        #expect(expected.count == 4)
        for cal in [calendar("America/Los_Angeles"), calendar("Pacific/Kiritimati"), calendar("UTC", .buddhist), calendar("UTC", .iso8601)] {
            #expect(e.occurrences(after: at("2026-03-07T12:00:00Z"), upTo: at("2026-03-10T15:00:00Z"), calendar: cal) == expected)
        }
    }

    @Test func oneOffEventsFireOnceInsideTheWindow() {
        let e = ScheduledEvent(id: UUID(), name: "Once", isEnabled: true, timing: .once(at("2026-03-02T09:00:00Z")), payload: .actions([ping]))
        #expect(e.occurrences(after: at("2026-03-02T08:00:00Z"), upTo: at("2026-03-02T09:00:00Z"), calendar: calendar()) == [at("2026-03-02T09:00:00Z")])
        #expect(e.occurrences(after: at("2026-03-02T09:00:00Z"), upTo: at("2026-03-02T10:00:00Z"), calendar: calendar()).isEmpty)
        #expect(e.occurrences(after: at("2026-03-02T09:00:01Z"), upTo: at("2026-03-09T00:00:00Z"), calendar: calendar()).isEmpty)
        #expect(e.occurrences(after: at("2026-03-01T00:00:00Z"), upTo: at("2026-03-02T08:59:59Z"), calendar: calendar()).isEmpty)
    }

    @Test func occurrencesAtOrBeforeActiveFromAreIgnored() {
        let e = weekly(Self.every, 9, 0, "UTC", activeFrom: at("2026-03-03T09:00:00Z"))
        let got = e.occurrences(after: at("2026-03-01T00:00:00Z"), upTo: at("2026-03-05T00:00:00Z"), calendar: calendar())
        #expect(got == [at("2026-03-04T09:00:00Z")])
    }

    @Test func validationNamesWhatIsWrong() {
        #expect(weekly(Self.every, 9, 0, "UTC").validationIssues.isEmpty)
        #expect(weekly([], 9, 0, "UTC").validationIssues == ["Choose at least one weekday."])
        #expect(weekly(Self.every, 24, 0, "UTC").validationIssues == ["The hour must be 0 to 23."])
        #expect(weekly(Self.every, 9, 60, "UTC").validationIssues == ["The minute must be 0 to 59."])
        #expect(weekly(Self.every, 9, 0, "Mars/Olympus").validationIssues == ["Unknown time zone \u{201C}Mars/Olympus\u{201D}."])
        #expect(ScheduledEvent(id: UUID(), name: "x", isEnabled: true, timing: .once(.now), payload: .actions([])).validationIssues == ["The event has no actions."])
        #expect(ScheduledEvent(id: UUID(), name: " ", isEnabled: true, timing: .once(.now), payload: .macro(UUID())).validationIssues == ["The event needs a name."])
    }

    @Test func aMacroPayloadBecomesARunMacroAction() {
        let id = UUID()
        let e = ScheduledEvent(id: UUID(), name: "M", isEnabled: true, timing: .once(.now), payload: .macro(id))
        #expect(e.cueActions == [.runMacro(id)])
        #expect(weekly([.monday], 9, 0, "UTC").cueActions == [ping])
    }
}

// MARK: engine

@Suite struct ScheduleEngineTests {
    private let cal = calendar()
    private let sunday = UUID()

    private func sundayService(tz: String = "America/New_York") -> ScheduledEvent {
        weekly([.sunday], 10, 30, tz, name: "Sunday service", id: sunday)
    }

    @Test func anEventFiresWhenItsTimeIsReached() {
        var engine = ScheduleEngine(events: [sundayService()])
        // 8 March 2026 10:30 EDT = 14:30 UTC (the day clocks went forward).
        #expect(engine.due(after: at("2026-03-08T14:28:00Z"), upTo: at("2026-03-08T14:29:59Z"), calendar: cal).fire.isEmpty)
        let due = engine.due(after: at("2026-03-08T14:29:59Z"), upTo: at("2026-03-08T14:30:00Z"), calendar: cal)
        #expect(due.fire.map(\.occurrence) == [at("2026-03-08T14:30:00Z")])
        #expect(due.fire.first?.event.id == sunday)
        #expect(due.fire.first?.actions == [ping])
        #expect(due.skipped.isEmpty)
    }

    @Test func theSameOccurrenceNeverFiresTwiceAcrossRepeatedAndOverlappingWindows() {
        var engine = ScheduleEngine(events: [sundayService()])
        #expect(engine.due(after: at("2026-03-08T14:29:00Z"), upTo: at("2026-03-08T14:30:30Z"), calendar: cal).fire.count == 1)
        #expect(engine.due(after: at("2026-03-08T14:29:00Z"), upTo: at("2026-03-08T14:30:30Z"), calendar: cal).fire.isEmpty)   // identical window
        #expect(engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:31:00Z"), calendar: cal).fire.isEmpty)   // overlapping
        #expect(engine.due(after: at("2026-03-08T14:30:00Z"), upTo: at("2026-03-08T14:35:00Z"), calendar: cal).fire.isEmpty)   // adjacent
        #expect(engine.due(after: at("2026-03-01T00:00:00Z"), upTo: at("2026-03-08T14:31:00Z"), calendar: cal).fire.isEmpty)   // wide, from before
    }

    @Test func aMissedEventWithinTheGracePeriodFiresOnceOnWake() {
        var engine = ScheduleEngine(events: [sundayService()])
        // Slept from 14:00 to 14:33 UTC: three minutes late.
        let due = engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:33:00Z"), calendar: cal)
        #expect(due.fire.map(\.occurrence) == [at("2026-03-08T14:30:00Z")])
        #expect(due.skipped.isEmpty)
        #expect(engine.due(after: at("2026-03-08T14:33:00Z"), upTo: at("2026-03-08T14:34:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func aMissedEventBeyondTheGracePeriodIsSkippedAndReportedNeverFiredLate() {
        var engine = ScheduleEngine(events: [sundayService()])
        let due = engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:40:00Z"), calendar: cal)
        #expect(due.fire.isEmpty)
        #expect(due.skipped.count == 1)
        let s = due.skipped[0]
        #expect(s.eventID == sunday && s.occurrence == at("2026-03-08T14:30:00Z"))
        #expect(s.reason == .missed(by: 600))
        #expect(s.message.contains("Sunday service") && s.message.contains("missed"))
        #expect(s.message.contains("2026-03-08 10:30"))           // shown in the event's own zone
        // It is reported once, not on every later check.
        #expect(engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:41:00Z"), calendar: cal).skipped.isEmpty)
    }

    @Test(arguments: [
        (298.0, true), (299.0, true), (299.9, true), (300.0, false), (301.0, false),
    ]) func theGraceBoundaryIsLessThanFiveMinutes(_ late: Double, _ fires: Bool) {
        var engine = ScheduleEngine(events: [sundayService()])
        let due = engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:30:00Z").addingTimeInterval(late), calendar: cal)
        #expect(due.fire.count == (fires ? 1 : 0))
        #expect(due.skipped.count == (fires ? 0 : 1))
        #expect(ScheduleEngine.defaultGracePeriod == 300)
        #expect(engine.gracePeriod == 300)
    }

    @Test func theGracePeriodCanBeChanged() {
        var engine = ScheduleEngine(events: [sundayService()], gracePeriod: 60)
        #expect(engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:32:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func aWeekOfSleepDoesNotReleaseABurstOfOldEvents() {
        let daily = weekly(Set(Weekday.allCases), 9, 0, "UTC", name: "Daily", id: UUID())
        var engine = ScheduleEngine(events: [daily])
        let due = engine.due(after: at("2026-03-01T00:00:00Z"), upTo: at("2026-03-08T12:00:00Z"), calendar: cal)
        #expect(due.fire.isEmpty)
        #expect(due.skipped.count == 8)
        #expect(due.skipped.map(\.occurrence) == (1...8).map { at("2026-03-0\($0)T09:00:00Z") })
    }

    @Test func aLongGraceFiresOnlyTheLatestOccurrenceOfOneEvent() {
        let daily = weekly(Set(Weekday.allCases), 9, 0, "UTC", name: "Daily", id: UUID())
        var engine = ScheduleEngine(events: [daily], gracePeriod: 5 * 86400)
        let due = engine.due(after: at("2026-03-01T00:00:00Z"), upTo: at("2026-03-04T12:00:00Z"), calendar: cal)
        #expect(due.fire.map(\.occurrence) == [at("2026-03-04T09:00:00Z")])
        #expect(due.skipped.map(\.reason) == [.supersededByLater, .supersededByLater, .supersededByLater])
        #expect(due.skipped.map(\.occurrence) == [at("2026-03-01T09:00:00Z"), at("2026-03-02T09:00:00Z"), at("2026-03-03T09:00:00Z")])
    }

    @Test func dueEventsComeBackInChronologicalOrderThenListOrder() {
        let a = weekly([.sunday], 10, 31, "UTC", name: "A")
        let b = weekly([.sunday], 10, 30, "UTC", name: "B")
        let c = weekly([.sunday], 10, 31, "UTC", name: "C")
        var engine = ScheduleEngine(events: [a, b, c])
        let due = engine.due(after: at("2026-03-08T10:00:00Z"), upTo: at("2026-03-08T10:32:00Z"), calendar: cal)
        #expect(due.fire.map(\.event.name) == ["B", "A", "C"])
    }

    @Test func disabledEventsNeitherFireNorAreReported() {
        var engine = ScheduleEngine(events: [weekly([.sunday], 10, 30, "UTC", enabled: false)])
        let due = engine.due(after: at("2026-03-08T00:00:00Z"), upTo: at("2026-03-08T23:00:00Z"), calendar: cal)
        #expect(due.fire.isEmpty && due.skipped.isEmpty)
    }

    @Test func enablingAnEventDoesNotReleaseOccurrencesFromWhileItWasOff() {
        let id = UUID()
        var engine = ScheduleEngine(events: [weekly([.sunday], 10, 30, "UTC", enabled: false, id: id)])
        engine.setEnabled(true, for: id, now: at("2026-03-08T10:31:00Z"))
        #expect(engine.events[0].isEnabled)
        #expect(engine.due(after: at("2026-03-08T10:00:00Z"), upTo: at("2026-03-08T10:32:00Z"), calendar: cal).fire.isEmpty)
        #expect(engine.due(after: at("2026-03-08T10:32:00Z"), upTo: at("2026-03-15T10:30:00Z"), calendar: cal).fire.count == 1)
        engine.setEnabled(false, for: id, now: at("2026-03-15T11:00:00Z"))
        #expect(!engine.events[0].isEnabled)
        engine.setEnabled(true, for: UUID(), now: .now)    // unknown id: no effect, no crash
    }

    @Test func aNewEventDoesNotFireForATimeEarlierThanItsCreation() {
        let e = weekly([.sunday], 10, 30, "UTC", activeFrom: at("2026-03-08T10:31:00Z"))
        var engine = ScheduleEngine(events: [e])
        #expect(engine.due(after: at("2026-03-08T10:00:00Z"), upTo: at("2026-03-08T10:32:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func oneOffEventsFireOnceAndAreRemembered() {
        let e = ScheduledEvent(id: UUID(), name: "Once", isEnabled: true, timing: .once(at("2026-03-02T09:00:00Z")), payload: .actions([ping]))
        var engine = ScheduleEngine(events: [e])
        #expect(engine.due(after: at("2026-03-02T08:00:00Z"), upTo: at("2026-03-02T09:01:00Z"), calendar: cal).fire.count == 1)
        #expect(engine.due(after: at("2026-03-02T08:00:00Z"), upTo: at("2026-03-02T09:02:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func theClockGoingBackwardNeitherFiresNorForgets() {
        var engine = ScheduleEngine(events: [sundayService()])
        #expect(engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:31:00Z"), calendar: cal).fire.count == 1)
        #expect(engine.due(after: at("2026-03-08T14:31:00Z"), upTo: at("2026-03-08T13:00:00Z"), calendar: cal).fire.isEmpty)   // backwards
        // Time set back by an hour and the same minute reached again: still once.
        #expect(engine.due(after: at("2026-03-08T13:59:00Z"), upTo: at("2026-03-08T14:31:00Z"), calendar: cal).fire.isEmpty)
        #expect(engine.lastCheckedAt == at("2026-03-08T14:31:00Z"))
    }

    @Test func stateSurvivesEncodingSoARelaunchDoesNotRefire() throws {
        var engine = ScheduleEngine(events: [sundayService()])
        #expect(engine.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:31:00Z"), calendar: cal).fire.count == 1)
        let data = try JSONEncoder().encode(engine)
        var restored = try JSONDecoder().decode(ScheduleEngine.self, from: data)
        #expect(restored == engine)
        #expect(restored.due(after: at("2026-03-08T14:00:00Z"), upTo: at("2026-03-08T14:40:00Z"), calendar: cal).fire.isEmpty)
        #expect(restored.lastHandled[sunday] == at("2026-03-08T14:30:00Z"))
    }

    @Test func pollUsesTheLastCheckedInstantSoARelaunchAfterTheAppWasClosedCatchesUp() throws {
        var engine = ScheduleEngine(events: [sundayService()])
        #expect(engine.poll(now: at("2026-03-08T13:00:00Z"), calendar: cal) == ScheduleDue())     // first poll only sets the baseline
        #expect(engine.lastCheckedAt == at("2026-03-08T13:00:00Z"))
        // App quit at 13:00 and relaunched at 14:32.
        let data = try JSONEncoder().encode(engine)
        var relaunched = try JSONDecoder().decode(ScheduleEngine.self, from: data)
        let due = relaunched.poll(now: at("2026-03-08T14:32:00Z"), calendar: cal)
        #expect(due.fire.map(\.occurrence) == [at("2026-03-08T14:30:00Z")])
    }

    @Test func problemsListsInvalidEventsByIdAndInvalidEventsNeverFire() {
        let bad = weekly([.sunday], 10, 30, "Mars/Olympus", id: UUID())
        let good = sundayService()
        var engine = ScheduleEngine(events: [bad, good])
        #expect(engine.problems() == [bad.id: ["Unknown time zone \u{201C}Mars/Olympus\u{201D}."]])
        #expect(engine.due(after: at("2026-03-08T00:00:00Z"), upTo: at("2026-03-09T00:00:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func eventsFireForTheirOwnZoneWhateverTheCallersCalendarIs() {
        var engine = ScheduleEngine(events: [sundayService(tz: "Asia/Kolkata")])
        let la = calendar("America/Los_Angeles")
        // Sunday 8 March 10:30 IST is 05:00 UTC.
        let due = engine.due(after: at("2026-03-08T04:59:00Z"), upTo: at("2026-03-08T05:00:00Z"), calendar: la)
        #expect(due.fire.map(\.occurrence) == [at("2026-03-08T05:00:00Z")])
    }
}

// MARK: end to end, one check a minute across each daylight-saving change

@Suite struct ScheduleDaylightSavingSimulationTests {
    /// Polls once a minute from `start` to `end` like the app would and returns the instants at which the event fired.
    private func simulate(_ event: ScheduledEvent, from start: String, to end: String) -> [Date] {
        var engine = ScheduleEngine(events: [event])
        var now = at(start)
        _ = engine.poll(now: now, calendar: calendar())
        var fired: [Date] = []
        while now < at(end) {
            now = now.addingTimeInterval(60)
            let due = engine.poll(now: now, calendar: calendar())
            #expect(due.skipped.isEmpty)
            fired.append(contentsOf: due.fire.map(\.occurrence))
        }
        return fired
    }

    @Test func newYorkTenThirtyFiresOncePerDayAcrossSpringForward() {
        let fired = simulate(weekly(Set(Weekday.allCases), 10, 30, "America/New_York"), from: "2026-03-06T00:00:00Z", to: "2026-03-11T00:00:00Z")
        #expect(fired == ["2026-03-06T15:30:00Z", "2026-03-07T15:30:00Z", "2026-03-08T14:30:00Z", "2026-03-09T14:30:00Z", "2026-03-10T14:30:00Z"].map(at))
    }

    @Test func newYorkTwoThirtyFiresOnceAtThreeOnSpringForwardDay() {
        let fired = simulate(weekly(Set(Weekday.allCases), 2, 30, "America/New_York"), from: "2026-03-06T12:00:00Z", to: "2026-03-10T12:00:00Z")
        #expect(fired == ["2026-03-07T07:30:00Z", "2026-03-08T07:00:00Z", "2026-03-09T06:30:00Z", "2026-03-10T06:30:00Z"].map(at))
    }

    @Test func newYorkOneThirtyFiresOnceOnFallBackDay() {
        let fired = simulate(weekly(Set(Weekday.allCases), 1, 30, "America/New_York"), from: "2026-10-30T12:00:00Z", to: "2026-11-03T12:00:00Z")
        #expect(fired == ["2026-10-31T05:30:00Z", "2026-11-01T05:30:00Z", "2026-11-02T06:30:00Z", "2026-11-03T06:30:00Z"].map(at))
    }

    @Test func londonOneThirtyAcrossBothChanges() {
        let spring = simulate(weekly(Set(Weekday.allCases), 1, 30, "Europe/London"), from: "2026-03-27T12:00:00Z", to: "2026-03-31T12:00:00Z")
        #expect(spring == ["2026-03-28T01:30:00Z", "2026-03-29T01:00:00Z", "2026-03-30T00:30:00Z", "2026-03-31T00:30:00Z"].map(at))
        let autumn = simulate(weekly(Set(Weekday.allCases), 1, 30, "Europe/London"), from: "2026-10-23T12:00:00Z", to: "2026-10-27T12:00:00Z")
        #expect(autumn == ["2026-10-24T00:30:00Z", "2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z", "2026-10-27T01:30:00Z"].map(at))
    }

    @Test func lordHoweHalfHourShift() {
        let fired = simulate(weekly(Set(Weekday.allCases), 2, 15, "Australia/Lord_Howe"), from: "2026-10-01T12:00:00Z", to: "2026-10-05T12:00:00Z")
        #expect(fired == ["2026-10-01T15:45:00Z", "2026-10-02T15:45:00Z", "2026-10-03T15:30:00Z", "2026-10-04T15:15:00Z"].map(at))
    }

    @Test func sleepingThroughTheSpringForwardGapStillFiresTheEventOnce() {
        var engine = ScheduleEngine(events: [weekly([.sunday], 2, 30, "America/New_York")])
        let due = engine.due(after: at("2026-03-08T06:00:00Z"), upTo: at("2026-03-08T07:02:00Z"), calendar: calendar())
        #expect(due.fire.map(\.occurrence) == [at("2026-03-08T07:00:00Z")])
    }

    @Test func slumberingThroughBothFallBackHoursFiresOnce() {
        var engine = ScheduleEngine(events: [weekly([.sunday], 1, 30, "America/New_York")], gracePeriod: 3 * 3600)
        // Asleep from 05:00 UTC; wakes at 06:45 UTC, which is 01:45 EST (the second pass through 01:30).
        let due = engine.due(after: at("2026-11-01T05:00:00Z"), upTo: at("2026-11-01T06:45:00Z"), calendar: calendar())
        #expect(due.fire.map(\.occurrence) == [at("2026-11-01T05:30:00Z")])
        #expect(due.skipped.isEmpty)
    }
}
