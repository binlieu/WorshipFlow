// CUE-002a (AUTO-12, storage half): scheduled events and the engine's state. Written by the implementer.
import Testing
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

@Suite struct CueStoreScheduleTests {
    @Test func aNewEventStartsFromNowSoAnEarlierTimeTodayDoesNotFire() async throws {
        let f = try Fixture()
        // Sunday 2026-03-08 12:00 UTC; the event is for 10:30, already past.
        f.clock.set(utc("2026-03-08T12:00:00Z"))
        let saved = try await f.store.saveScheduledEvent(weekly())
        #expect(saved.activeFrom == utc("2026-03-08T12:00:00Z"))
        var engine = try await f.store.loadLibrary().schedule
        let due = engine.due(after: utc("2026-03-08T09:00:00Z"), upTo: utc("2026-03-08T12:01:00Z"), calendar: Calendar(identifier: .gregorian))
        #expect(due.fire.isEmpty && due.skipped.isEmpty)
        // Next Sunday it does fire.
        let next = engine.due(after: utc("2026-03-15T10:00:00Z"), upTo: utc("2026-03-15T10:31:00Z"), calendar: Calendar(identifier: .gregorian))
        #expect(next.fire.count == 1)
    }

    @Test func switchingAnEventOnRestartsItFromNowAndSwitchingOffKeepsTheRest() async throws {
        let f = try Fixture()
        f.clock.set(utc("2026-03-01T08:00:00Z"))
        let e = try await f.store.saveScheduledEvent(weekly(enabled: false))
        f.clock.set(utc("2026-03-08T12:00:00Z"))
        let on = try await f.store.setScheduledEvent(id: e.id, enabled: true)
        #expect(on.isEnabled && on.activeFrom == utc("2026-03-08T12:00:00Z"))
        f.clock.set(utc("2026-03-09T12:00:00Z"))
        let off = try await f.store.setScheduledEvent(id: e.id, enabled: false)
        #expect(!off.isEnabled && off.activeFrom == utc("2026-03-08T12:00:00Z"))
        #expect(try await f.rawString("SELECT enabled FROM cueScheduledEvent") == "0")
        let again = try await f.store.setScheduledEvent(id: e.id, enabled: false)        // already off: unchanged
        #expect(again == off)
        await #expect(throws: CueStoreError.notFound) { _ = try await f.store.setScheduledEvent(id: UUID(), enabled: true) }
    }

    @Test func savingAnEnabledFlagOrANewTimeThroughSaveRestartsItToo() async throws {
        let f = try Fixture()
        f.clock.set(utc("2026-03-01T08:00:00Z"))
        var e = try await f.store.saveScheduledEvent(weekly(enabled: false))
        f.clock.set(utc("2026-03-08T12:00:00Z"))
        e.isEnabled = true
        e = try await f.store.saveScheduledEvent(e)
        #expect(e.activeFrom == utc("2026-03-08T12:00:00Z"))
        f.clock.set(utc("2026-03-09T12:00:00Z"))
        e.name = "Renamed"
        e = try await f.store.saveScheduledEvent(e)                       // only the name changed: not restarted
        #expect(e.activeFrom == utc("2026-03-08T12:00:00Z"))
        e.timing = .weekly(weekdays: [.sunday], hour: 11, minute: 0, timeZoneID: "UTC")
        e = try await f.store.saveScheduledEvent(e)
        #expect(e.activeFrom == utc("2026-03-09T12:00:00Z"))
        #expect(try await f.store.scheduledEvents() == [e])
    }

    @Test func eventsThatCannotWorkAreRefusedWithTheEnginesReasons() async throws {
        let f = try Fixture()
        let noActions = weekly(payload: .actions([]))
        let error = await #expect(throws: CueStoreError.self) { try await f.store.saveScheduledEvent(noActions) }
        #expect(error == .invalidEvent(["The event has no actions."]))
        await #expect(throws: CueStoreError.self) { try await f.store.saveScheduledEvent(weekly("")) }
        let missing = UUID()
        await #expect(throws: CueStoreError.unknownMacro(missing)) { try await f.store.saveScheduledEvent(weekly(payload: .macro(missing))) }
        await #expect(throws: CueStoreError.unknownMacro(missing)) { try await f.store.saveScheduledEvent(weekly(payload: .actions([.runMacro(missing)]))) }
        #expect(try await f.rawCount("cueScheduledEvent") == 0)
    }

