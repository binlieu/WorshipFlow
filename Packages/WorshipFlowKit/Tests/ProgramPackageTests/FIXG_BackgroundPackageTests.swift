// FIX-G item 2 (LIB-005): the program package carries a slide's own background: the file in media/, a relative reference on the
// slide. Import restores it. A package written before this change still imports.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXG_BackgroundPackageTests {
    @Test func aSlidesOwnBackgroundTravelsAndComesBackWithItsFile() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let selection = try await home.giveSermonABackground()
        let package = try await home.export()

        // The file is in media/ and the slide refers to it by a relative path; nothing absolute or personal is written.
        let manifest = try String(contentsOf: package.appendingPathComponent("program.json"), encoding: .utf8)
        #expect(!manifest.contains(rig.root.path) && !manifest.contains("ExternalDrive"))
        let contents = try ProgramPackageContents.open(package)
        let slide = try #require(contents.document.presentations.first { $0.id == home.songTwo }?.slides.first)
        let entry = try #require(slide.background)
        #expect(entry.assetID == selection.assetID && entry.kind == .video && entry.duration == 3)
        #expect(ProgramPathRules.isSafePackagePath(entry.file))
        #expect(contents.document.media.contains { $0.file == entry.file && $0.status == .included })
        #expect(contents.document.mediaAssets.contains { $0.id == selection.assetID })

        try FileManager.default.removeItem(at: rig.url("ExternalDrive"))
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await home.sermonBackgrounds(in: church) == [selection, nil])
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == selection.assetID })
        #expect(try Data(contentsOf: URL(fileURLWithPath: asset.path)) == rig.bytes(seed: 4, count: 5_000))
    }

    @Test func aPackageWrittenBeforeTheFieldExistedStillImports() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await home.giveSermonABackground()
        let package = try await home.export()
        try editSlides(package) { $0.removeValue(forKey: "background") }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await home.sermonBackgrounds(in: church) == [nil, nil])
        #expect(try await church.slides(of: home.songTwo).map(\.content.primary) == ["Point one", "Point two"])
    }

    @Test func twoPresentationsThatDifferOnlyInABackgroundAreNotTheSame() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await home.giveSermonABackground()
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await ProgramImporter.summarize(contents, into: church).isNothingToImport)
        var slides = try await church.slides(of: home.songTwo)
        slides[0].content.background = nil
        try await church.updateSlide(slides[0])
        let summary = try await ProgramImporter.summarize(contents, into: church)
        #expect(summary.conflicting == ["Invented Sermon"])
    }

    @Test func keepBothAndUseImportedBothCarryTheBackground() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let selection = try await home.giveSermonABackground()
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        var slides = try await church.slides(of: home.songTwo)
        slides[0].content.background = nil
        try await church.updateSlide(slides[0])

        let both = try await ProgramImporter.apply(contents, into: church, choice: .keepBoth)
        #expect(both.presentationsKeptAsCopies >= 1)
        let library = try #require(try await church.libraries().first)
        let copies = try await church.presentations(in: library.id).filter { $0.title == "Invented Sermon (imported)" }
        let copyID = try #require(copies.first).id
        #expect(try await church.slides(of: copyID).map(\.content.background) == [selection, nil])
        #expect(try await church.slides(of: home.songTwo).map(\.content.background) == [nil, nil], "the library's own is left alone")

        _ = try await ProgramImporter.apply(contents, into: church, choice: .useImported)
        #expect(try await home.sermonBackgrounds(in: church) == [selection, nil])
    }

    @Test func aBackgroundFileThatTheMediaListDoesNotCoverIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await home.giveSermonABackground()
        let package = try await home.export()
        try editSlides(package) { slide in
            if var b = slide["background"] as? [String: Any] { b["file"] = "media/0000000000000000000000000000000000000000000000000000000000000000.mov"; slide["background"] = b }
        }
        #expect(throws: ProgramPackageError.self) { try ProgramPackageContents.open(package) }
        try editSlides(package) { slide in
            if var b = slide["background"] as? [String: Any] { b["file"] = "/etc/hosts"; slide["background"] = b }
        }
        #expect(throws: ProgramPackageError.self) { try ProgramPackageContents.open(package) }
    }
}
