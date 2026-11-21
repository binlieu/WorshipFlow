// FIX-G item 2 (MEDIA-010, KI-100): a slide's own background is stored with the slide (migration v11, a nullable column).
// The migration moves the old appState entries across, drops the stale ones and touches nothing else.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXG_SlideBackgroundStoreTests {
    let video = MediaSelection(assetID: UUID(), kind: .video, duration: 12.5)
    let picture = MediaSelection(assetID: UUID(), kind: .image, duration: nil)

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixg-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    private func json(_ dict: [String: MediaSelection]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(dict), as: UTF8.self)
    }

    // MARK: The migration

    @Test func v11MovesEveryAppStateEntryIntoItsSlideAndRemovesIt() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = try LibraryStore.open(at: file, migratingUpTo: "v10")
        #expect(try await old.appliedMigrations().count == 10)
        let lib = try await old.createLibrary(name: "Songs")
        let a = try await old.createPresentation(in: lib.id, title: "A", kind: .song)
        let b = try await old.createPresentation(in: lib.id, title: "B", kind: .song)
        let a1 = try await old.appendSlide(to: a.id, content: SlideContent(primary: "a one"))
        let a2 = try await old.appendSlide(to: a.id, content: SlideContent(primary: "a two"))
        let a3 = try await old.appendSlide(to: a.id, content: SlideContent(primary: "a three"))
        let b1 = try await old.appendSlide(to: b.id, content: SlideContent(primary: "b one"))
        // Written the way the media slice wrote them: per presentation, keyed by the upper-case slide id. One entry is for a
        // slide that no longer exists; another presentation id does not exist at all; one value is damaged.
        let ghost = UUID()
        try await old.setState(try json([a1.id.uuidString: video, a3.id.uuidString: picture, ghost.uuidString: video]),
                               for: "slideBackgrounds.\(a.id.uuidString)")
        try await old.setState(try json([b1.id.uuidString: picture]), for: "slideBackgrounds.\(b.id.uuidString)")
        let nobody = UUID()
        try await old.setState(try json([UUID().uuidString: video]), for: "slideBackgrounds.\(nobody.uuidString)")
        try await old.setState("{not json", for: "slideBackgrounds.\(UUID().uuidString)")
        try await old.setState("keep me", for: "unrelated.key")
        try old.close()

        let new = try LibraryStore.open(at: file)
        let applied = try await new.appliedMigrations()
        #expect(Array(applied.prefix(10)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"])
        #expect(applied.last == "v11" && applied.count == 11)
        #expect(try await new.columnNames(of: "slide").contains("background"))
        #expect(try await new.slides(of: a.id).map(\.content.background) == [video, nil, picture])
        #expect(try await new.slides(of: b.id).map(\.content.background) == [picture])
        // Existing rows are otherwise untouched.
        #expect(try await new.slides(of: a.id).map(\.id) == [a1.id, a2.id, a3.id])
        #expect(try await new.slides(of: a.id).map(\.content.primary) == ["a one", "a two", "a three"])
        #expect(try await new.libraries().map(\.name) == ["Songs"])
        #expect(try await new.state(for: "unrelated.key") == "keep me")
        // The old entries are gone, the stale ones with them.
        #expect(try await new.state(for: "slideBackgrounds.\(a.id.uuidString)") == nil)
        #expect(try await new.state(for: "slideBackgrounds.\(b.id.uuidString)") == nil)
        #expect(try await new.state(for: "slideBackgrounds.\(nobody.uuidString)") == nil)
        #expect(try await new.stateKeys(prefix: "slideBackgrounds.").isEmpty)
        try new.close()
        let again = try LibraryStore.open(at: file)
        #expect(try await again.appliedMigrations().filter { $0 == "v11" }.count == 1)
        #expect(try await again.slides(of: a.id).map(\.content.background) == [video, nil, picture])
    }

    @Test func aLibraryWithNoEntriesMigratesToo() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = try LibraryStore.open(at: file, migratingUpTo: "v10")
        let lib = try await old.createLibrary(name: "Songs")
        let p = try await old.createPresentation(in: lib.id, title: "A", kind: .song)
        _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: "one"))
        try old.close()
        let new = try LibraryStore.open(at: file)
        #expect(try await new.slides(of: p.id).map(\.content.background) == [nil])
    }

    // MARK: Stored with the slide

    @Test func aBackgroundIsWrittenToTheSlideAndNeverToAppState() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "S", kind: .song)
        var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", background: video))
        slide.content.background = picture
        try await store.updateSlide(slide)
        #expect(try await store.slides(of: p.id).first?.content.background == picture)
        #expect(try await store.stateKeys(prefix: "slideBackgrounds.").isEmpty)
    }

    @Test func deletingASlideLeavesNothingBehindAndDeletingThePresentationToo() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "S", kind: .song)
        let s1 = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", background: video))
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "two", background: picture))
        try await store.deleteSlide(id: s1.id)
        #expect(try await store.slides(of: p.id).map(\.content.background) == [picture])
        #expect(try await store.slideBackgroundCount() == 1)
        try await store.deletePresentation(id: p.id)
        #expect(try await store.slideBackgroundCount() == 0)
    }

    // MARK: Re-flow

    @Test func aReflowCarriesTheBackgroundByTheSameMatchAsNotes() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "S", kind: .song)
        var one = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", background: video))
        one.notes = "slow"
        try await store.updateSlide(one)
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "two", background: picture))
        let results = [ReflowResult(sectionName: nil, content: SlideContent(primary: "one")),
                       ReflowResult(sectionName: nil, content: SlideContent(primary: "three"))]
        let losses = try await store.reflowLosses(of: p.id, with: results)
        #expect(losses.count == 1 && losses.first?.primary == "two" && losses.first?.hasBackground == true)
        try await store.replaceContent(of: p.id, with: results)
        let after = try await store.slides(of: p.id)
        #expect(after.map(\.content.primary) == ["one", "three"])
        #expect(after.map(\.notes) == ["slow", ""])
        #expect(after.map(\.content.background) == [video, nil])
    }
}
