// SLIDE-001a: object storage beyond the coordinator's acceptance tests: older stores, arrangements, playlists, search paths.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct SlideObjectStoreExtraTests {
    private func text(_ words: String) -> SlideObject {
        SlideObject(frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2),
                    content: .text(TextObject(text: words, style: TextStyle(fontName: "Helvetica Neue", fontSize: 50, color: .white))))
    }
    private func shape() -> SlideObject {
        SlideObject(frame: .full, opacity: 0.4, content: .shape(ShapeObject(shape: .roundedRectangle(cornerRadius: 0.2), fill: .black, strokeColor: .white, strokeWidth: 3)))
    }
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
    }

    @Test func plainSlidesStoreNullAndStillWorkOnEveryOlderSchema() async throws {
        for version in ["v1", "v2", "v3", "v4"] {
            let store = try LibraryStore.open(at: tempURL(), migratingUpTo: version)
            let lib = try await store.createLibrary(name: "L")
            let p = try await store.createPresentation(in: lib.id, title: "Old \(version)", kind: .song)
            var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", secondary: "một"))
            slide.content.primary = "two"
            try await store.updateSlide(slide)                                      // no objects: no objects column needed
            #expect(try await store.slides(of: p.id).map(\.content) == [SlideContent(primary: "two", secondary: "một")])
            #expect(try await store.search("two", limit: 5).map(\.presentationID) == [p.id])
            try store.close()
        }
    }

    @Test func plainSlidesLeaveTheColumnNullAndSlidesWithObjectsFillIt() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "T", kind: .sermon)
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "plain"))
        var withObjects = try await store.appendSlide(to: p.id, content: SlideContent(primary: "with", objects: [shape()]))
        let values = try await store.writer.read { db in try String?.fetchAll(db, sql: "SELECT objects FROM slide ORDER BY sortOrder") }
        #expect(values.count == 2 && values[0] == nil && values[1] != nil)
        // Clearing the objects stores NULL again.
        withObjects.content.objects = []
        try await store.updateSlide(withObjects)
        let cleared = try await store.writer.read { db in try String?.fetchAll(db, sql: "SELECT objects FROM slide ORDER BY sortOrder") }
        #expect(cleared == [nil, nil])
    }

    @Test func objectsSurviveArrangementsAndPlaylistItems() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "T", kind: .sermon)
        let objects = [shape(), text("Hello")]
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "a", objects: objects))
        #expect(try await store.resolvedSlides(of: p.id, arrangementID: nil).first?.content.objects == objects)
        let playlist = try await store.createPlaylist(name: "Sunday")
        let item = try await store.addPresentation(p.id, to: playlist.id)
        #expect(try await store.slides(forPlaylistItem: item.id).first?.content.objects == objects)
    }

    @Test func replaceContentDropsObjects() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "T", kind: .song)
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "a", objects: [text("gone words")]))
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "x\ny", secondary: nil, maxLines: 2))
        #expect(try await store.slides(of: p.id).allSatisfy { $0.content.objects.isEmpty })
        #expect(try await store.search("gone", limit: 5).isEmpty)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func textBoxWordsAreSearchableOnBothPathsAndShapesAddNoWords(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try LibraryStore.inMemory(forcing: backend)
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "Talk", kind: .sermon)
        var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "", objects: [text("Điểm thứ nhất"), shape()]))
        #expect(try await store.search("diem thu", limit: 5).map(\.presentationID) == [p.id])
        slide.content.objects = [shape()]                                             // text box removed
        try await store.updateSlide(slide)
        #expect(try await store.search("diem", limit: 5).isEmpty)
        try await store.deleteSlide(id: slide.id)
    }

    @Test func unreadableObjectsReadAsNoneWithoutFailingTheList() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "T", kind: .sermon)
        let slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "keep", objects: [shape()]))
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE slide SET objects = '{not json' WHERE id = ?", arguments: [slide.id.dbText])
        }
        let read = try await store.slides(of: p.id)
        #expect(read.count == 1 && read[0].content == SlideContent(primary: "keep"))
    }

    @Test func objectsOnAPreV5StoreFailLoudlyInsteadOfBeingDropped() async throws {
        let store = try LibraryStore.open(at: tempURL(), migratingUpTo: "v4")
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "T", kind: .sermon)
        var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "a"))
        slide.content.objects = [shape()]
        await #expect(throws: (any Error).self) { try await store.updateSlide(slide) }
        await #expect(throws: (any Error).self) { _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "b", objects: [shape()])) }
        try store.close()
    }
}
