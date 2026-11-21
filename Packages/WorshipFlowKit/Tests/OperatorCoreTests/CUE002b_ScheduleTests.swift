// CUE-002b item 3: the schedule is polled with the wall clock (and on wake), its state is saved, missed events are reported,
// and nothing fires while the Hardware Test is running. Fakes and a settable wall clock; no real waiting.
import Testing
import Foundation
import CueEngine
import CueStore
import Persistence
@testable import OperatorCore

final class WallClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
@Suite struct CUE002b_ScheduleTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: h, minute: m, second: s))! }

    struct Rig { var cue: CueModel; var show: FakeShow; var store: CueStore; var wall: WallClock; var library: LibraryStore }

    func rig(start: Date) throws -> Rig {
        let library = try LibraryStore.inMemory()
        let wall = WallClock(start)
        let store = CueStore(library: library, now: { wall.date })
        let show = FakeShow()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock(), wallClock: { wall.date }, calendar: utc)
        return Rig(cue: cue, show: show, store: store, wall: wall, library: library)
    }

    func macroEvent(_ r: Rig, at date: Date) async throws -> ScheduledEvent {
        let macro = Macro(name: "Start", steps: [.transport(.clear)])
        try await r.store.saveMacro(macro)
        return try await r.store.saveScheduledEvent(ScheduledEvent(name: "Doors", timing: .once(date), payload: .macro(macro.id)))
    }

    @Test func anEventFiresOnceWhenItsTimePassesAndItsStateIsSaved() async throws {
        let r = try rig(start: at(8, 59))
        let event = try await macroEvent(r, at: at(9, 0))
        await r.cue.reload()
        r.cue.pollSchedule()                                 // first look: only the baseline
        r.wall.date = at(9, 0, 1)
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.show.log == ["clear"])
        #expect(r.cue.activity.contains { $0.source == .schedule })
        r.wall.date = at(9, 0, 30)
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.show.log == ["clear"])                     // not again
        await r.cue.flushSchedule()
        let saved = try #require(try await r.store.scheduleState())
        #expect(saved.lastHandled[event.id] == at(9, 0))
    }

    @Test func missedWhileTheAppWasClosedIsSkippedAndReportedNotRunLate() async throws {
        let r = try rig(start: at(8, 0))
        let event = try await macroEvent(r, at: at(8, 30))
        try await r.store.saveScheduleState(ScheduleEngineState(lastCheckedAt: at(8, 10)))
        r.wall.date = at(9, 0)                               // the app was closed over 08:30
        await r.cue.reload()
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(r.cue.notices.contains { $0.text.contains("Doors") && $0.text.contains("missed") })
        _ = event
    }

    @Test func wakingFromSleepLooksAtOnceAndReportsWhatWasMissed() async throws {
        let r = try rig(start: at(8, 0))
        _ = try await macroEvent(r, at: at(8, 30))
        await r.cue.reload()
        r.cue.pollSchedule()                                 // baseline 08:00
        r.wall.date = at(10, 0)                              // the Mac slept through it
        r.cue.wakeFromSleep()
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(r.cue.notices.contains { $0.text.contains("missed") })
    }

    @Test func nothingFiresWhileTheHardwareTestRunsAndItIsNotRunLaterEither() async throws {
        let r = try rig(start: at(8, 59))
        _ = try await macroEvent(r, at: at(9, 0))
        await r.cue.reload()
        r.cue.pollSchedule()
        var testing = true
        r.cue.hardwareTestIsRunning = { testing }
        r.wall.date = at(9, 0, 5)
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(r.cue.notices.contains { $0.text.contains("Hardware Test") })
        testing = false
        r.wall.date = at(9, 0, 20)
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.show.log.isEmpty)                          // it was handled, not postponed
    }

    @Test func aSecondOfPollingDoesNotWriteTheDatabaseEverySecond() async throws {
        let r = try rig(start: at(8, 0))
        _ = try await macroEvent(r, at: at(12, 0))
        await r.cue.reload()
        r.cue.pollSchedule()
        await r.cue.flushSchedule()
        let first = try await r.store.scheduleState()?.lastCheckedAt
        r.wall.date = at(8, 0, 1)
        r.cue.pollSchedule()
        await r.cue.flushSchedule()
        #expect(try await r.store.scheduleState()?.lastCheckedAt == first)     // within the save interval: memory only
        r.wall.date = at(8, 1, 30)
        r.cue.pollSchedule()
        await r.cue.flushSchedule()
        #expect(try await r.store.scheduleState()?.lastCheckedAt == at(8, 1, 30))
    }

    @Test func theNextScheduledEventIsTheEarliestEnabledOneAhead() async throws {
        let r = try rig(start: at(8, 0))
        let macro = Macro(name: "Go", steps: [.transport(.clear)])
        try await r.store.saveMacro(macro)
        _ = try await r.store.saveScheduledEvent(ScheduledEvent(name: "Late", timing: .once(at(11, 0)), payload: .macro(macro.id)))
        _ = try await r.store.saveScheduledEvent(ScheduledEvent(name: "Soon", timing: .once(at(9, 0)), payload: .macro(macro.id)))
        let off = try await r.store.saveScheduledEvent(ScheduledEvent(name: "Off", timing: .once(at(8, 30)), payload: .macro(macro.id)))
        _ = try await r.store.setScheduledEvent(id: off.id, enabled: false)
        await r.cue.reload()
        #expect(r.cue.nextScheduledEvent()?.name == "Soon")
        #expect(r.cue.nextScheduledEvent()?.date == at(9, 0))
        r.wall.date = at(9, 30)
        #expect(r.cue.nextScheduledEvent()?.name == "Late")
        r.wall.date = at(12, 0)
        #expect(r.cue.nextScheduledEvent() == nil)
    }

    @Test func editingEventsGoesThroughTheStoreAndKeepsTheEnginesMemory() async throws {
        let r = try rig(start: at(8, 0))
        let macro = Macro(name: "Go", steps: [.transport(.clear)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        await r.cue.saveEvent(ScheduledEvent(name: "One", timing: .once(at(9, 0)), payload: .macro(macro.id)))
        #expect(r.cue.schedule.events.map(\.name) == ["One"])
        let id = try #require(r.cue.schedule.events.first?.id)
        await r.cue.setEventEnabled(false, id: id)
        #expect(r.cue.schedule.events.first?.isEnabled == false)
        await r.cue.saveEvent(ScheduledEvent(name: "", timing: .once(at(9, 0)), payload: .macro(macro.id)))
        #expect(r.cue.lastError != nil)                       // a nameless event cannot work, and says so
        await r.cue.deleteEvent(id)
        #expect(r.cue.schedule.events.isEmpty)
    }
}
