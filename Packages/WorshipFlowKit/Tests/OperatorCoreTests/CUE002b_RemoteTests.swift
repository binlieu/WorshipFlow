// CUE-002b item 5: the remote control server is off until the operator turns it on, listens only where the run says (loopback and an
// ephemeral port here), sends every command through the one command path, keeps paired devices as salted hashes in the library,
// and is stopped again. Real loopback sockets, always stopped at the end of each test.
import Testing
import Foundation
import Domain
import CueEngine
import CueStore
import Persistence
import RemoteControl
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_RemoteTests {
    struct Rig { var cue: CueModel; var show: FakeShow; var store: CueStore; var library: LibraryStore }

    func rig(library: LibraryStore? = nil) throws -> Rig {
        let lib = try library ?? LibraryStore.inMemory()
        let store = CueStore(library: lib)
        let show = FakeShow()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { nil }),
                           clock: TestCueClock(), settingsStore: lib)
        cue.remoteLoopbackOnly = true
        cue.remotePortOverride = 0
        cue.localAddresses = { ["192.168.1.20"] }
        return Rig(cue: cue, show: show, store: store, library: lib)
    }

    func call(_ port: UInt16, _ method: String, _ path: String, token: String? = nil, json: String? = nil) async throws -> (Int, Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(json.utf8)
        }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func pair(_ r: Rig, port: UInt16, label: String = "Test phone") async throws -> String {
        let code = try #require(r.cue.remotePairing()?.code)
        let (status, data) = try await call(port, "POST", "/api/v1/pair", json: "{\"code\":\"\(code)\",\"label\":\"\(label)\"}")
        #expect(status == 200)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["token"] as? String)
    }

    @Test func theServerIsOffByDefaultAndStartsOnlyWhenTurnedOn() async throws {
        let r = try rig()
        await r.cue.start()
        #expect(r.cue.remote.isEnabled == false && r.cue.remoteStatus.isRunning == false)
        #expect(r.cue.remotePairing() == nil)
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        #expect(r.cue.remoteStatus.isRunning && port > 0)
        #expect(r.cue.remoteStatus.addresses == ["http://127.0.0.1:\(port)"])       // loopback run: no other address is offered
        let code = try #require(r.cue.remotePairing())
        #expect(code.code.count == 6 && code.code.allSatisfy(\.isNumber))
        #expect(code.expiresAt > Date())
        await r.cue.setRemoteEnabled(false)
        #expect(r.cue.remoteStatus.isRunning == false && r.cue.remotePairing() == nil)
        await #expect(throws: (any Error).self) { _ = try await self.call(port, "GET", "/") }     // the port is released
    }

    @Test func aPhoneCanPairAndAdvanceTheShowThroughTheOneCommandPath() async throws {
        let r = try rig()
        await r.cue.start()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        #expect(try await call(port, "POST", "/api/v1/transport", json: "{\"command\":\"next\"}").0 == 401)     // no token, no command
        let token = try await pair(r, port: port)
        let (status, _) = try await call(port, "POST", "/api/v1/transport", token: token, json: "{\"command\":\"next\"}")
        #expect(status == 200)
        #expect(r.show.log == ["next begin", "next end"])
        #expect(r.cue.activity.contains { $0.source == .remote })
        #expect(r.cue.remoteStatus.devices.map(\.label) == ["Test phone"])
        await r.cue.stopRemote()
    }

    @Test func aRefusedCommandAnswersWithItsReasonAndAMacroRunsByIdOrIs404() async throws {
        let r = try rig()
        await r.cue.start()
        let timer = UUID()
        r.show.timers = [timer]
        let macro = Macro(name: "Start", steps: [.startTimer(timer)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await pair(r, port: port)
        let refused = try await call(port, "POST", "/api/v1/transport", token: token, json: "{\"command\":\"goToSlide\",\"index\":4}")
        #expect(refused.0 == 409)
        #expect(String(decoding: refused.1, as: UTF8.self).contains("Nothing is live"))
        #expect(try await call(port, "POST", "/api/v1/macros/\(macro.id.uuidString)/run", token: token).0 == 200)
        #expect(r.show.log == ["timer start"])
        #expect(try await call(port, "POST", "/api/v1/macros/\(UUID().uuidString)/run", token: token).0 == 404)
        let state = try await call(port, "GET", "/api/v1/state", token: token)
        #expect(String(decoding: state.1, as: UTF8.self).contains("Start"))                // the macro is listed on the phone
        await r.cue.stopRemote()
    }

    @Test func pairedDevicesSurviveARelaunchAsHashesAndCanBeRevoked() async throws {
        let library = try LibraryStore.inMemory()
        let first = try rig(library: library)
        await first.cue.start()
        await first.cue.setRemoteEnabled(true)
        let port1 = try #require(first.cue.remoteStatus.port)
        let token = try await pair(first, port: port1)
        await first.cue.stopRemote()
        let stored = try await library.remoteTokens()
        #expect(stored.count == 1 && stored[0].hash.count == 32)
        #expect(!String(decoding: stored[0].hash + stored[0].salt, as: UTF8.self).contains(token.split(separator: ".").last.map(String.init) ?? "?"))

        let second = try rig(library: library)
        await second.cue.start()                               // the setting was saved as on: it comes back
        let port2 = try #require(second.cue.remoteStatus.port)
        #expect(try await call(port2, "GET", "/api/v1/state", token: token).0 == 200)
        #expect(second.cue.remoteStatus.devices.count == 1)
        let id = try #require(second.cue.remoteStatus.devices.first?.id)
        await second.cue.revokeDevice(id)
        #expect(try await call(port2, "GET", "/api/v1/state", token: token).0 == 401)
        await second.cue.flushRemote()
        #expect(try await library.remoteTokens().isEmpty)
        await second.cue.stopRemote()
    }

    @Test func revokeAllRemovesEveryDevice() async throws {
        let r = try rig()
        await r.cue.start()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let a = try await pair(r, port: port, label: "A")
        let b = try await pair(r, port: port, label: "B")
        #expect(r.cue.remoteStatus.devices.count == 2)
        await r.cue.revokeAllDevices()
        #expect(try await call(port, "GET", "/api/v1/state", token: a).0 == 401)
        #expect(try await call(port, "GET", "/api/v1/state", token: b).0 == 401)
        #expect(r.cue.remoteStatus.devices.isEmpty)
        await r.cue.stopRemote()
    }

    @Test func theAddressesOfAnOpenServerAreThisMacsLocalOnes() async throws {
        let r = try rig()
        r.cue.remoteLoopbackOnly = false
        r.cue.remote.port = 8765
        r.cue.remotePortOverride = nil
        #expect(r.cue.remoteAddresses(port: 8765) == ["http://192.168.1.20:8765"])
        r.cue.localAddresses = { [] }
        #expect(r.cue.remoteAddresses(port: 8765).isEmpty)
    }
}

@MainActor
@Suite struct CUE002b_TokenStoreTests {
    func record(_ n: UInt8) -> StoredToken {
        StoredToken(id: UUID(), label: "P\(n)", salt: Data(repeating: n, count: 16), hash: Data(repeating: n, count: 32),
                    createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(n)))
    }

    @Test func changesAreSeenAtOnceAndWrittenInOrder() async throws {
        let library = try LibraryStore.inMemory()
        let store = try await LibraryTokenStore.load(from: library)
        let a = record(1), b = record(2)
        store.add(a); store.add(b)
        #expect(store.all().map(\.label) == ["P1", "P2"] && store.record(id: a.id) == a)
        _ = store.remove(id: a.id)
        await store.flush()
        #expect(try await library.remoteTokens().map(\.label) == ["P2"])
        let again = try await LibraryTokenStore.load(from: library)
        #expect(again.all().map(\.label) == ["P2"])
        again.removeAll()
        await again.flush()
        #expect(try await library.remoteTokens().isEmpty)
    }

    @Test func lastUsedIsWrittenAtMostOncePerHalfMinute() async throws {
        let library = try LibraryStore.inMemory()
        let store = try await LibraryTokenStore.load(from: library)
        let a = record(1)
        store.add(a)
        let t = Date(timeIntervalSinceReferenceDate: 800_001_000)
        store.touch(id: a.id, at: t)
        store.touch(id: a.id, at: t.addingTimeInterval(5))
        #expect(store.record(id: a.id)?.lastUsed == t.addingTimeInterval(5))             // memory is always current
        await store.flush()
        #expect(try await library.remoteTokens().first?.lastUsed == t)                   // the disk is written sparingly
        store.touch(id: a.id, at: t.addingTimeInterval(60))
        await store.flush()
        #expect(try await library.remoteTokens().first?.lastUsed == t.addingTimeInterval(60))
    }
}

