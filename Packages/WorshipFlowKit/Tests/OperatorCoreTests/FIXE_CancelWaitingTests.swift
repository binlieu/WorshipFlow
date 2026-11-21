// FIX-E item 2 and 4: Blackout on, Clear, Clear all and Stop, from any source, drop every waited step of every running macro and
// the activity list says so; Blackout off cancels nothing; a macro's own later steps survive its own Blackout. Item 4 pins the order of
// a Next that crosses into another playlist item (KI-087).
import Testing
import Foundation
import CueEngine
import CueStore
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXE_CancelWaitingTests {
    struct Rig { var cue: CueModel; var show: FakeShow; var store: CueStore; var clock: TestCueClock }

    func rig() throws -> Rig {
        let library = try LibraryStore.inMemory()
        let store = CueStore(library: library)
        let show = FakeShow()
        let clock = TestCueClock()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { show }), clock: clock)
        return Rig(cue: cue, show: show, store: store, clock: clock)
    }

    /// Runs `[Next, wait 30 s, Next]` and returns with the second Next waiting.
    func startWaitingMacro(_ r: Rig) async throws {
        let macro = Macro(name: "Slow", steps: [.transport(.next), .wait(seconds: 30), .transport(.next)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        r.cue.submit(.runMacro(macro.id), from: .button)
        await r.cue.settled()
        #expect(r.show.log == ["next sync"])
    }

    func thirtySecondsLater(_ r: Rig) async {
        r.clock.seconds += 30
        r.cue.tick()
        await r.cue.settled()
    }

    @Test(arguments: [CommandSource.button, .midi, .remote, .key])
    func blackoutOnCancelsTheWaitingStepAndBlackoutStaysOn(source: CommandSource) async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        r.cue.submit(.transport(.blackout(.on)), from: source)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "blackout true"])          // the slide has not moved
        #expect(r.show.isBlackedOut)
        #expect(r.cue.activity.contains { $0.text == "cancelled: 1 waiting step" })
    }

    @Test func blackoutToggledOnCancelsToo() async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        r.cue.submit(.transport(.blackout(.toggle)), from: .key)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "blackout true"])
    }

    @Test func clearCancelsTheWaitingStep() async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        r.cue.submit(.transport(.clear), from: .midi)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "clear"])
        #expect(r.cue.activity.contains { $0.text == "cancelled: 1 waiting step" })
    }

    @Test func clearAllCancelsTheWaitingStep() async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        r.cue.submit(.transport(.clearAll), from: .remote)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "clearAll"])
        #expect(r.cue.activity.contains { $0.text == "cancelled: 1 waiting step" })
    }

    @Test func stopCancelsTheWaitingStepAndSaysSo() async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        r.cue.submit(.transport(.stop), from: .key)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "stop"])
        #expect(r.cue.activity.contains { $0.text == "cancelled: 1 waiting step" })
    }

    @Test func blackoutOffCancelsNothing() async throws {
        let r = try rig()
        r.cue.submit(.transport(.blackout(.on)), from: .key)
        await r.cue.settled()
        try await startWaitingMacro2(r)
        r.cue.submit(.transport(.blackout(.off)), from: .key)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["blackout true", "next sync", "blackout false", "next sync"])      // the waited Next still ran
        #expect(r.cue.activity.contains { $0.text.hasPrefix("cancelled") } == false)
    }

    func startWaitingMacro2(_ r: Rig) async throws {
        let macro = Macro(name: "Slow", steps: [.transport(.next), .wait(seconds: 30), .transport(.next)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        r.cue.submit(.runMacro(macro.id), from: .button)
        await r.cue.settled()
    }

    @Test func aMacroDoesNotCancelItsOwnLaterSteps() async throws {
        let r = try rig()
        let macro = Macro(name: "Hold", steps: [.transport(.blackout(.on)), .wait(seconds: 30), .transport(.blackout(.off))])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        r.cue.submit(.runMacro(macro.id), from: .button)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["blackout true", "blackout false"])
    }

    @Test func aMacroThatClearsCancelsAnotherMacrosWaitingSteps() async throws {
        let r = try rig()
        try await startWaitingMacro(r)
        let clearer = Macro(name: "Clearer", steps: [.transport(.clear)])
        try await r.store.saveMacro(clearer)
        await r.cue.reload()
        r.cue.submit(.runMacro(clearer.id), from: .midi)
        await r.cue.settled()
        await thirtySecondsLater(r)
        #expect(r.show.log == ["next sync", "clear"])
        #expect(r.cue.activity.contains { $0.text == "cancelled: 1 waiting step" })
    }

    // MARK: Item 4 (KI-087)

    @Test func aNextThatCrossesIntoAnotherItemRunsAfterTheMacrosOtherSteps() async throws {
        let r = try rig()
        r.show.nextCrossesAnItem = true
        let macro = Macro(name: "Cross", steps: [.transport(.next), .transport(.clear)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        r.cue.submit(.runMacro(macro.id), from: .button)
        await r.cue.settled()
        #expect(r.show.log == ["clear", "next begin", "next end"])
    }
}
