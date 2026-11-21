// CUE-002b item 6: the schedule editor's draft. What the operator types becomes an event only when the engine would accept it.
import Testing
import Foundation
import CueEngine
@testable import OperatorCore

@Suite struct CUE002b_ScheduleDraftTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func aWeeklyDraftBuildsAnEventThatWorks() {
        let macro = UUID()
        var draft = ScheduleDraft(timeZoneID: "UTC")
        draft.name = "  Doors  "
        draft.repeats = .weekly
        draft.weekdays = [.sunday, .wednesday]
        draft.hour = 9; draft.minute = 0
        draft.macroID = macro
        let event = draft.build()
        #expect(event?.name == "Doors")
        #expect(event?.timing == .weekly(weekdays: [.sunday, .wednesday], hour: 9, minute: 0, timeZoneID: "UTC"))
        #expect(event?.payload == .macro(macro))
        #expect(event?.validationIssues.isEmpty == true)
    }

    @Test func aDraftThatCannotWorkExplainsWhy() {
        var draft = ScheduleDraft(timeZoneID: "UTC")
        #expect(draft.problems.contains("The event needs a name."))
        draft.name = "X"
        draft.repeats = .weekly
        draft.weekdays = []
        draft.macroID = UUID()
        #expect(draft.problems == ["Choose at least one weekday."])
        #expect(draft.build() == nil)
        draft.weekdays = [.monday]
        draft.macroID = nil
        #expect(draft.problems == ["Choose a macro to run."])
    }

    @Test func aOnceDraftUsesTheChosenInstant() {
        let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var draft = ScheduleDraft(timeZoneID: "UTC")
        draft.name = "Once"; draft.repeats = .once; draft.date = when; draft.macroID = UUID()
        #expect(draft.build()?.timing == .once(when))
    }

    @Test func editingAnExistingEventKeepsItsIdentityAndAnActionsPayload() {
        let id = UUID()
        let existing = ScheduledEvent(id: id, name: "Old", isEnabled: false, timing: .weekly(weekdays: [.friday], hour: 18, minute: 30, timeZoneID: "UTC"),
                                      payload: .actions([.stopForeground]))
        var draft = ScheduleDraft(event: existing)
        #expect(draft.repeats == .weekly && draft.hour == 18 && draft.minute == 30 && draft.weekdays == [.friday])
        #expect(draft.macroID == nil && draft.keepsActions)
        draft.name = "New"
        let built = draft.build()
        #expect(built?.id == id && built?.name == "New" && built?.isEnabled == false)
        #expect(built?.payload == .actions([.stopForeground]))
    }

    @Test func timingReadsInWords() {
        let weekly = ScheduledEvent.Timing.weekly(weekdays: [.sunday, .wednesday], hour: 9, minute: 5, timeZoneID: "UTC")
        #expect(ScheduleText.timing(weekly, calendar: utc) == "Sun, Wed 09:05")
        let daily = ScheduledEvent.Timing.weekly(weekdays: Set(Weekday.allCases), hour: 18, minute: 0, timeZoneID: "UTC")
        #expect(ScheduleText.timing(daily, calendar: utc) == "Every day 18:00")
        let date = utc.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 9, minute: 0))!
        #expect(ScheduleText.timing(.once(date), calendar: utc) == "22 Nov 2026 09:00")
        #expect(ScheduleText.next(date, now: date.addingTimeInterval(-3600), calendar: utc) == "today 09:00")
        #expect(ScheduleText.next(date, now: date.addingTimeInterval(-86_400), calendar: utc) == "tomorrow 09:00")
        #expect(ScheduleText.next(date, now: date.addingTimeInterval(-3 * 86_400), calendar: utc) == "Sun 22 Nov 09:00")
    }
}