@MainActor
@Suite struct CUE002b_RemoteStateTests {
    @Test func theStateReadsFromTheShowTheStageAndTheMacros() async throws {
        let library = try LibraryStore.inMemory()
        let w = WorkspaceModel(store: library)
        await w.load()
        let stage = StageModel(store: library)
        await stage.load()
        let p = try #require(await w.importLyrics(title: "Song", primaryText: "Verse 1\nOne\n\nChorus\nTwo\n\nEnding\nThree", secondaryText: nil, maxLines: 2))
        await w.addToPlaylist(p.id)
        await w.openPresentation(p.id)
        let macro = Macro(name: "Go", steps: [])
        var state = RemoteStateBuilder.make(workspace: w, stage: stage, macros: [macro])
        #expect(state.mode == .stopped && state.live == nil && state.position == nil)
        #expect(state.macros == [RemoteMacro(id: macro.id, name: "Go")])
        #expect(state.playlist.map(\.title) == ["Song"] && state.playlist.map(\.isLive) == [false])
        w.goLive(at: 1)
        state = RemoteStateBuilder.make(workspace: w, stage: stage, macros: [])
        #expect(state.mode == .live && state.live?.primary == "Two")
        #expect(state.next?.primary == "Three")
        #expect(state.position == "2 of 3" && state.presentationTitle == "Song")
        w.clear()
        #expect(RemoteStateBuilder.make(workspace: w, stage: stage, macros: []).mode == .cleared)
        w.blackout()
        #expect(RemoteStateBuilder.make(workspace: w, stage: stage, macros: []).mode == .blackedOut)
        let timer = try #require(stage.addElapsed(name: "Service"))
        stage.startTimer(timer.id)
        let timers = RemoteStateBuilder.make(workspace: w, stage: stage, macros: []).timers
        #expect(timers.map(\.name) == ["Service"] && timers.first?.isRunning == true)
    }
}
