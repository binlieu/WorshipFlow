// CUE-002b item 1 (ARCH-15): every command, whatever its source, goes through ONE serial path. These tests make a slow
// command and fire others at it from other sources: the log must never show two commands inside each other.
import Testing
import Foundation
import CueEngine
import CueStore
import Persistence
import Domain
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_CommandPathTests {
    func make(_ show: FakeShow = FakeShow(), clock: TestCueClock = TestCueClock()) throws -> (CueModel, FakeShow, CueStore, TestCueClock) {
        let library = try LibraryStore.inMemory()
        let store = CueStore(library: library)
        let model = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { show }), clock: clock)
        return (model, show, store, clock)
    }

    @Test func commandsFromEverySourceRunOneAtATimeInArrivalOrder() async throws {
        let (model, show, _, _) = try make()
        model.submit(.goLive, from: .button)
        model.submit(.transport(.next), from: .midi)
        model.submit(.transport(.next), from: .remote)
        model.submit(.transport(.previous), from: .key)
        await model.settled()
        #expect(show.log == ["goLive begin", "goLive end", "next begin", "next end", "next begin", "next end", "previous begin", "previous end"])
    }

    @Test func aHeldPadOrARemoteBurstCannotInterleaveWithTheOperator() async throws {
        let (model, show, _, _) = try make()
        async let remote: String? = model.run(.transport(.next), from: .remote)
        async let operatorKey: String? = model.run(.transport(.previous), from: .key)
        for _ in 0..<20 { model.submit(.transport(.next), from: .midi) }
        _ = await (remote, operatorKey)
        await model.settled()
        // Every "begin" is followed at once by its own "end".
        for pair in stride(from: 0, to: show.log.count, by: 2) {
            #expect(show.log[pair].hasSuffix("begin"))
            #expect(show.log[pair + 1] == show.log[pair].replacingOccurrences(of: "begin", with: "end"))
        }
        #expect(show.log.count == 44)
    }

    @Test func runReturnsOnlyWhenItsCommandHasFinished() async throws {
        let (model, show, _, _) = try make()
        model.submit(.goLive, from: .button)
        await model.run(.transport(.next), from: .remote)
        #expect(show.log.suffix(2) == ["next begin", "next end"])
    }

    @Test func aMacroRunsThroughTheExecutorWithItsStepsInTheEnginesOrder() async throws {
        let (model, show, store, _) = try make()
        let (look, timer) = (UUID(), UUID())
        show.looks = [look]; show.timers = [timer]
        let macro = Macro(name: "Start", steps: [.startTimer(timer), .selectLook(look), .transport(.clear)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .button)
        #expect(show.log == ["clear", "look \(look.uuidString.prefix(4))", "timer start"])     // transport, Look, then timers
    }

    @Test func aTransportInsideAMacroThatCrossesAnItemIsAwaitedBeforeTheCommandEnds() async throws {
        let (model, show, store, _) = try make()
        show.nextCrossesAnItem = true
        let macro = Macro(name: "Skip", steps: [.transport(.next)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .midi)
        #expect(show.log == ["next begin", "next end"])
    }

    @Test func failuresBecomeActivityLinesAndNoticesAndTheRestStillRuns() async throws {
        let (model, show, store, _) = try make()
        let timer = UUID()
        show.timers = [timer]
        let macro = Macro(name: "Mixed", steps: [.selectLook(UUID()), .startTimer(timer)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .button)
        #expect(show.log == ["timer start"])
        #expect(model.activity.contains { $0.isProblem && $0.text.contains("Select Look") })
        #expect(model.notices.contains { $0.text.contains("Select Look") })
    }

    @Test func aWaitedStageIsDeliveredByTickWhenTheClockHasPassedIt() async throws {
        let (model, show, store, clock) = try make()
        let timer = UUID()
        show.timers = [timer]
        let macro = Macro(name: "Later", steps: [.transport(.clear), .wait(seconds: 5), .startTimer(timer)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .button)
        #expect(show.log == ["clear"])
        model.tick(); await model.settled()
        #expect(show.log == ["clear"])                       // not due yet
        clock.seconds += 5
        model.tick(); await model.settled()
        #expect(show.log == ["clear", "timer start"])
        model.tick(); await model.settled()
        #expect(show.log.count == 2)                         // delivered once
    }

    @Test func stopCancelsWaitedStages() async throws {
        let (model, show, store, clock) = try make()
        let timer = UUID()
        show.timers = [timer]
        let macro = Macro(name: "Later", steps: [.wait(seconds: 5), .startTimer(timer)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .button)
        await model.run(.transport(.stop), from: .button)
        clock.seconds += 10
        model.tick(); await model.settled()
        #expect(show.log == ["stop"])
    }

    @Test func theQueueIsBoundedAndSaysSoWhenItOverflows() async throws {
        let (model, show, _, _) = try make()
        show.yields = 0
        for _ in 0..<(CueModel.queueLimit + 50) { model.submit(.transport(.clear), from: .midi) }
        await model.settled()
        #expect(show.log.count <= CueModel.queueLimit + 1)
        #expect(model.notices.contains { $0.text.contains("Too many") })
    }

    @Test func theTriggerOfAScheduledMacroIsTaggedAsASchedule() async throws {
        let (model, show, store, _) = try make()
        let macro = Macro(name: "Clear", steps: [.transport(.clear)])
        try await store.saveMacro(macro)
        await model.reload()
        await model.run(.runMacro(macro.id), from: .schedule)
        #expect(show.log == ["clear"])
        #expect(model.activity.last?.source == .schedule)
    }
}
