// STAGE-001a acceptance tests, persistence half (schema v4). Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct StageStoreTests {
    @Test func schemaV4AddsStageTables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        #expect(tables.contains("stageLayout") && tables.contains("showTimer"))
        #expect(Array(try await store.appliedMigrations().prefix(4)) == ["v1", "v2", "v3", "v4"])
    }

    @Test func v3RowsSurviveV4() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
        let old = try LibraryStore.open(at: url, migratingUpTo: "v3")
        let lib = try await old.createLibrary(name: "Songs")
        let look = Look(id: UUID(), name: "Worship", screens: [:])
        try await old.saveLook(look)
        try old.close()
        let new = try LibraryStore.open(at: url)
        #expect(try await new.libraries().map(\.id) == [lib.id])
        #expect(try await new.looks() == [look])
        #expect(try await new.stageLayouts().isEmpty)
        try new.close()
    }

    @Test func stageLayoutsRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        var custom = StageLayout.standard
        custom = StageLayout(id: UUID(), name: "Band", background: .black, elements: custom.elements)
        try await store.saveStageLayout(custom)
        #expect(try await store.stageLayouts() == [custom])                 // the built-in layout is not stored
        var edited = custom; edited.name = "Band and choir"; edited.elements.removeLast()
        try await store.saveStageLayout(edited)
        #expect(try await store.stageLayouts() == [edited])
        try await store.deleteStageLayout(id: custom.id)
        #expect(try await store.stageLayouts().isEmpty)
        await #expect(throws: StoreError.notFound) { try await store.deleteStageLayout(id: custom.id) }
        await #expect(throws: StoreError.self) { try await store.saveStageLayout(.standard) }
        await #expect(throws: StoreError.self) { try await store.deleteStageLayout(id: StageLayout.standard.id) }
    }

    /// A running countdown survives a relaunch with the right time.
    @Test func timersRoundTripWhileRunning() async throws {
        let store = try LibraryStore.inMemory()
        var sermon = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 1800))
        let service = ShowTimer(id: UUID(), name: "Service", kind: .elapsed)
        try await store.saveTimer(sermon)
        try await store.saveTimer(service)
        sermon.start(at: 1000)
        try await store.saveTimer(sermon)
        let loaded = try await store.timers()
        #expect(loaded == [sermon, service])                                // creation order
        #expect(loaded[0].value(at: 1060) == 1740)
        try await store.deleteTimer(id: service.id)
        #expect(try await store.timers().map(\.name) == ["Sermon"])
    }
}
