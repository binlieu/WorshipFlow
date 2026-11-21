// FIX-E items 5, 6 and 7: while the Hardware Test runs, commands from MIDI, the remote server and the schedule are refused (buttons and
// keys are not) and the refusal is recorded; an event that falls due then is listed with the missed events; the remote macro endpoint
// answers like the transport endpoint when a step failed.
import Testing
import Foundation
import CueEngine
import CueStore
import Persistence
import MIDIIO
import RemoteControl
@testable import OperatorCore

@MainActor
@Suite struct FIXE_HardwareTestTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: h, minute: m, second: s))! }

    struct Rig { var cue: CueModel; var show: FakeShow; var store: CueStore; var wall: WallClock; var library: LibraryStore }

    func rig(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> Rig {
        let library = try LibraryStore.inMemory()
        let wall = WallClock(start)
        let store = CueStore(library: library, now: { wall.date })
        let show = FakeShow()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock(), wallClock: { wall.date }, calendar: utc, settingsStore: library)
        cue.remoteLoopbackOnly = true
        cue.remotePortOverride = 0
        return Rig(cue: cue, show: show, store: store, wall: wall, library: library)
    }

    // MARK: Item 5

    @Test(arguments: [CommandSource.midi, .remote, .schedule])
    func aCommandFromThisSourceIsRefusedWhileTheTestRunsAndRecorded(source: CommandSource) async throws {
        let r = try rig()
        r.cue.hardwareTestIsRunning = { true }
        r.cue.submit(.transport(.next), from: source)
        let why = await r.cue.run(.transport(.next), from: source)
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(why?.contains("Hardware Test") == true)
        #expect(r.cue.activity.filter { $0.source == source && $0.isProblem && $0.text.contains("refused") }.count == 2)
    }

    @Test(arguments: [CommandSource.button, .key])
    func buttonsAndKeysStillWorkWhileTheTestRuns(source: CommandSource) async throws {
        let r = try rig()
        r.cue.hardwareTestIsRunning = { true }
        r.cue.submit(.transport(.next), from: source)
        await r.cue.settled()
        #expect(r.show.log == ["next begin", "next end"])
    }

    @Test func aMIDIPadIsRefusedWhileTheTestRuns() async throws {
        let ports = FakeMIDIPorts()
        let r = try rig()
        r.cue.midiPortsFactory = { ports }
        ports.addSource(id: 7, name: "Pad")
        await r.cue.start()
        await r.cue.setMIDIEnabled(true)
        await r.cue.chooseMIDIInput(7)
        await r.cue.saveBinding(MIDIBinding(name: "Next", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 60), command: .transport(.next)))
        r.cue.hardwareTestIsRunning = { true }
        ports.emit(.noteOn(channel: 1, note: 60, velocity: 100), from: 7)
        for _ in 0..<20_000 where !r.cue.activity.contains(where: { $0.source == .midi }) { await Task.yield() }
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(r.cue.activity.contains { $0.source == .midi && $0.isProblem })
        await r.cue.setMIDIEnabled(false)
    }

    @Test func theRemoteAnswers409WithAReasonWhileTheTestRuns() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await fixePair(r.cue, port: port)
        r.cue.hardwareTestIsRunning = { true }
        let (status, body) = try await fixeCall(port, "POST", "/api/v1/transport", token: token, json: "{\"command\":\"next\"}")
        #expect(status == 409)
        #expect(String(decoding: body, as: UTF8.self).contains("Hardware Test"))
        #expect(r.show.log.isEmpty)
        #expect(r.cue.activity.contains { $0.source == .remote && $0.isProblem })
        r.cue.hardwareTestIsRunning = { false }
        let (ok, _) = try await fixeCall(port, "POST", "/api/v1/transport", token: token, json: "{\"command\":\"next\"}")
        #expect(ok == 200)
        await r.cue.stopRemote()
    }

    // MARK: Item 6

    @Test func anEventDueDuringTheTestIsListedWithTheMissedEventsAfterItEnds() async throws {
        let r = try rig(start: at(8, 59))
        let macro = Macro(name: "Start", steps: [.transport(.clear)])
        try await r.store.saveMacro(macro)
        _ = try await r.store.saveScheduledEvent(ScheduledEvent(name: "Doors", timing: .once(at(9, 0)), payload: .macro(macro.id)))
        await r.cue.reload()
        r.cue.pollSchedule()
        var testing = true
        r.cue.hardwareTestIsRunning = { testing }
        r.wall.date = at(9, 0, 5)
        r.cue.pollSchedule()
        await r.cue.settled()
        #expect(r.cue.notices.contains { $0.text.contains("Hardware Test") })       // the notice stays
        #expect(r.cue.missedEvents.count == 1)
        #expect(r.cue.missedEvents.first.map { $0.text.contains("Doors") && $0.text.contains("Hardware Test") } == true)
        testing = false
        r.wall.date = at(9, 1)
        r.cue.pollSchedule()
        #expect(r.cue.missedEvents.count == 1)                                       // still there after the test ends
        r.cue.dismissMissedEvents()
        #expect(r.cue.missedEvents.isEmpty)
    }

    @Test func aSkippedEventIsListedToo() async throws {
        let r = try rig(start: at(8, 0))
        let macro = Macro(name: "Start", steps: [.transport(.clear)])
        try await r.store.saveMacro(macro)
        _ = try await r.store.saveScheduledEvent(ScheduledEvent(name: "Doors", timing: .once(at(8, 30)), payload: .macro(macro.id)))
        try await r.store.saveScheduleState(ScheduleEngineState(lastCheckedAt: at(8, 10)))
        r.wall.date = at(9, 0)
        await r.cue.reload()
        r.cue.pollSchedule()
        #expect(r.cue.missedEvents.contains { $0.text.contains("Doors") && $0.text.contains("missed") })
    }

    // MARK: Item 7

    @Test func theRemoteMacroEndpointRejectsLikeTheTransportEndpointWhenAStepFailed() async throws {
        let r = try rig()
        let macro = Macro(name: "Broken", steps: [.selectLook(UUID())])              // a Look that does not exist
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await fixePair(r.cue, port: port)
        let (status, body) = try await fixeCall(port, "POST", "/api/v1/macros/\(macro.id.uuidString)/run", token: token)
        #expect(status == 409)
        #expect(String(decoding: body, as: UTF8.self).contains("Look"))
        await r.cue.stopRemote()
    }
}
