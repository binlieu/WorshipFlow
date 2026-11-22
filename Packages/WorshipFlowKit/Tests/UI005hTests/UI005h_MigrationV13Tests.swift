// UI-005h item 5: migration v13 is additive. A library written at v12 with a church's own themes opens at v13 with every row kept,
// every stored theme definition byte for byte, and every user theme drawing the pixels it drew before. Existing libraries (those that
// have a presentation or a theme) gain two "Classic" themes holding the previous built-in looks, so a church can go back; a library
// with nothing in it gains none. Written with raw SQL in the v12 shape, because the v13 code knows the new fields.
import Testing
import Foundation
import GRDB
import Domain
import RenderEngine
@testable import Persistence

@Suite struct UI005h_MigrationV13Tests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-ui005h-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
    }
    private let library = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let presentation = UUID(uuidString: "11111111-0000-4000-8000-000000000002")!
    private let slide = UUID(uuidString: "11111111-0000-4000-8000-000000000003")!

    /// A v12 library: one library, one presentation using the first user theme, one slide, the user themes as the v12 code stored them.
    private func writeV12(at file: URL, themes: [Theme], withContent: Bool = true) async throws -> [String: String] {
        let old = try LibraryStore.open(at: file, migratingUpTo: "v12")
        let now = Date()
        var definitions: [String: String] = [:]
        for theme in themes { definitions[theme.id.uuidString] = try SettingsJSON.encode(theme) }
        let stored = definitions
        try await old.writer.write { db in
            if withContent {
                try db.execute(sql: "INSERT INTO library (id, name, sortOrder, createdAt, updatedAt) VALUES (?, 'Songs', 0, ?, ?)", arguments: [library.uuidString, now, now])
                try db.execute(sql: "INSERT INTO presentation (id, libraryID, title, kind, themeID, createdAt, updatedAt) VALUES (?, ?, 'Amazing Grace', 'song', ?, ?, ?)",
                               arguments: [presentation.uuidString, library.uuidString, themes.first?.id.uuidString, now, now])
                try db.execute(sql: "INSERT INTO slide (id, presentationID, sortOrder, primaryText, createdAt, updatedAt) VALUES (?, ?, 0, 'Amazing grace', ?, ?)",
                               arguments: [slide.uuidString, presentation.uuidString, now, now])
                try db.execute(sql: "INSERT INTO appState (key, value, updatedAt) VALUES ('keep.me', 'yes', ?)", arguments: [now])
            }
            for theme in themes {
                let text = stored[theme.id.uuidString] ?? ""
                try db.execute(sql: "INSERT INTO theme (id, name, nameFolded, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                               arguments: [theme.id.uuidString, theme.name, SearchFolding.fold(theme.name), text, now, now])
            }
        }
        try old.close()
        return definitions
    }

    private func digest(_ theme: Theme, _ compositor: Compositor) throws -> String {
        UI005hFixtures.digest(try UI005hFixtures.frames(of: theme, compositor: compositor)[0])
    }

    @Test func aV12LibraryKeepsEveryRowAndEveryUserThemeDrawsTheSamePixels() async throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let stored = try await writeV12(at: file, themes: UI005hFixtures.userThemes)
        let compositor = try Compositor()

        // Before: what the v12 library holds and draws.
        let before = try LibraryStore.open(at: file, migratingUpTo: "v12")
        #expect(try await before.appliedMigrations().count == 12)
        let themesBefore = try await before.themes()
        #expect(themesBefore.count == 4)
        let digestsBefore = try Dictionary(uniqueKeysWithValues: themesBefore.map { ($0.name, try digest($0, compositor)) })
        #expect(digestsBefore == UI005h_Golden.userThemeAudience, "the v12 picture is the one recorded before this slice")
        try before.close()

        // After: opened by this build.
        let after = try LibraryStore.open(at: file)
        let applied = try await after.appliedMigrations()
        #expect(Array(applied.prefix(12)) == (1...12).map { "v\($0)" } && applied.last == "v13")
        let rows = try after.writer.read { db in try Row.fetchAll(db, sql: "SELECT id, definition FROM theme") }
        for (id, text) in stored {                                                  // the church's definitions are untouched, byte for byte
            #expect(rows.first { ($0["id"] as String) == id }.map { $0["definition"] as String } == text, "definition of \(id)")
        }
        let themesAfter = try await after.themes()
        #expect(themesAfter.filter { stored.keys.contains($0.id.uuidString) } == themesBefore.sorted { $0.name.lowercased() < $1.name.lowercased() }.sortedLike(themesAfter))
        let digestsAfter = try Dictionary(uniqueKeysWithValues: themesAfter.filter { stored.keys.contains($0.id.uuidString) }.map { ($0.name, try digest($0, compositor)) })
        #expect(digestsAfter == digestsBefore, "every user theme renders pixel-identical before and after")
        #expect(digestsAfter == UI005h_Golden.userThemeAudience)
        // The broadcast picture of the keyed user theme is also unchanged.
        let keyed = try #require(themesAfter.first { $0.name == "Keyed plain" })
        #expect(UI005hFixtures.digest(try UI005hFixtures.frames(of: keyed, compositor: compositor)[1]) == UI005h_Golden.userThemeAudience["Keyed plain"])

        // Every other row is where it was.
        #expect(try await after.libraries().map(\.id) == [library])
        #expect(try await after.presentations(in: library).map(\.title) == ["Amazing Grace"])
        #expect(try await after.presentations(in: library).first?.themeID == UI005hFixtures.userThemes[0].id)
        #expect(try await after.slides(of: presentation).map(\.content.primary) == ["Amazing grace"])
        let keep = try await after.writer.read { db in try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = 'keep.me'") }
        #expect(keep == "yes")
    }

    @Test func anExistingLibraryGainsTheTwoClassicThemesWhichDrawTheOldBuiltInLooks() async throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        _ = try await writeV12(at: file, themes: UI005hFixtures.userThemes)
        let store = try LibraryStore.open(at: file)
        let themes = try await store.themes()
        let classic = try #require(themes.first { $0.id == Theme.classicFullScreenID }), lower = try #require(themes.first { $0.id == Theme.classicLowerThirdID })
        #expect(classic == Theme.classicFullScreen && lower == Theme.classicLowerThird)
        #expect(classic.name == "Classic full screen" && lower.name == "Classic lower third" && themes.count == 6)
        let compositor = try Compositor()
        #expect(UI005hFixtures.digest(try UI005hFixtures.frames(of: classic, compositor: compositor)[0]) == UI005h_Golden.oldFullScreenAudience)
        #expect(UI005hFixtures.digest(try UI005hFixtures.frames(of: lower, compositor: compositor)[1]) == UI005h_Golden.oldLowerThirdBroadcast)
        // The Classic rows are the church's to rename, edit or delete, like any theme.
        var renamed = classic; renamed.name = "Last year's look"
        try await store.saveTheme(renamed)
        try await store.deleteTheme(id: Theme.classicLowerThirdID)
        #expect(try await store.themes().map(\.name).sorted() == ["Last year's look", "Keyed plain", "Loop with shadow", "Missing picture", "Sunday blue"].sorted())
        try store.close()
        // Opening again does not bring a deleted one back, and does not add a second copy.
        let again = try LibraryStore.open(at: file)
        let countAgain = try await again.themes().count
        let v13Count = try await again.appliedMigrations().filter { $0 == "v13" }.count
        #expect(countAgain == 5 && v13Count == 1)
    }

    @Test func aLibraryWithNothingInItGainsNoThemes() async throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        _ = try await writeV12(at: file, themes: [], withContent: false)
        let store = try LibraryStore.open(at: file)
        let none = try await store.themes().isEmpty, last = try await store.appliedMigrations().last
        #expect(none && last == "v13")
        let fresh = try LibraryStore.inMemory()
        #expect(try await fresh.themes().isEmpty)
    }

    @Test func aLibraryWithPresentationsButNoThemesStillGainsTheClassicOnes() async throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        _ = try await writeV12(at: file, themes: [])
        let themes = try await LibraryStore.open(at: file).themes()
        let ids = Set(themes.map(\.id))
        #expect(ids == Set([Theme.classicFullScreenID, Theme.classicLowerThirdID]) && themes.count == 2)
    }

    @Test func aChurchThemeNamedLikeAClassicOneKeepsItsOwnRow() async throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var mine = UI005hFixtures.userThemes[0]; mine.name = "Classic full screen"
        _ = try await writeV12(at: file, themes: [mine])
        let themes = try await LibraryStore.open(at: file).themes()
        #expect(themes.count == 3 && themes.contains(mine) && themes.contains { $0.id == Theme.classicFullScreenID })
    }
}

private extension Array where Element == Theme {
    /// This array's themes in the order `other` lists them (by id), so two lists of the same themes compare equal.
    func sortedLike(_ other: [Theme]) -> [Theme] {
        let order = Dictionary(uniqueKeysWithValues: other.enumerated().map { ($1.id, $0) })
        return sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}
