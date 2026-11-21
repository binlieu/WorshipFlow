// UI-005b: migration v12 is additive. A library written at v11, with data in every table the new columns touch, opens at v12 with
// every row kept, libraries as songs, playlists without a service date, and props that keep the roles they were drawn on, audience and broadcast (so nothing
// disappears from a screen after the upgrade, and nothing new appears on the stage). Written with raw SQL in the v11 shape, because the v12 code writes the new columns.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct UI005b_MigrationV12Tests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-ui005b-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    private struct Ids {
        var library = UUID(), presentation = UUID(), slide = UUID(), playlist = UUID()
        var items = (song: UUID(), header: UUID(), countdown: UUID(), scripture: UUID())
        var props = (logo: UUID(), badge: UUID())
        var look = UUID()
    }

    private func writeV11(at file: URL, _ ids: Ids) async throws {
        let old = try LibraryStore.open(at: file, migratingUpTo: "v11")
        let now = Date()
        try await old.writer.write { db in
            try db.execute(sql: "INSERT INTO library (id, name, sortOrder, createdAt, updatedAt) VALUES (?, 'Songs', 0, ?, ?)",
                           arguments: [ids.library.uuidString, now, now])
            try db.execute(sql: "INSERT INTO presentation (id, libraryID, title, kind, createdAt, updatedAt) VALUES (?, ?, 'Amazing Grace', 'song', ?, ?)",
                           arguments: [ids.presentation.uuidString, ids.library.uuidString, now, now])
            try db.execute(sql: "INSERT INTO slide (id, presentationID, sortOrder, primaryText, notes, createdAt, updatedAt) VALUES (?, ?, 0, 'Amazing grace', 'note', ?, ?)",
                           arguments: [ids.slide.uuidString, ids.presentation.uuidString, now, now])
            try db.execute(sql: "INSERT INTO playlist (id, name, createdAt, updatedAt) VALUES (?, 'Sunday 9:00', ?, ?)", arguments: [ids.playlist.uuidString, now, now])
            let rows: [(UUID, UUID?, Int, String, String?)] = [
                (ids.items.song, ids.presentation, 0, "presentation", nil),
                (ids.items.header, nil, 1, "header", #"{"label":"Worship"}"#),
                (ids.items.countdown, nil, 2, "countdown", #"{"label":"Soon","mode":{"duration":{"seconds":300}}}"#),
                (ids.items.scripture, nil, 3, "scripture", PlaylistItemKind.scripture(ScriptureItemSpec(label: "Ephesians 2:1-10", ranges: [.init(book: "EPH", startChapter: 2, startVerse: 1, endChapter: 2, endVerse: 10)], primaryCode: "kjv")).stored.payload)]
            for (id, presentation, order, kind, payload) in rows {
                try db.execute(sql: "INSERT INTO playlistItem (id, playlistID, presentationID, sortOrder, createdAt, kind, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               arguments: [id.uuidString, ids.playlist.uuidString, presentation?.uuidString, order, now, kind, payload])
            }
            let frame = #"{"x":0.8,"y":0.05,"width":0.15,"height":0.1}"#
            for (id, name, on) in [(ids.props.logo, "Church logo bug", true), (ids.props.badge, "Corner badge", false)] {
                try db.execute(sql: "INSERT INTO prop (id, name, imagePath, frame, opacity, isOn, createdAt, updatedAt) VALUES (?, ?, '/x/logo.png', ?, 0.9, ?, ?, ?)",
                               arguments: [id.uuidString, name, frame, on, now, now])
            }
            try db.execute(sql: "INSERT INTO look (id, name, screens, createdAt, updatedAt) VALUES (?, 'Standard', '{}', ?, ?)", arguments: [ids.look.uuidString, now, now])
            try db.execute(sql: "INSERT INTO appState (key, value, updatedAt) VALUES ('keep.me', 'yes', ?)", arguments: [now])
        }
        try old.close()
    }

    @Test func aLibraryAtV11KeepsEveryRowAndGainsTheDefaults() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let ids = Ids()
        try await writeV11(at: file, ids)

        let new = try LibraryStore.open(at: file)
        let applied = try await new.appliedMigrations()
        #expect(Array(applied.prefix(11)) == (1...11).map { "v\($0)" } && applied.last == "v12")
        // Every row is still there.
        let libraries = try await new.libraries()
        #expect(libraries.map(\.id) == [ids.library] && libraries.first?.name == "Songs")
        #expect(libraries.first?.kind == .songs)
        #expect(try await new.presentations(in: ids.library).map(\.title) == ["Amazing Grace"])
        #expect(try await new.slides(of: ids.presentation).map(\.content.primary) == ["Amazing grace"])
        #expect(try await new.slides(of: ids.presentation).map(\.notes) == ["note"])
        let playlists = try await new.playlists()
        #expect(playlists.map(\.id) == [ids.playlist] && playlists.first?.name == "Sunday 9:00")
        #expect(playlists.first?.serviceAt == nil)
        let items = try await new.playlistItems(of: ids.playlist)
        #expect(items.map(\.id) == [ids.items.song, ids.items.header, ids.items.countdown, ids.items.scripture])
        #expect(items.map(\.title) == ["Amazing Grace", "Worship", "Soon", "Ephesians 2:1-10"])
        // Props keep the roles they were drawn on (audience and broadcast; the stage never drew them) and stay pictures: nothing
        // disappears from a screen, and nothing new appears on a stage screen.
        let props = try await new.props()
        #expect(props.map(\.id) == [ids.props.logo, ids.props.badge])
        #expect(props.allSatisfy { $0.targets == [.audience, .broadcast] && $0.kind == .image && $0.text == nil })
        #expect(props.map(\.isOn) == [true, false] && props.map(\.opacity) == [0.9, 0.9] && props.map(\.imagePath) == ["/x/logo.png", "/x/logo.png"])
        #expect(try await new.looks().map(\.name) == ["Standard"])
        #expect(try await new.state(for: "keep.me") == "yes")
    }

    @Test func theMigrationRunsOnceAndAReopenChangesNothing() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let ids = Ids()
        try await writeV11(at: file, ids)
        let first = try LibraryStore.open(at: file)
        try first.close()
        let again = try LibraryStore.open(at: file)
        #expect(try await again.appliedMigrations().filter { $0 == "v12" }.count == 1)
        let propCount = try await again.props().count, libraryCount = try await again.libraries().count
        #expect(propCount == 2 && libraryCount == 1)
        let columns = try await again.columnNames(of: "prop")
        #expect(["targets", "kind", "text"].allSatisfy(columns.contains))
        #expect(try await again.columnNames(of: "library").contains("kind"))
        #expect(try await again.columnNames(of: "playlist").contains("serviceAt"))
    }

    @Test func v12ValuesRoundTripThroughTheStore() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Sermons", kind: .sermons)
        #expect(try await store.libraries().first { $0.id == lib.id }?.kind == .sermons)
        let playlist = try await store.createPlaylist(name: "Service")
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.setPlaylistServiceDate(id: playlist.id, to: when)
        #expect(try await store.playlists().first?.serviceAt == when)
        try await store.setPlaylistServiceDate(id: playlist.id, to: nil)
        #expect(try await store.playlists().first?.serviceAt == nil)
        let strap = Prop(name: "Service title strap", imagePath: "", frame: NormalizedRect(x: 0.05, y: 0.8, width: 0.5, height: 0.1),
                         targets: [.broadcast], kind: .text, text: TextPropSpec(text: "Ân điển lạ lùng", fontSize: 54, colorHex: "#FFD17B", anchor: .bottomRight))
        try await store.saveProp(strap, bookmark: nil)
        #expect(try await store.props().first == strap)
    }
}
