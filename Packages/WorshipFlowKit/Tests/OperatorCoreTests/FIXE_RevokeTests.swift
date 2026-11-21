// FIX-E item 1: a revoke is written before it is reported done; a failed write is retried and then told to the operator; the token
// is refused at once either way. Real loopback sockets (always stopped), the real library in memory, a store whose writes can fail.
import Testing
import Foundation
import CueStore
import Persistence
import RemoteControl
@testable import OperatorCore

@MainActor
@Suite struct FIXE_RevokeTests {
    struct Rig { var cue: CueModel; var library: LibraryStore; var flaky: FlakyTokenPersistence }

    func rig() throws -> Rig {
        let library = try LibraryStore.inMemory()
        let flaky = FlakyTokenPersistence(library)
        let show = FakeShow()
        let cue = CueModel(store: CueStore(library: library), ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { nil }),
                           clock: TestCueClock(), settingsStore: library)
        cue.remoteLoopbackOnly = true
        cue.remotePortOverride = 0
        cue.tokenPersistence = flaky
        cue.tokenRetryDelay = .zero
        return Rig(cue: cue, library: library, flaky: flaky)
    }

    func call(_ port: UInt16, _ method: String, _ path: String, token: String? = nil, json: String? = nil) async throws -> Int {
        try await fixeCall(port, method, path, token: token, json: json).0
    }

    func pair(_ r: Rig, port: UInt16, label: String = "Phone") async throws -> String {
        try await fixePair(r.cue, port: port, label: label)
    }

    func untilPaired(_ r: Rig, _ count: Int) async {
        for _ in 0..<20_000 where r.cue.remoteStatus.devices.count < count { await Task.yield() }
    }

    func transport(_ r: Rig, port: UInt16, token: String) async throws -> Int {
        try await call(port, "POST", "/api/v1/transport", token: token, json: "{\"command\":\"next\"}")
    }

    @Test func aFailedRevokeIsToldToTheOperatorAndTheDeviceIsRefusedAtOnce() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await pair(r, port: port)
        await r.cue.flushRemote()
        await untilPaired(r, 1)
        let id = try #require(r.cue.remoteStatus.devices.first?.id)
        r.flaky.failDeletes(99)
        await r.cue.revokeDevice(id)
        let notice = try #require(r.cue.notices.first { $0.text.contains("not saved") })
        #expect(notice.text.contains("connect again after WORSHIPFLOW restarts"))
        #expect(r.cue.activity.contains { $0.isProblem && $0.text.contains("not saved") })
        #expect(try await transport(r, port: port, token: token) == 401)          // refused now, whatever the disk did
        await r.cue.stopRemote()
    }

    @Test func aFailedRevokeAllIsToldToTheOperatorToo() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await pair(r, port: port)
        await r.cue.flushRemote()
        r.flaky.failDeletes(99)
        await r.cue.revokeAllDevices()
        #expect(r.cue.notices.contains { $0.text.contains("Revoke all is not saved") })
        #expect(try await transport(r, port: port, token: token) == 401)
        await r.cue.stopRemote()
    }

    @Test func aWriteThatFailsOnceIsRetriedAndNothingIsReported() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        _ = try await pair(r, port: port)
        await r.cue.flushRemote()
        await untilPaired(r, 1)
        let id = try #require(r.cue.remoteStatus.devices.first?.id)
        r.flaky.failDeletes(1)
        await r.cue.revokeDevice(id)
        #expect(r.cue.notices.contains { $0.text.contains("not saved") } == false)
        #expect(try await r.library.remoteTokens().isEmpty)
        await r.cue.stopRemote()
    }

    @Test func aRevokeIsOnDiskByTheTimeItReturns() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        _ = try await pair(r, port: port, label: "One")
        _ = try await pair(r, port: port, label: "Two")
        await r.cue.flushRemote()
        #expect(try await r.library.remoteTokens().count == 2)
        r.flaky.slowDeletes.withLock { $0 = 500 }
        await untilPaired(r, 2)
        let id = try #require(r.cue.remoteStatus.devices.first?.id)
        await r.cue.revokeDevice(id)
        #expect(try await r.library.remoteTokens().count == 1)         // no flush in between
        await r.cue.revokeAllDevices()
        #expect(try await r.library.remoteTokens().isEmpty)
        await r.cue.stopRemote()
    }

    @Test func aRevokedTokenIsStillRefusedAfterTheServerIsSwitchedOffAndOn() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        let token = try await pair(r, port: port)
        await r.cue.flushRemote()
        await untilPaired(r, 1)
        let id = try #require(r.cue.remoteStatus.devices.first?.id)
        await r.cue.revokeDevice(id)
        await r.cue.stopRemote()
        await r.cue.setRemoteEnabled(true)
        let again = try #require(r.cue.remoteStatus.port)
        #expect(try await transport(r, port: again, token: token) == 401)
        await r.cue.stopRemote()
    }

    @Test func aPairingWhoseWriteFailsIsReported() async throws {
        let r = try rig()
        await r.cue.setRemoteEnabled(true)
        let port = try #require(r.cue.remoteStatus.port)
        r.flaky.failSaves(99)
        _ = try await pair(r, port: port)
        await r.cue.flushRemote()
        for _ in 0..<20_000 where !r.cue.notices.contains(where: { $0.text.contains("could not be saved") }) { await Task.yield() }
        #expect(r.cue.notices.contains { $0.text.contains("could not be saved") && $0.text.contains("pair again after a restart") || $0.text.contains("Paired devices could not be saved") })
        await r.cue.stopRemote()
    }

    @Test func theStoreReturnsAWriteProblemFromFlush() async throws {
        let library = try LibraryStore.inMemory()
        let flaky = FlakyTokenPersistence(library)
        let store = try await LibraryTokenStore.load(from: flaky, retryDelay: .zero)
        let record = StoredToken(id: UUID(), label: "X", salt: Data([1]), hash: Data([2]), createdAt: Date(timeIntervalSince1970: 100))
        store.add(record)
        #expect(await store.flush() == nil)
        flaky.failDeletes(99)
        #expect(store.remove(id: record.id))
        #expect(store.record(id: record.id) == nil)                   // gone from memory at once
        let problem = await store.flush()
        #expect(problem?.contains("could not be saved") == true)
        #expect(await store.flush() == nil)                          // reported once
    }
}
