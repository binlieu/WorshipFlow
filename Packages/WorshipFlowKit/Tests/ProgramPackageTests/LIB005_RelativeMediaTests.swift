// LIB-005 item 3 and 5: imported media is referenced relative to the library's folder, so it still resolves after the folder moves.
import Testing
import Foundation
import Domain
import GRDB
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct LIB005_RelativeMediaTests {
    @Test func movingTheLibraryFolderAfterAnImportStillResolvesEveryMedia() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)

        // What the library file holds is relative.
        let stored = try await church.programRead { db in
            try String.fetchAll(db, sql: "SELECT objects FROM slide WHERE objects IS NOT NULL")
                + String.fetchAll(db, sql: "SELECT definition FROM theme")
                + String.fetchAll(db, sql: "SELECT path FROM mediaAsset")
        }
        #expect(stored.count == 4)
        for text in stored.map({ $0.replacingOccurrences(of: "\\/", with: "/") }) {
            #expect(text.contains("Media/Imported/"))
            #expect(!text.contains(rig.root.path) && !text.contains("/church/"))
        }

        try church.close()
        let moved = rig.url("moved", "somewhere else")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: rig.url("church"), to: moved)
        let reopened = try LibraryStore.open(at: moved.appendingPathComponent("Library.sqlite"))

        var checked = 0
        for item in try await reopened.playlistItems(of: home.playlistID) where item.kind == .presentation {
            for slide in try await reopened.slides(of: item.presentationID) {
                for case .image(let image) in slide.content.objects.map(\.content) {
                    #expect(image.path.hasPrefix(moved.standardizedFileURL.path + "/Media/Imported/"))
                    #expect(FileManager.default.fileExists(atPath: image.path))
                    checked += 1
                }
            }
        }
        #expect(checked == 3)
        let theme = try #require(try await reopened.themes().first)
        guard case .image(let themePath) = theme.background else { Issue.record("no picture"); return }
        #expect(FileManager.default.fileExists(atPath: themePath) && themePath.hasPrefix(moved.standardizedFileURL.path))
        let asset = try #require(try await reopened.mediaAssets(kind: nil).first)
        #expect(FileManager.default.fileExists(atPath: asset.path) && asset.path.hasPrefix(moved.standardizedFileURL.path))
    }

    @Test func theStoreKeepsAPathInsideItsManagedFolderRelativeAndResolvesItAfterTheFolderMoves() async throws {
        let rig = try Rig()
        var store = try rig.openStore("lib")
        let folder = rig.url("lib")
        let library = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: library.id, title: "T", kind: .song)
        var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "x"))
        let inside = folder.standardizedFileURL.path + "/Media/Imported/prog/pic.png"
        slide.content.objects = [SlideObject(frame: .full, content: .image(ImageObject(path: inside)))]
        try await store.updateSlide(slide)
        let raw = try await store.programRead { db in try String.fetchOne(db, sql: "SELECT objects FROM slide") ?? "" }
            .replacingOccurrences(of: "\\/", with: "/")      // the column escapes slashes
        #expect(raw.contains("\"Media/Imported/prog/pic.png\"") && !raw.contains(folder.path))
        try store.close()
        let moved = rig.url("elsewhere", "lib2")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: moved)
        store = try LibraryStore.open(at: moved.appendingPathComponent("Library.sqlite"))
        guard case .image(let image) = try await store.slides(of: p.id)[0].content.objects[0].content else { Issue.record("no image"); return }
        #expect(image.path == moved.standardizedFileURL.path + "/Media/Imported/prog/pic.png")
    }

    @Test func editingAnImportedSlideKeepsItsMediaRelative() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(try await home.export()), into: church)
        var slide = try await church.slides(of: home.songOne)[1]
        slide.notes = "edited at church"
        try await church.updateSlide(slide)                 // the app hands the objects back with absolute paths
        let slideID = slide.id.uuidString
        let text = try await church.programRead { db in
            try String.fetchOne(db, sql: "SELECT objects FROM slide WHERE id = ?", arguments: [slideID]) ?? ""
        }
        let plain = text.replacingOccurrences(of: "\\/", with: "/")
        #expect(plain.contains("Media/Imported/") && !plain.contains(rig.root.path))
    }

    @Test func aFilesOwnPathOutsideTheManagedFolderIsLeftAsItIs() async throws {
        let rig = try Rig()
        let store = try rig.openStore("lib")
        let library = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: library.id, title: "T", kind: .song)
        var slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "x"))
        slide.content.objects = [SlideObject(frame: .full, content: .image(ImageObject(path: "/some/where/else/pic.png")))]
        try await store.updateSlide(slide)
        let read = try await store.slides(of: p.id)
        guard case .image(let image) = read[0].content.objects[0].content else { Issue.record("no image"); return }
        #expect(image.path == "/some/where/else/pic.png")
        // An in-memory library has no folder, so nothing is rewritten there either.
        let memory = try LibraryStore.inMemory()
        let lib = try await memory.createLibrary(name: "M")
        let q = try await memory.createPresentation(in: lib.id, title: "T", kind: .song)
        var s2 = try await memory.appendSlide(to: q.id, content: SlideContent(primary: "x"))
        s2.content.objects = [SlideObject(frame: .full, content: .image(ImageObject(path: "Media/Imported/x/y.png")))]
        try await memory.updateSlide(s2)
        guard case .image(let kept) = try await memory.slides(of: q.id)[0].content.objects[0].content else { Issue.record("no image"); return }
        #expect(kept.path == "Media/Imported/x/y.png")
    }

    @Test func aStoredPathWithAParentPartIsNeverTurnedIntoAFilePathOutsideTheLibrary() async throws {
        let rig = try Rig()
        let store = try rig.openStore("lib")
        let library = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: library.id, title: "T", kind: .song)
        let slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "x"))
        let evil = #"[{"id":"\#(UUID().uuidString)","frame":{"x":0,"y":0,"width":1,"height":1},"opacity":1,"content":{"image":{"_0":{"path":"Media/Imported/../../../etc/hosts","contentMode":"fit"}}}}]"#
        try await store.programWrite { db, _ in
            try db.execute(sql: "UPDATE slide SET objects = ? WHERE id = ?", arguments: [evil, slide.id.uuidString])
        }
        guard case .image(let image) = try await store.slides(of: p.id)[0].content.objects[0].content else { Issue.record("no image"); return }
        #expect(!image.path.hasPrefix("/"))
    }
}
