// FIX-N item 2 (FIX-K): a hostile `slide.textFrames` value in the library file is read as no override, whatever put it there.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXN_FrameValidationStoreTests {
    private func setUp() async throws -> (LibraryStore, Presentation, Slide) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        let slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", secondary: "một"))
        return (store, p, slide)
    }

    private func store(_ json: String, in store: LibraryStore, slide: Slide) async throws {
        try await store.writer.write { db in try db.execute(sql: "UPDATE slide SET textFrames = ? WHERE id = ?", arguments: [json, slide.id.dbText]) }
    }

    @Test func hostileStoredFramesAreReadAsNoOverride() async throws {
        let (db, p, slide) = try await setUp()
        for json in [#"{"primary":{"x":0.1,"y":0.1,"width":0,"height":0.3}}"#, #"{"primary":{"x":0.5,"y":0.1,"width":-0.3,"height":0.3}}"#,
                     #"{"primary":{"x":4,"y":4,"width":0.3,"height":0.3}}"#, #"{"secondary":{"x":0.1,"y":-9,"width":0.3,"height":0.3}}"#,
                     #"{"primary":{"x":1e300,"y":1e300,"width":1e300,"height":1e300}}"#] {
            try await store(json, in: db, slide: slide)
            #expect(try await db.slides(of: p.id).first?.content.textFrames == nil, "\(json)")
        }
    }

    @Test func aStoredFrameHangingOverTheEdgeIsClampedAndAGoodOneIsKept() async throws {
        let (db, p, slide) = try await setUp()
        try await store(#"{"primary":{"x":0.9,"y":0.1,"width":0.4,"height":0.2},"secondary":{"x":0.1,"y":0.6,"width":0.5,"height":0.2}}"#, in: db, slide: slide)
        let frames = try #require(try await db.slides(of: p.id).first?.content.textFrames)
        #expect(abs((frames.primary?.x ?? 9) - 0.6) < 1e-12 && frames.primary?.width == 0.4)
        #expect(frames.secondary == NormalizedRect(x: 0.1, y: 0.6, width: 0.5, height: 0.2))
    }
}
