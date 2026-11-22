// STAGE-001b (LIVE-01, LIVE-02, LIVE-04, SCRN-03): layouts, timers, clock style and screen choices.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// A clock the tests move by hand.
@MainActor
final class TestClock {
    var date: Date
    init(_ date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite struct StageModelTests {
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    func ready(_ store: LibraryStore? = nil, clock: TestClock = TestClock()) async throws -> (StageModel, LibraryStore, TestClock) {
        let store = try store ?? LibraryStore.inMemory()
        let model = StageModel(store: store, now: { clock.date }, calendar: Self.utc)
        await model.load()
        return (model, store, clock)
    }

    func relaunch(_ store: LibraryStore, _ clock: TestClock) async -> StageModel {
        let model = StageModel(store: store, now: { clock.date }, calendar: Self.utc)
        await model.load()
        return model
    }

    // MARK: Layouts

    @Test func firstLaunchHasOnlyTheBuiltInLayout() async throws {
        let (model, _, _) = try await ready()
        #expect(model.layouts == [StageLayout.standard] && model.customLayouts.isEmpty && model.timers.isEmpty)
        #expect(model.isLoaded && model.lastError == nil)
        #expect(!model.isEditable(StageLayout.standardID))
    }

    @Test func theBuiltInLayoutIsReadOnlyAndExplainsHowToEdit() async throws {
        let (model, store, _) = try await ready()
        let id = StageLayout.standardID
        let element = try #require(StageLayout.standard.elements.first)
        model.setFontSize(10, for: element.id, in: id)
        #expect(model.lastError == StageModel.readOnlyMessage && model.lastError?.contains("Duplicate") == true)
        model.dismissError()
        model.removeElement(element.id, from: id)
        model.renameLayout(id, to: "Mine")
        model.deleteLayout(id)
        #expect(model.addElement(.message, to: id) == nil)
        #expect(model.lastError == StageModel.readOnlyMessage)
        #expect(model.layouts == [StageLayout.standard])
        await model.flush()
        #expect(try await store.stageLayouts().isEmpty)
    }

    @Test func createDuplicateRenameAndDeleteAreStored() async throws {
        let (model, store, clock) = try await ready()
        let made = try #require(model.createLayout(name: "  Worship band  "))
        #expect(made.name == "Worship band" && made.id != StageLayout.standardID)
        #expect(made.elements.map(\.kind) == StageLayout.standard.elements.map(\.kind))
        #expect(Set(made.elements.map(\.id)).isDisjoint(with: StageLayout.standard.elements.map(\.id)))   // fresh ids
        let copy = try #require(model.duplicateLayout(made.id))
        #expect(copy.name == "Worship band copy" && copy.elements.map(\.id) != made.elements.map(\.id))
        let ofBuiltIn = try #require(model.duplicateLayout(StageLayout.standardID))         // Duplicate on the built-in
        #expect(ofBuiltIn.name == "Standard copy" && model.isEditable(ofBuiltIn.id))
        model.renameLayout(copy.id, to: "Choir")
        model.deleteLayout(ofBuiltIn.id)
        await model.flush()
        #expect(model.lastError == nil)
        let again = await relaunch(store, clock)
        #expect(again.customLayouts.map(\.name) == ["Worship band", "Choir"])
        #expect(again.customLayouts.map(\.id) == model.customLayouts.map(\.id))
    }

    @Test func blankOrUnknownLayoutOperationsSetAnError() async throws {
        let (model, _, _) = try await ready()
        #expect(model.createLayout(name: "   ") == nil)
        #expect(model.lastError?.contains("a name is needed") == true)
        let made = try #require(model.createLayout(name: "A"))
        model.dismissError()
        model.renameLayout(made.id, to: "")
        #expect(model.lastError?.contains("a name is needed") == true)
        #expect(model.layout(withID: made.id)?.name == "A")
        model.dismissError()
        model.renameLayout(UUID(), to: "X")
        #expect(model.lastError?.contains("no longer exists") == true)
        model.dismissError()
        #expect(model.duplicateLayout(UUID()) == nil)
        #expect(model.lastError?.contains("no longer exists") == true)
    }

    // MARK: Choice per screen

    @Test func eachStageScreenKeepsItsOwnLayoutAcrossRelaunches() async throws {
        let (model, store, clock) = try await ready()
        let (a, b) = (UUID(), UUID())
        let one = try #require(model.createLayout(name: "One"))
        let two = try #require(model.createLayout(name: "Two"))
        #expect(model.layout(forScreen: a) == StageLayout.standard)           // no choice yet
        model.setLayout(one.id, forScreen: a)
        model.setLayout(two.id, forScreen: b)
        #expect(model.layout(forScreen: a).id == one.id && model.layout(forScreen: b).id == two.id)
        await model.flush()
        let again = await relaunch(store, clock)
        #expect(again.layoutID(forScreen: a) == one.id && again.layoutID(forScreen: b) == two.id)
        again.setLayout(nil, forScreen: a)                                     // back to the built-in one
        await again.flush()
        let third = await relaunch(store, clock)
        #expect(third.layoutID(forScreen: a) == StageLayout.standardID && third.layoutID(forScreen: b) == two.id)
    }

    @Test func deletingALayoutReturnsItsScreensToTheBuiltInOne() async throws {
        let (model, store, clock) = try await ready()
        let screen = UUID()
        let mine = try #require(model.createLayout(name: "Mine"))
        model.setLayout(mine.id, forScreen: screen)
        model.deleteLayout(mine.id)
        #expect(model.layoutID(forScreen: screen) == StageLayout.standardID)
        await model.flush()
        #expect(model.lastError == nil)
        #expect(await relaunch(store, clock).layoutID(forScreen: screen) == StageLayout.standardID)
        model.setLayout(UUID(), forScreen: screen)                             // a layout that does not exist is refused
        #expect(model.lastError?.contains("no longer exists") == true)
    }

    @Test func aStoredChoiceThatPointsAtAMissingLayoutIsIgnoredAtLoad() async throws {
        let store = try LibraryStore.inMemory()
        let screen = UUID()
        let text = "{\"\(screen.uuidString)\":\"\(UUID().uuidString)\"}"
        try await store.setState(text, for: StageModel.choicesKey)
        try await store.setState("not json", for: StageModel.clockKey)
        let (model, _, _) = try await ready(store)
        #expect(model.layoutID(forScreen: screen) == StageLayout.standardID)
        #expect(model.layoutChoices.isEmpty && model.clockStyle == ClockStyle() && model.lastError == nil)
    }

    // MARK: Elements

    func editable(_ model: StageModel) throws -> (StageLayout, StageElement) {
        let layout = try #require(model.createLayout(name: "Edit"))
        return (layout, try #require(layout.elements.first))
    }

    @Test func addingAndRemovingElementsOfEveryKind() async throws {
        let (model, store, clock) = try await ready()
        let layout = try #require(model.createLayout(name: "All"))
        let timer = try #require(model.addElapsed(name: "Run"))
        var added: [UUID] = []
        for template in NewStageElement.allCases { added.append(try #require(model.addElement(template, to: layout.id))) }
        let kinds = try #require(model.layout(withID: layout.id)).elements.map(\.kind).suffix(6)
        #expect(Array(kinds) == [.currentSlide, .nextSlide, .timeOfDay, .timer(timer.id), .message, .notes])
        model.removeElement(added[0], from: layout.id)
        await model.flush()
        let reloaded = await relaunch(store, clock)
        #expect(reloaded.layout(withID: layout.id)?.elements.count == 4 + 6 - 1)   // UI-005h: the built-in layout has four elements (was: 3 + 6 - 1)
        #expect(reloaded.layout(withID: layout.id)?.elements.contains { $0.id == added[0] } == false)
    }

    @Test func aTimerElementNeedsAnExistingTimer() async throws {
        let (model, _, _) = try await ready()
        let layout = try #require(model.createLayout(name: "T"))
        #expect(model.addElement(.timer, to: layout.id) == nil)
        #expect(model.lastError?.contains("no timers yet") == true)
        model.dismissError()
        #expect(model.addElement(.timer, to: layout.id, timerID: UUID()) == nil)
        #expect(model.lastError?.contains("no longer exists") == true)
        let one = try #require(model.addElapsed(name: "One"))
        let two = try #require(model.addElapsed(name: "Two"))
        let element = try #require(model.addElement(.timer, to: layout.id, timerID: one.id))
        model.setTimer(two.id, for: element, in: layout.id)
        #expect(model.layout(withID: layout.id)?.elements.first { $0.id == element }?.kind == .timer(two.id))
        model.dismissError()
        model.setTimer(UUID(), for: element, in: layout.id)
        #expect(model.lastError != nil)
        #expect(model.layout(withID: layout.id)?.elements.first { $0.id == element }?.kind == .timer(two.id))
    }

    @Test func dragMovesFromTheStartFrameAndStaysOnScreen() async throws {
        let (model, _, _) = try await ready()
        let (layout, element) = try editable(model)
        let start = element.frame
        model.moveElement(element.id, in: layout.id, from: start, dx: 0.1, dy: 0.05)
        var now = try #require(model.layout(withID: layout.id)?.elements.first { $0.id == element.id }).frame
        #expect(abs(now.x - (start.x + 0.1)) < 1e-9 || now.x == 1 - start.width)
        #expect(now.width == start.width && now.height == start.height)
        model.moveElement(element.id, in: layout.id, from: start, dx: 5, dy: 5)        // far off screen: pinned to the corner
        now = try #require(model.layout(withID: layout.id)?.elements.first { $0.id == element.id }).frame
        #expect(abs(now.x - (1 - start.width)) < 1e-9 && abs(now.y - (1 - start.height)) < 1e-9)
        model.moveElement(element.id, in: layout.id, from: start, dx: 0, dy: 0)       // dragging back restores it exactly
        #expect(model.layout(withID: layout.id)?.elements.first { $0.id == element.id }?.frame == start)
        model.moveElement(element.id, in: layout.id, from: start, dx: -5, dy: -5)
        now = try #require(model.layout(withID: layout.id)?.elements.first { $0.id == element.id }).frame
        #expect(now.x == 0 && now.y == 0)
    }

    @Test func resizeIsClampedToTheMinimumAndTheScreenEdge() async throws {
        let (model, _, _) = try await ready()
        let (layout, element) = try editable(model)
        let start = element.frame
        func frame() -> NormalizedRect { model.layout(withID: layout.id)?.elements.first { $0.id == element.id }?.frame ?? .full }
        model.resizeElement(element.id, in: layout.id, from: start, dWidth: -5, dHeight: -5)
        #expect(frame().width == StageElement.minimumSize && frame().height == StageElement.minimumSize)
        #expect(frame().x == start.x && frame().y == start.y)
        model.resizeElement(element.id, in: layout.id, from: start, dWidth: 5, dHeight: 5)
        #expect(abs(frame().x + frame().width - 1) < 1e-9 && abs(frame().y + frame().height - 1) < 1e-9)
        model.resizeElement(element.id, in: layout.id, from: start, dWidth: 0.02, dHeight: -0.01)
        #expect(abs(frame().width - (start.width + 0.02)) < 1e-9 || frame().x + frame().width == 1)
    }

    @Test func typedFrameFontColourAndAlignmentAreAppliedAndClamped() async throws {
        let (model, store, clock) = try await ready()
        let (layout, element) = try editable(model)
        model.setFrame(element.id, in: layout.id, x: 0.9, y: 0.9, width: 0.5, height: 0.5)
        model.setFontSize(5_000, for: element.id, in: layout.id)
        model.setColor(ColorRGBA(red: 1, green: 0, blue: 0), for: element.id, in: layout.id)
        model.setAlignment(.center, for: element.id, in: layout.id)
        model.setShowsSecondLanguage(false, for: element.id, in: layout.id)
        func current(_ m: StageModel) throws -> StageElement {
            try #require(m.layout(withID: layout.id)?.elements.first { $0.id == element.id })
        }
        let e = try current(model)
        #expect(e.frame == NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(e.style.fontSize == StageEditing.fontSizeRange.upperBound)
        #expect(e.style.color == ColorRGBA(red: 1, green: 0, blue: 0) && e.alignment == .center && !e.showsSecondLanguage)
        #expect(e.id == element.id && e.kind == element.kind)
        await model.flush()
        #expect(try current(await relaunch(store, clock)) == e)             // all of it was written
    }

    @Test func editingAnUnknownElementChangesNothing() async throws {
        let (model, _, _) = try await ready()
        let (layout, _) = try editable(model)
        let before = model.layout(withID: layout.id)
        model.setFontSize(80, for: UUID(), in: layout.id)
        model.removeElement(UUID(), from: layout.id)
        #expect(model.layout(withID: layout.id) == before && model.lastError == nil)
    }

    // MARK: Timers

    @Test func countdownStartPauseAndResetUseTheInjectedClock() async throws {
        let (model, store, clock) = try await ready()
        let timer = try #require(model.addCountdown(name: "Sermon", minutes: 20, seconds: 0))
        func row() -> TimerRow { model.timerRows(at: clock.date.timeIntervalSinceReferenceDate)[0] }
        #expect(row().text == "20:00" && !row().isRunning)
        model.startTimer(timer.id)
        clock.advance(65)
        #expect(row().text == "18:55" && row().isRunning && !row().isOverrun)
        model.pauseTimer(timer.id)
        clock.advance(500)                                                       // paused: time does not move
        #expect(row().text == "18:55" && !row().isRunning)
        model.startTimer(timer.id)
        clock.advance(18 * 60 + 55 + 5)
        #expect(row().text == "-0:05" && row().isOverrun)
        await model.flush()
        let again = await relaunch(store, clock)                                  // a relaunch mid-countdown shows the right time
        #expect(again.timerRows(at: clock.date.timeIntervalSinceReferenceDate)[0].text == "-0:05")
        model.resetTimer(timer.id)
        #expect(row().text == "20:00" && !row().isRunning && !row().isOverrun)
    }

    @Test func elapsedTimerCountsUp() async throws {
        let (model, _, clock) = try await ready()
        let timer = try #require(model.addElapsed(name: nil))
        #expect(timer.name == "Elapsed")
        model.startTimer(timer.id)
        clock.advance(3_725)
        let row = model.timerRows(at: clock.date.timeIntervalSinceReferenceDate)[0]
        #expect(row.text == "1:02:05" && !row.isOverrun && row.kindLabel == "Elapsed")
    }

    @Test func countdownToATimeTodayFollowsTheClockAndGoesOverrunAfterIt() async throws {
        let noon = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 11, minute: 30)) ?? Date()
        let (model, _, clock) = try await ready(clock: TestClock(noon))
        let timer = try #require(model.addCountdown(name: "Service", toHour: 12, minute: 0))
        func row() -> TimerRow { model.timerRows(at: clock.date.timeIntervalSinceReferenceDate)[0] }
        #expect(row().text == "30:00" && row().followsClock && row().kindLabel == "Countdown to 12:00 PM")
        model.startTimer(timer.id)                                                // no start, pause or reset for a clock timer
        model.pauseTimer(timer.id)
        model.resetTimer(timer.id)
        clock.advance(10 * 60)
        #expect(row().text == "20:00")
        clock.advance(20 * 60 + 3)
        #expect(row().text == "-0:03" && row().isOverrun)
    }

    @Test func timerInputIsChecked() async throws {
        let (model, _, _) = try await ready()
        for (minutes, seconds) in [(0, 0), (-1, 30), (5, -10), (6_000, 0)] {
            #expect(model.addCountdown(name: "x", minutes: minutes, seconds: seconds) == nil)
            #expect(model.lastError?.contains("longer than zero") == true)
            model.dismissError()
        }
        #expect(model.addCountdown(name: "ok", minutes: 0, seconds: 90)?.kind == .countdown(seconds: 90))
        #expect(model.addCountdown(name: "x", toHour: 24, minute: 0) == nil)
        #expect(model.addCountdown(name: "x", toHour: 9, minute: 60) == nil)
        #expect(model.lastError?.contains("hour from 0 to 23") == true)
        #expect(model.timers.count == 1)
    }

    @Test func timersAreRenamedAndDeletedAndStored() async throws {
        let (model, store, clock) = try await ready()
        let a = try #require(model.addCountdown(name: "A", minutes: 1, seconds: 0))
        let b = try #require(model.addElapsed(name: "B"))
        model.renameTimer(a.id, to: "  Welcome ")
        model.renameTimer(b.id, to: "   ")
        #expect(model.lastError?.contains("a name is needed") == true)
        model.deleteTimer(b.id)
        model.deleteTimer(b.id)                                                  // already gone: reported, not fatal
        #expect(model.lastError?.contains("no longer exists") == true)
        await model.flush()
        let again = await relaunch(store, clock)
        #expect(again.timers.map(\.name) == ["Welcome"])
        model.startTimer(UUID())
        #expect(model.lastError?.contains("no longer exists") == true)
    }

    // MARK: Clock style

    @Test func theClockReadsAsSetAndTheSettingIsKept() async throws {
        let at = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 5, second: 9)) ?? Date()
        let (model, store, clock) = try await ready(clock: TestClock(at))
        #expect(model.timeOfDayText(at: at) == "2:05 PM")
        model.setClockStyle(showsSeconds: true)
        #expect(model.timeOfDayText(at: at) == "2:05:09 PM")
        model.setClockStyle(twentyFourHour: true)
        #expect(model.timeOfDayText(at: at) == "14:05:09")
        model.setClockStyle(showsSeconds: false)
        #expect(model.timeOfDayText(at: at) == "14:05")
        await model.flush()
        let again = await relaunch(store, clock)
        #expect(again.clockStyle == ClockStyle(twentyFourHour: true, showsSeconds: false))
    }

    @Test func theStageSceneShowsTheClockInTheChosenStyle() async throws {
        let at = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9, minute: 7, second: 3)) ?? Date()
        let (model, _, _) = try await ready(clock: TestClock(at))
        let screen = UUID()
        let state = ShowState()
        #expect(model.stageScene(forScreen: screen, state: state, notes: nil).textLayers.map(\.text) == ["9:07 AM"])
        model.setClockStyle(twentyFourHour: true, showsSeconds: true)
        #expect(model.stageScene(forScreen: screen, state: state, notes: nil).textLayers.map(\.text) == ["09:07:03"])
    }

    // MARK: Refresh and change notices

    @Test func theAppOnlyTicksForScreensWhoseLayoutHasAClockOrTimer() async throws {
        let (model, _, _) = try await ready()
        let (a, b) = (UUID(), UUID())
        #expect(model.needsPerSecondRefresh(forScreens: [a]))                      // the built-in layout has a clock
        let quiet = try #require(model.createLayout(name: "Quiet"))
        for element in quiet.elements where element.kind == .timeOfDay || element.kind == .firstCountdown { model.removeElement(element.id, from: quiet.id) }   // UI-005h: the built-in layout also has a timer (was: .timeOfDay only)
        model.setLayout(quiet.id, forScreen: a)
        #expect(!model.needsPerSecondRefresh(forScreens: [a]))
        #expect(!model.needsPerSecondRefresh(forScreens: []))
        #expect(model.needsPerSecondRefresh(forScreens: [a, b]))                   // b still has the built-in layout
        _ = model.addElapsed(name: "Run")
        model.addElement(.timer, to: quiet.id)
        #expect(model.needsPerSecondRefresh(forScreens: [a]))
    }

    @Test func everyChangeThatCanAlterAStagePictureIsAnnounced() async throws {
        let (model, _, _) = try await ready()
        var notices = 0
        model.onChange = { notices += 1 }
        let layout = try #require(model.createLayout(name: "N"))
        let timer = try #require(model.addElapsed(name: "T"))
        model.startTimer(timer.id)
        model.setClockStyle(showsSeconds: true)
        model.setLayout(layout.id, forScreen: UUID())
        let element = try #require(layout.elements.first)
        model.setFontSize(70, for: element.id, in: layout.id)
        #expect(notices == 6)
        model.setClockStyle(showsSeconds: true)                                    // no change, no notice
        model.setFontSize(70, for: element.id, in: layout.id)
        model.startTimer(timer.id)
        #expect(notices == 6)
    }

    // MARK: Failures

    @Test func aFailedWriteSetsAMessageTheOperatorCanActOn() async throws {
        let (model, store, _) = try await ready()
        try store.close()
        _ = model.createLayout(name: "Lost")
        await model.flush()
        let message = try #require(model.lastError)
        #expect(message.hasPrefix("Could not save the layout") && message.contains("restart the app"))
        #expect(model.customLayouts.map(\.name) == ["Lost"])                       // still in effect in memory
    }

    @Test func storeErrorsReadAsPlainSentences() {
        for error in [StoreError.invalidName, .notFound, .invalidReference, .unknownMigration("v9")] {
            let text = StageModel.message(for: error, doing: "do it")
            #expect(text.hasPrefix("Could not do it:") && text.hasSuffix("."))
        }
    }
}
