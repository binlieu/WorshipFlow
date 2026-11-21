// FIX-E: fakes for the review fixes: a remote server whose start can be held, and a token store whose writes can be made to fail.
import Foundation
import Testing
import Synchronization
import Persistence
import RemoteControl
@testable import OperatorCore

/// Plays `RemoteServing`. `start()` can be held until `release()`. State is behind a lock because `start()` runs off the main actor.
final class FakeRemoteServer: RemoteServing, @unchecked Sendable {
    private struct State {
        var running = false
        var startCalls = 0
        var stopCalls = 0
        var waiting: CheckedContinuation<Void, Never>?
        var released = false
    }
    private let state = Mutex(State())
    let configuration: RemoteServerConfiguration
    let hold: Bool

    init(configuration: RemoteServerConfiguration, hold: Bool) {
        self.configuration = configuration
        self.hold = hold
    }

    var startCalls: Int { state.withLock { $0.startCalls } }
    var stopCalls: Int { state.withLock { $0.stopCalls } }
    var isRunning: Bool { state.withLock { $0.running } }
    var port: UInt16? { isRunning ? configuration.port : nil }
    var currentPairingCode: String { "123456" }
    var pairingCodeExpiresAt: Date { Date().addingTimeInterval(120) }
    func listTokens() -> [TokenInfo] { [] }
    func revoke(id: UUID) {}
    func revokeAll() {}
    func setEventHandler(_ h: (@Sendable (RemoteServerEvent) -> Void)?) {}
    func stateDidChange() {}

    func start() async throws -> UInt16 {
        state.withLock { $0.startCalls += 1 }
        if hold {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { s -> Bool in
                    if s.released { return true }
                    s.waiting = c
                    return false
                }
                if resumeNow { c.resume() }
            }
        }
        state.withLock { $0.running = true }
        return configuration.port
    }

    func stop() async { state.withLock { $0.running = false; $0.stopCalls += 1 } }

    func release() {
        let c = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.released = true
            defer { s.waiting = nil }
            return s.waiting
        }
        c?.resume()
    }
}

@MainActor
final class FakeServers {
    var all: [FakeRemoteServer] = []
    /// How many of the first servers made are held in `start()`.
    var holdFirst = 0

    func factory() -> (any RemoteControlTarget, any TokenStore, RemoteServerConfiguration) -> any RemoteServing {
        { [unowned self] _, _, configuration in
            MainActor.assumeIsolated {
                let server = FakeRemoteServer(configuration: configuration, hold: all.count < holdFirst)
                all.append(server)
                return server
            }
        }
    }

    /// Gives other tasks the turn until the condition holds (bounded; no clock).
    func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<20_000 where !condition() { await Task.yield() }
    }
}

/// The library, with writes that can be made to fail a set number of times.
final class FlakyTokenPersistence: RemoteTokenPersistence, Sendable {
    let base: LibraryStore
    private let failures = Mutex<(saves: Int, deletes: Int)>((0, 0))
    init(_ base: LibraryStore) { self.base = base }

    struct Refused: Error, LocalizedError { var errorDescription: String? { "the disk refused the write" } }

    /// Deletes give way to other tasks this many times first, so a read that does not wait for the write sees the old data.
    let slowDeletes = Mutex(0)
    func failSaves(_ n: Int) { failures.withLock { $0.saves = n } }
    func failDeletes(_ n: Int) { failures.withLock { $0.deletes = n } }

    func remoteTokens() async throws -> [RemoteTokenRecord] { try await base.remoteTokens() }
    func saveRemoteToken(_ record: RemoteTokenRecord) async throws {
        if failures.withLock({ f -> Bool in if f.saves > 0 { f.saves -= 1; return true }; return false }) { throw Refused() }
        try await base.saveRemoteToken(record)
    }
    func deleteRemoteToken(id: UUID) async throws {
        for _ in 0..<slowDeletes.withLock({ $0 }) { await Task.yield() }
        if failures.withLock({ f -> Bool in if f.deletes > 0 { f.deletes -= 1; return true }; return false }) { throw Refused() }
        try await base.deleteRemoteToken(id: id)
    }
    func deleteAllRemoteTokens() async throws {
        for _ in 0..<slowDeletes.withLock({ $0 }) { await Task.yield() }
        if failures.withLock({ f -> Bool in if f.deletes > 0 { f.deletes -= 1; return true }; return false }) { throw Refused() }
        try await base.deleteAllRemoteTokens()
    }
    func touchRemoteToken(id: UUID, at date: Date) async throws { try await base.touchRemoteToken(id: id, at: date) }
}

// MARK: A phone, over real loopback sockets

func fixeCall(_ port: UInt16, _ method: String, _ path: String, token: String? = nil, json: String? = nil) async throws -> (Int, Data) {
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

@MainActor
func fixePair(_ cue: CueModel, port: UInt16, label: String = "Phone") async throws -> String {
    let code = try #require(cue.remotePairing()?.code)
    let (_, data) = try await fixeCall(port, "POST", "/api/v1/pair", json: "{\"code\":\"\(code)\",\"label\":\"\(label)\"}")
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(object["token"] as? String)
}
