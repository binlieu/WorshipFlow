// CUE-002b item 5: paired devices of the remote control server are kept in the library (migration v10) as salted hashes.
import Testing
import Foundation
import GRDB
@testable import Persistence

@Suite struct CUE002b_RemoteTokenTests {
    func record(_ label: String = "Phone", id: UUID = UUID(), at: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> RemoteTokenRecord {
        RemoteTokenRecord(id: id, label: label, salt: Data(repeating: 1, count: 16), hash: Data(repeating: 2, count: 32), createdAt: at, lastUsed: nil)
    }

    @Test func v10IsTheNextMigrationAndCreatesTheTokenTable() async throws {
        let store = try LibraryStore.inMemory()
        let applied = try await store.appliedMigrations()
        #expect(Array(applied.prefix(10)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"])
        #expect(try await store.tableNames().contains("remoteToken"))
    }

    @Test func v10LeavesAnOlderLibraryAndItsRowsAlone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-v10-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Library.sqlite")
        let old = try LibraryStore.open(at: url, migratingUpTo: "v9")
        _ = try await old.createLibrary(name: "Songs")
        try old.close()
        let new = try LibraryStore.open(at: url)
        #expect(try await new.libraries().map(\.name) == ["Songs"])
        #expect(try await new.appliedMigrations().filter { $0 == "v10" }.count == 1)
        #expect(try await new.remoteTokens().isEmpty)
    }

    @Test func recordsRoundTripAndAreListedOldestFirst() async throws {
        let store = try LibraryStore.inMemory()
        let a = record("A", at: Date(timeIntervalSinceReferenceDate: 800_000_100))
        let b = record("B", at: Date(timeIntervalSinceReferenceDate: 800_000_000))
        try await store.saveRemoteToken(a)
        try await store.saveRemoteToken(b)
        let all = try await store.remoteTokens()
        #expect(all.map(\.label) == ["B", "A"])
        #expect(all.first { $0.id == a.id } == a)
    }

    @Test func touchDeleteAndDeleteAll() async throws {
        let store = try LibraryStore.inMemory()
        let a = record("A"), b = record("B")
        try await store.saveRemoteToken(a)
        try await store.saveRemoteToken(b)
        let when = Date(timeIntervalSinceReferenceDate: 800_001_000)
        try await store.touchRemoteToken(id: a.id, at: when)
        #expect(try await store.remoteTokens().first { $0.id == a.id }?.lastUsed == when)
        try await store.deleteRemoteToken(id: a.id)
        #expect(try await store.remoteTokens().map(\.label) == ["B"])
        try await store.deleteAllRemoteTokens()
        #expect(try await store.remoteTokens().isEmpty)
    }

    @Test func savingAgainReplacesTheRowAndNothingStoresATokenSecret() async throws {
        let store = try LibraryStore.inMemory()
        var a = record("A")
        try await store.saveRemoteToken(a)
        a.label = "Renamed"
        try await store.saveRemoteToken(a)
        #expect(try await store.remoteTokens().map(\.label) == ["Renamed"])
        let columns = try await store.rawColumnNames(of: "remoteToken")
        #expect(Set(columns) == ["id", "label", "salt", "hash", "createdAt", "lastUsed"])     // a hash and a salt, never the token
    }
}
