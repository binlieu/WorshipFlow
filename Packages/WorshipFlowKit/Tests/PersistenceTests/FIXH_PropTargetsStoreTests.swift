// FIX-H item 9 (UI-005b): a damaged prop `targets` value fell back to every role, including the stage. The documented default is
// audience and broadcast.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXH_PropTargetsStoreTests {
    private func prop(_ store: LibraryStore, id: UUID, targets: String?) async throws {
        try await store.writer.write { db in
            try db.execute(sql: "INSERT INTO prop (id, name, imagePath, frame, opacity, isOn, createdAt, updatedAt, targets, kind, text) VALUES (?, 'p', '/x.png', ?, 1, 1, ?, ?, ?, 'image', NULL)",
                           arguments: [id.uuidString, #"{"x":0,"y":0,"width":1,"height":1}"#, Date(), Date(), targets])
        }
    }

    @Test func aDamagedTargetsValueReadsAsAudienceAndBroadcast() async throws {
        let store = try LibraryStore.inMemory()
        let a = UUID(), b = UUID(), c = UUID()
        try await prop(store, id: a, targets: "{not json")
        try await prop(store, id: b, targets: #"["audience","from-a-newer-build"]"#)
        try await prop(store, id: c, targets: #"["stage"]"#)
        let read = Dictionary(uniqueKeysWithValues: try await store.props().map { ($0.id, $0.targets) })
        #expect(read[a] == [.audience, .broadcast])           // not the stage
        #expect(read[b] == [.audience, .broadcast])
        #expect(read[c] == [.stage])                           // a real value is kept
    }

    @Test func aStoreOpenedBeforeV12ReadsPropsAsAudienceAndBroadcast() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try LibraryStore.open(at: dir.appendingPathComponent("Library.sqlite"), migratingUpTo: "v11")
        try await old.writer.write { db in
            try db.execute(sql: "INSERT INTO prop (id, name, imagePath, frame, opacity, isOn, createdAt, updatedAt) VALUES (?, 'p', '/x.png', ?, 1, 1, ?, ?)",
                           arguments: [UUID().uuidString, #"{"x":0,"y":0,"width":1,"height":1}"#, Date(), Date()])
        }
        #expect(try await old.props().map(\.targets) == [[.audience, .broadcast]])
        try old.close()
    }
}
