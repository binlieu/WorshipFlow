// UI-003 Part 1: the timers shown in the toolbar. Default: the first elapsed timer and the first countdown. The
// operator can mark others (or unmark these). Overrun is reported as a flag (the view uses the warning colour).
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI003_ToolbarTimerTests {
    func ready(_ store: LibraryStore? = nil, clock: TestClock = TestClock()) async throws -> (StageModel, LibraryStore, TestClock) {
        let store = try store ?? LibraryStore.inMemory()
        let model = StageModel(store: store, now: { clock.date }, calendar: StageModelTests.utc)
        await model.load()
        return (model, store, clock)
    }

    @Test func noTimersMeansNothingToShow() async throws {
        let (model, _, _) = try await ready()
        #expect(model.toolbarTimerRows(at: model.nowSeconds).isEmpty)
    }

    @Test func theDefaultIsTheFirstElapsedAndTheFirstCountdown() async throws {
        let (model, _, _) = try await ready()
        let sermon = try #require(model.addCountdown(name: "Sermon", minutes: 25, seconds: 0))
        _ = model.addCountdown(name: "Second", minutes: 5, seconds: 0)
        let service = try #require(model.addElapsed(name: "Service"))
        _ = model.addElapsed(name: "Other")
        _ = model.addCountdown(name: "To ten", toHour: 10, minute: 0)
        let rows = model.toolbarTimerRows(at: model.nowSeconds)
        #expect(rows.map(\.id) == [sermon.id, service.id])           // the operator's own order
        #expect(rows.map(\.text) == ["25:00", "0:00"])
    }

    @Test func onlyACountdownGetsAStartPauseButtonAndItFlipsWithTheState() async throws {
        let (model, _, clock) = try await ready()
        let sermon = try #require(model.addCountdown(name: "Sermon", minutes: 25, seconds: 0))
        let service = try #require(model.addElapsed(name: "Service"))
        var rows = model.toolbarTimerRows(at: model.nowSeconds)
        #expect(rows.first { $0.id == sermon.id }?.canToggle == true && rows.first { $0.id == sermon.id }?.isRunning == false)
        #expect(rows.first { $0.id == service.id }?.canToggle == false)
        model.toggleToolbarTimer(sermon.id)
        clock.advance(10)
        rows = model.toolbarTimerRows(at: model.nowSeconds)
        #expect(rows.first { $0.id == sermon.id }?.isRunning == true && rows.first { $0.id == sermon.id }?.text == "24:50")
        model.toggleToolbarTimer(sermon.id)
        clock.advance(10)
        rows = model.toolbarTimerRows(at: model.nowSeconds)
        #expect(rows.first { $0.id == sermon.id }?.isRunning == false && rows.first { $0.id == sermon.id }?.text == "24:50")
        model.toggleToolbarTimer(service.id)                          // no button: nothing happens
        #expect(model.timers.first { $0.id == service.id }?.isRunning == false)
    }

    @Test func overrunIsFlagged() async throws {
        let (model, _, clock) = try await ready()
        let t = try #require(model.addCountdown(name: "Short", minutes: 0, seconds: 5))
        model.startTimer(t.id)
        clock.advance(8)
        let row = try #require(model.toolbarTimerRows(at: model.nowSeconds).first)
        #expect(row.isOverrun)
    }

    @Test func theOperatorCanMarkAndUnmarkAndItIsRemembered() async throws {
        let (model, store, clock) = try await ready()
        let a = try #require(model.addCountdown(name: "A", minutes: 1, seconds: 0))
        let b = try #require(model.addCountdown(name: "B", minutes: 2, seconds: 0))
        #expect(model.isShownInToolbar(a.id) && !model.isShownInToolbar(b.id))
        model.setShownInToolbar(b.id, true)
        #expect(model.toolbarTimerRows(at: model.nowSeconds).map(\.id) == [a.id, b.id])
        model.setShownInToolbar(a.id, false)
        #expect(model.toolbarTimerRows(at: model.nowSeconds).map(\.id) == [b.id])
        await model.flush()
        let (again, _, _) = try await ready(store, clock: clock)
        #expect(again.toolbarTimerRows(at: again.nowSeconds).map(\.id) == [b.id])
    }

    @Test func unmarkingEverythingShowsNothingEvenThoughDefaultsExist() async throws {
        let (model, _, _) = try await ready()
        let a = try #require(model.addCountdown(name: "A", minutes: 1, seconds: 0))
        model.setShownInToolbar(a.id, false)
        #expect(model.toolbarTimerRows(at: model.nowSeconds).isEmpty)
    }

    @Test func aDeletedTimerLeavesTheToolbar() async throws {
        let (model, _, _) = try await ready()
        let a = try #require(model.addCountdown(name: "A", minutes: 1, seconds: 0))
        let b = try #require(model.addCountdown(name: "B", minutes: 2, seconds: 0))
        model.setShownInToolbar(b.id, true)
        model.deleteTimer(b.id)
        #expect(model.toolbarTimerRows(at: model.nowSeconds).map(\.id) == [a.id])
    }
}
