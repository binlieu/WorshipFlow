// FIX-J item 4 (UI-005h): the store names what it skipped, and the models tell the operator once and keep the rest.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXJ_TolerantLoadingTests {
    typealias R = FIXJ_TolerantLoadingRuntimeTests

    /// A library with good themes "Alpha" and "Gamma", a theme row "Beta" with an unknown background kind, a Look whose row is damaged, and a
    /// stage layout whose first element has an unknown kind.
    func library() async throws -> LibraryStore {
        let store = try LibraryStore.open(at: R.file())
        try await store.saveTheme(R.theme(1, "Alpha"))
        try await store.saveTheme(R.theme(2, "Gamma"))
        try await store.saveLook(Look(id: R.uuid(1), name: "Sunday"))
        var layout = StageLayout.standard
        layout.id = R.uuid(1); layout.name = "Booth"
        try await store.saveStageLayout(layout)
        var broken = StageLayout.standard
        broken.id = R.uuid(3); broken.name = "Broken layout"
        let layoutText = try R.damaged(broken) { root in
            var elements = root["elements"] as? [[String: Any]] ?? []
            elements[0]["kind"] = ["hologram": [String: Any]()]
            root["elements"] = elements
        }
        let themeText = try R.damaged(R.theme(3, "Beta")) { $0["background"] = ["hologram": ["_0": 1]] }
        try await store.writer.write { db in
            let now = Date()
            try db.execute(sql: "INSERT INTO theme (id, name, nameFolded, definition, createdAt, updatedAt) VALUES (?, 'Beta', 'beta', ?, ?, ?)",
                           arguments: [R.uuid(3).uuidString, themeText, now, now])
            try db.execute(sql: "INSERT INTO look (id, name, screens, createdAt, updatedAt) VALUES (?, 'Broken look', ?, ?, ?)",
                           arguments: [R.uuid(3).uuidString, #"{"x":1}"#, now.addingTimeInterval(5), now])
            try db.execute(sql: "INSERT INTO stageLayout (id, name, definition, createdAt, updatedAt) VALUES (?, 'Broken layout', ?, ?, ?)",
                           arguments: [R.uuid(3).uuidString, layoutText, now.addingTimeInterval(5), now])
        }
        return store
    }

    @Test func theStoreReturnsTheGoodRowsAndNamesTheSkippedOnes() async throws {
        let store = try await library()
        let themes = try await store.themesAndSkipped()
        #expect(themes.themes.map(\.name) == ["Alpha", "Gamma"] && themes.skipped == [SkippedRow(kind: .theme, name: "Beta", id: R.uuid(3).uuidString)])
        let looks = try await store.looksAndSkipped()
        #expect(looks.looks.map(\.name) == ["Sunday"] && looks.skipped.map(\.name) == ["Broken look"])
        let layouts = try await store.stageLayoutsAndSkipped()
        #expect(layouts.layouts.map(\.name) == ["Booth"] && layouts.skipped.map(\.name) == ["Broken layout"])
    }

    @Test func aSkippedRowIsLeftInTheTableUntouched() async throws {
        let store = try await library()
        _ = try await store.themesAndSkipped()
        let count = try await store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM theme WHERE name = 'Beta'") }
        #expect(count == 1)
    }

    @Test func theSettingsModelKeepsTheGoodThemesAndLooksAndTellsTheOperatorOnce() async throws {
        let store = try await library()
        let model = SettingsModel(store: store, defaultProfiles: { [] })
        await model.load()
        #expect(model.customThemes.map(\.name).sorted() == ["Alpha", "Gamma"])
        #expect(model.looks.map(\.name).contains("Sunday"))
        let message = try #require(model.lastError)
        #expect(message.contains("\"Beta\"") && message.contains("\"Broken look\""), "\(message)")
        #expect(message.components(separatedBy: "\"Beta\"").count == 2, "named once")
        model.dismissError()
        #expect(model.lastError == nil)
    }

    @Test func theStageModelKeepsTheGoodLayoutsAndTellsTheOperatorOnce() async throws {
        let store = try await library()
        let model = StageModel(store: store)
        await model.load()
        #expect(model.customLayouts.map(\.name) == ["Booth"])
        let message = try #require(model.lastError)
        #expect(message.contains("\"Broken layout\"") && message.contains("stage layout"), "\(message)")
    }

    @Test func aCleanLibraryProducesNoNotice() async throws {
        let store = try LibraryStore.open(at: R.file())
        try await store.saveTheme(R.theme(1, "Alpha"))
        let settings = SettingsModel(store: store, defaultProfiles: { [] })
        await settings.load()
        let stage = StageModel(store: store)
        await stage.load()
        #expect(settings.lastError == nil && stage.lastError == nil)
        #expect(([] as [SkippedRow]).operatorNotice == nil)
    }

    @Test func theNoticeReadsInPlainWords() {
        let one = [SkippedRow(kind: .theme, name: "Beta", id: "x")].operatorNotice
        #expect(one == "A theme (\"Beta\") could not be read and was skipped. Everything else loaded as it was; the saved row is left untouched.")
        let two = [SkippedRow(kind: .theme, name: "A", id: "1"), SkippedRow(kind: .theme, name: nil, id: "2")].operatorNotice
        #expect(two?.hasPrefix("2 themes (\"A\", one with no readable name) could not be read and were skipped.") == true)
    }
}