    @Test func eventsListInTheOrderTheyWereCreatedAndASecondSaveKeepsThePlace() async throws {
        let f = try Fixture()
        let a = try await f.store.saveScheduledEvent(weekly("A")), b = try await f.store.saveScheduledEvent(weekly("B"))
        var a2 = a; a2.name = "A2"
        try await f.store.saveScheduledEvent(a2)
        #expect(try await f.store.scheduledEvents().map(\.name) == ["A2", "B"])
        #expect(b.name == "B")
    }

    @Test func stateRoundTripsWithItsLastCheckAtomicallyInOneRow() async throws {
        let f = try Fixture()
        #expect(try await f.store.scheduleState() == nil)
        let e = try await f.store.saveScheduledEvent(weekly())
        let s1 = ScheduleEngineState(gracePeriod: 120, lastHandled: [e.id: t0.addingTimeInterval(0.5)], lastCheckedAt: t0.addingTimeInterval(10.25))
        try await f.store.saveScheduleState(s1)
        #expect(try await f.store.scheduleState() == s1)
        let s2 = ScheduleEngineState(gracePeriod: 300, lastHandled: [e.id: t0.addingTimeInterval(99)], lastCheckedAt: t0.addingTimeInterval(100))
        try await f.store.saveScheduleState(s2)
        #expect(try await f.store.scheduleState() == s2)
        #expect(try await f.rawCount("cueScheduleState") == 1)
        // The lastCheckedAt column and the stored state never disagree.
        let column = try await f.library.cueRead { try Date.fetchOne($0, sql: "SELECT lastCheckedAt FROM cueScheduleState") }
        #expect(column == s2.lastCheckedAt)
    }

    @Test func aRelaunchFromTheStoredStateDoesNotFireTheSameOccurrenceAgain() async throws {
        let f = try Fixture()
        f.clock.set(utc("2026-03-01T08:00:00Z"))
        try await f.store.saveScheduledEvent(weekly())
        var engine = try await f.store.loadLibrary().schedule
        let cal = Calendar(identifier: .gregorian)
        #expect(engine.due(after: utc("2026-03-08T10:00:00Z"), upTo: utc("2026-03-08T10:31:00Z"), calendar: cal).fire.count == 1)
        try await f.store.saveScheduleState(engine.state)

        var relaunched = try await f.store.loadLibrary().schedule
        #expect(relaunched.lastCheckedAt == utc("2026-03-08T10:31:00Z"))
        #expect(relaunched.due(after: utc("2026-03-08T10:00:00Z"), upTo: utc("2026-03-08T10:40:00Z"), calendar: cal).fire.isEmpty)
    }

    @Test func deletingAnEventDropsItsRowAndItsPlaceInTheState() async throws {
        let f = try Fixture()
        let a = try await f.store.saveScheduledEvent(weekly("A")), b = try await f.store.saveScheduledEvent(weekly("B"))
        try await f.store.saveScheduleState(ScheduleEngineState(lastHandled: [a.id: t0, b.id: t0], lastCheckedAt: t0))
        try await f.store.deleteScheduledEvent(id: a.id)
        #expect(try await f.store.scheduledEvents().map(\.id) == [b.id])
        #expect(try await f.store.scheduleState()?.lastHandled == [b.id: t0])
        await #expect(throws: CueStoreError.notFound) { try await f.store.deleteScheduledEvent(id: a.id) }
    }

    @Test func aNewerVersionStateIsNeverOverwritten() async throws {
        let f = try Fixture()
        try await f.rawExec("INSERT INTO cueScheduleState (id, state, lastCheckedAt, updatedAt) VALUES (1, '{\"version\":9,\"x\":1}', NULL, '2026-01-01 00:00:00.000')")
        await #expect(throws: CueStoreError.self) { try await f.store.saveScheduleState(ScheduleEngineState()) }
        #expect(try await f.rawString("SELECT state FROM cueScheduleState") == "{\"version\":9,\"x\":1}")
    }
}
