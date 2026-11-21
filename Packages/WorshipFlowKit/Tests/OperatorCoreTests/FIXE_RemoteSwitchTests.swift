// FIX-E item 3 and 9: switching the remote server on and off cannot interleave (the last request wins and the saved setting matches
// what is listening), and the network addresses are not looked up every second. A fake server stands in; nothing listens.
import Testing
import Foundation
import CueStore
import Persistence
import RemoteControl
@testable import OperatorCore

@MainActor
@Suite struct FIXE_RemoteSwitchTests {
    final class Calls: @unchecked Sendable { var n = 0 }

    func rig() throws -> (cue: CueModel, servers: FakeServers, library: LibraryStore, calls: Calls) {
        let library = try LibraryStore.inMemory()
        let show = FakeShow()
        let cue = CueModel(store: CueStore(library: library), ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { nil }),
                           clock: TestCueClock(), settingsStore: library)
        let servers = FakeServers()
        cue.remoteServerFactory = servers.factory()
        cue.watchesNetwork = false
        let calls = Calls()
        cue.localAddresses = { calls.n += 1; return ["192.168.1.20"] }
        return (cue, servers, library, calls)
    }

    func savedEnabled(_ library: LibraryStore) async throws -> Bool? {
        guard let text = try await library.state(for: CueModel.remoteKey) else { return nil }
        return try JSONDecoder().decode(RemoteSettings.self, from: Data(text.utf8)).isEnabled
    }

    @Test func onThenOnAgainStartsOneServer() async throws {
        let r = try rig()
        r.servers.holdFirst = 1
        async let first: Void = r.cue.setRemoteEnabled(true)
        await r.servers.until { r.servers.all.first?.startCalls == 1 }
        async let second: Void = r.cue.setRemoteEnabled(true)
        for _ in 0..<50 { await Task.yield() }
        r.servers.all[0].release()
        _ = await (first, second)
        #expect(r.servers.all.count == 1)
        #expect(r.servers.all[0].isRunning && r.servers.all[0].startCalls == 1)
        #expect(r.cue.remoteStatus.isRunning)
        #expect(try await savedEnabled(r.library) == true)
        await r.cue.stopRemote()
    }

    @Test func onThenOffDuringTheStartEndsWithNothingListeningAndTheSettingOff() async throws {
        let r = try rig()
        r.servers.holdFirst = 1
        async let on: Void = r.cue.setRemoteEnabled(true)
        await r.servers.until { r.servers.all.first?.startCalls == 1 }
        async let off: Void = r.cue.setRemoteEnabled(false)
        for _ in 0..<50 { await Task.yield() }
        r.servers.all[0].release()
        _ = await (on, off)
        #expect(r.servers.all.allSatisfy { !$0.isRunning })
        #expect(r.servers.all.count == 1 && r.servers.all[0].stopCalls == 1)
        #expect(r.cue.remoteStatus.isRunning == false)
        #expect(r.cue.remote.isEnabled == false)
        #expect(try await savedEnabled(r.library) == false)
    }

    @Test func aPortChangeDuringAStartEndsListeningOnTheNewPortOnly() async throws {
        let r = try rig()
        r.servers.holdFirst = 1
        async let on: Void = r.cue.setRemoteEnabled(true)
        await r.servers.until { r.servers.all.first?.startCalls == 1 }
        async let change: Void = r.cue.setRemotePort(9100)
        for _ in 0..<50 { await Task.yield() }
        r.servers.all[0].release()
        _ = await (on, change)
        let listening = r.servers.all.filter(\.isRunning)
        #expect(listening.count == 1 && listening[0].configuration.port == 9100)
        #expect(r.cue.remoteStatus.port == 9100)
        #expect(r.cue.remote.port == 9100 && r.cue.remote.isEnabled)
        let saved = try #require(try await r.library.state(for: CueModel.remoteKey))
        #expect(try JSONDecoder().decode(RemoteSettings.self, from: Data(saved.utf8)).port == 9100)
        await r.cue.stopRemote()
    }

    @Test func theAddressesAreLookedUpWhenTheServerStartsAndWhenTheNetworkChangesNotEverySecond() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        #expect(r.calls.n == 1)
        for _ in 0..<10 { r.cue.refreshRemote() }                        // the app's one-second tick
        #expect(r.calls.n == 1)
        #expect(r.cue.remoteStatus.addresses.count == 1)
        r.cue.networkChanged()
        #expect(r.calls.n == 2)
        await r.cue.stopRemote()
        r.cue.refreshRemote()
        r.cue.networkChanged()
        #expect(r.calls.n == 2)                                          // nothing runs while the server is off
    }
}
