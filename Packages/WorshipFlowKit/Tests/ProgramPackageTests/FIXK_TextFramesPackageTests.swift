// FIX-K item 3 (LIB-005): the program package carries a slide's own text frames. They are fractions of the frame, so nothing about them is a path or a
// machine. A package written before the field existed still imports, and two presentations that differ only in a frame are not the same.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXK_TextFramesPackageTests {
    let own = SlideTextFrames(primary: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25), secondary: nil)

    private func giveFrames(_ home: HomeProgram) async throws {
        var slides = try await home.store.slides(of: home.songTwo)
        slides[0].content.textFrames = own
        try await home.store.updateSlide(slides[0])
    }

    @Test func framesTravelInTheManifestAndComeBackOnImport() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await giveFrames(home)
        let package = try await home.export()
        let contents = try ProgramPackageContents.open(package)
        let entry = try #require(contents.document.presentations.first { $0.id == home.songTwo }?.slides.first)
        #expect(entry.textFrames == own)
        let manifest = try String(contentsOf: package.appendingPathComponent("program.json"), encoding: .utf8)
        #expect(!manifest.contains(rig.root.path))

        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await church.slides(of: home.songTwo).map(\.content.textFrames) == [own, nil])
    }

    @Test func aPackageWrittenBeforeTheFieldExistedStillImports() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await giveFrames(home)
        let package = try await home.export()
        try editSlides(package) { $0.removeValue(forKey: "textFrames") }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.slides(of: home.songTwo).map(\.content.textFrames) == [nil, nil])
    }

    @Test func aSlideWithoutFramesWritesNoKey() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let text = try String(contentsOf: package.appendingPathComponent("program.json"), encoding: .utf8)
        #expect(!text.contains("textFrames"))
    }

    @Test func twoPresentationsThatDifferOnlyInAFrameAreNotTheSame() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await giveFrames(home)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await ProgramImporter.summarize(contents, into: church).isNothingToImport)
        var slides = try await church.slides(of: home.songTwo)
        slides[0].content.textFrames = nil
        try await church.updateSlide(slides[0])
        #expect(try await ProgramImporter.summarize(contents, into: church).conflicting == ["Invented Sermon"])
    }
}
