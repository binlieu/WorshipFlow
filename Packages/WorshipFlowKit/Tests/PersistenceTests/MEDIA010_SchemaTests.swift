// MEDIA-010: a slide's own background and the hot folders are kept in the library without a migration (an earlier test pins
// the library at ten migrations). Existing rows are untouched; an older library opens as it was.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct MEDIA010_SchemaTests {
    @Test func noMigrationIsAddedAndNoTableOrColumnChanges() async throws {
        let store = try LibraryStore.inMemory()
        #expect(Array(try await store.appliedMigrations().prefix(10)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"])   // FIX-G: v11 follows (was: count == 10)
        #expect(!(try await store.tableNames().contains("mediaFolder")))
        #expect((try await store.columnNames(of: "slide")).contains("background"))   // FIX-G: v11 adds it (was: does not contain)
    }

    @Test func anOlderLibraryAndItsRowsAreUntouched() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-m10-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Library.sqlite")
        let old = try LibraryStore.open(at: url, migratingUpTo: "v10")
        let library = try await old.createLibrary(name: "Songs")
        let song = try await old.createPresentation(in: library.id, title: "Amazing Grace", kind: .song)
        _ = try await old.appendSlide(to: song.id, content: SlideContent(primary: "Amazing grace"))
        try old.close()
        let new = try LibraryStore.open(at: url)
        #expect(Array(try await new.appliedMigrations().prefix(10)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"])
        #expect(try await new.libraries().map(\.name) == ["Songs"])
        let slides = try await new.slides(of: song.id)
        #expect(slides.map(\.content.primary) == ["Amazing grace"] && slides.first?.content.background == nil)
        #expect(try await new.mediaFolders().isEmpty)
    }

    @Test func aSlideBackgroundRoundTripsThroughAppendAndUpdateAndAReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-m10b-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: url)
        let library = try await store.createLibrary(name: "Songs")
        let song = try await store.createPresentation(in: library.id, title: "S", kind: .song)
        let video = MediaSelection(assetID: UUID(), kind: .video, duration: 12.5)
        let added = try await store.appendSlide(to: song.id, content: SlideContent(primary: "one", background: video))
        #expect(added.content.background == video)
        var plain = try await store.appendSlide(to: song.id, content: SlideContent(primary: "two"))
        #expect(plain.content.background == nil)
        plain.content.background = MediaSelection(assetID: UUID(), kind: .image, duration: nil)
        try await store.updateSlide(plain)
        #expect(try await store.slides(of: song.id).map(\.content.background) == [video, plain.content.background])
        try store.close()
        let again = try LibraryStore.open(at: url)
        var slides = try await again.slides(of: song.id)
        #expect(slides.map(\.content.background) == [video, plain.content.background])
        slides[1].content.background = nil
        try await again.updateSlide(slides[1])
        #expect(try await again.slides(of: song.id).map(\.content.background) == [video, nil])
        #expect(slides.map(\.content.primary) == ["one", "two"], "the words are untouched")
    }

    @Test func editingWordsKeepsTheBackgroundAndDeletingThePresentationRemovesIt() async throws {
        let store = try LibraryStore.inMemory()
        let library = try await store.createLibrary(name: "Songs")
        let song = try await store.createPresentation(in: library.id, title: "S", kind: .song)
        let video = MediaSelection(assetID: UUID(), kind: .video, duration: 3)
        var slide = try await store.appendSlide(to: song.id, content: SlideContent(primary: "one", background: video))
        slide.content.primary = "edited"
        try await store.updateSlide(slide)
        #expect(try await store.slides(of: song.id).first?.content.background == video)
        #expect(try await store.slideBackgroundCount() == 1)   // FIX-G: stored with the slide (was: an appState key)
        try await store.deletePresentation(id: song.id)
        #expect(try await store.state(for: "slideBackgrounds.\(song.id.uuidString)") == nil)
    }

    @Test func aSlideWithoutABackgroundWritesNothingExtra() async throws {
        let store = try LibraryStore.inMemory()
        let library = try await store.createLibrary(name: "Songs")
        let song = try await store.createPresentation(in: library.id, title: "S", kind: .song)
        var slide = try await store.appendSlide(to: song.id, content: SlideContent(primary: "one"))
        slide.content.primary = "two"
        try await store.updateSlide(slide)
        #expect(try await store.state(for: "slideBackgrounds.\(song.id.uuidString)") == nil)
    }

    @Test func hotFoldersAreSavedInOrderUpdatedAndRemoved() async throws {
        let store = try LibraryStore.inMemory()
        let a = HotFolder(name: "Loops", path: "/v/loops", bookmark: Data([9, 9]))
        let b = HotFolder(name: "Sunday", path: "/v/sunday", bookmark: nil)
        try await store.saveMediaFolder(a)
        try await store.saveMediaFolder(b)
        #expect(try await store.mediaFolders() == [a, b])
        var moved = a
        moved.path = "/v/elsewhere"
        moved.bookmark = nil
        try await store.saveMediaFolder(moved)
        #expect(try await store.mediaFolders() == [moved, b], "an edited folder keeps its place")
        try await store.removeMediaFolder(id: a.id)
        #expect(try await store.mediaFolders() == [b])
        try await store.removeMediaFolder(id: b.id)
        #expect(try await store.mediaFolders().isEmpty)
        #expect(try await store.state(for: "media.hotFolders") == nil)
    }
}
