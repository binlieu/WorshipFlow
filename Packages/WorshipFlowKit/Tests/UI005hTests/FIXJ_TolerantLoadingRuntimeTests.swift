// FIX-J item 4 (UI-005h): one undecodable row must not hide the rest. Old API only, so it could be run red first (a bad row made the whole
// load throw, and the operator lost every theme, Look or stage layout).
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXJ_TolerantLoadingRuntimeTests {
    static func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixj-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
    }

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: "7E57F1A0-0000-4000-8000-0000000000B\(n)") ?? UUID() }

    /// The stored JSON of `value` with `change` applied as loose JSON (damage a typed value could not express).
    static func damaged<T: Encodable>(_ value: T, _ change: (inout [String: Any]) -> Void) throws -> String {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        change(&object)
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func theme(_ n: Int, _ name: String) -> Theme {
        var t = UI005hFixtures.userThemes[0]
        t.id = uuid(n)
        t.name = name
        return t
    }

    @Test func aThemeRowWithAnUnknownBackgroundKindDoesNotHideTheOthers() async throws {
        let store = try LibraryStore.open(at: Self.file())
        let good1 = Self.theme(1, "Alpha"), good2 = Self.theme(2, "Gamma")
        try await store.saveTheme(good1)
        try await store.saveTheme(good2)
        let bad = try Self.damaged(Self.theme(3, "Beta")) { $0["background"] = ["hologram": ["_0": 1]] }
        try await store.writer.write { db in
            let now = Date()
            try db.execute(sql: "INSERT INTO theme (id, name, nameFolded, definition, createdAt, updatedAt) VALUES (?, 'Beta', 'beta', ?, ?, ?)",
                           arguments: [Self.uuid(3).uuidString, bad, now, now])
        }
        let themes = try await store.themes()
        #expect(themes.map(\.name) == ["Alpha", "Gamma"])
    }

    @Test func aLookRowThatCannotBeReadDoesNotHideTheOthers() async throws {
        let store = try LibraryStore.open(at: Self.file())
        try await store.saveLook(Look(id: Self.uuid(1), name: "One"))
        try await store.saveLook(Look(id: Self.uuid(2), name: "Three"))
        try await store.writer.write { db in
            let now = Date()
            try db.execute(sql: "INSERT INTO look (id, name, screens, createdAt, updatedAt) VALUES (?, 'Two', ?, ?, ?)",
                           arguments: [Self.uuid(3).uuidString, #"{"not-a-screen-id":{"visibleLayers":["slide"]}}"#, now.addingTimeInterval(1), now])
        }
        #expect(try await store.looks().map(\.name).sorted() == ["One", "Three"])
    }

    @Test func aStageLayoutWithAnUnknownElementKindDoesNotHideTheOthers() async throws {
        let store = try LibraryStore.open(at: Self.file())
        var one = StageLayout.standard, two = StageLayout.standard
        one.id = Self.uuid(1); one.name = "Layout one"
        two.id = Self.uuid(2); two.name = "Layout two"
        try await store.saveStageLayout(one)
        try await store.saveStageLayout(two)
        var broken = StageLayout.standard
        broken.id = Self.uuid(3); broken.name = "Layout broken"
        let text = try Self.damaged(broken) { root in
            var elements = root["elements"] as? [[String: Any]] ?? []
            elements[0]["kind"] = ["hologram": [String: Any]()]
            root["elements"] = elements
        }
        try await store.writer.write { db in
            let now = Date()
            try db.execute(sql: "INSERT INTO stageLayout (id, name, definition, createdAt, updatedAt) VALUES (?, 'Layout broken', ?, ?, ?)",
                           arguments: [Self.uuid(3).uuidString, text, now.addingTimeInterval(1), now])
        }
        #expect(try await store.stageLayouts().map(\.name) == ["Layout one", "Layout two"])
    }
}
