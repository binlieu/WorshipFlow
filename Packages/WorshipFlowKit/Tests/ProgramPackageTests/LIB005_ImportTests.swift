// LIB-005 items 3 and 5: importing a program and the round trip from one library into another.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct LIB005_ImportTests {
    @Test func aRoundTripIntoAnEmptyLibraryPlaysTheSameSlideForSlide() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let expected = try await describe(home.store, playlist: home.playlistID)
        let themeBytes = try Data(contentsOf: home.background)

        // The drive the pictures were on is not at church.
        try FileManager.default.removeItem(at: rig.url("ExternalDrive"))

        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        let result = try await ProgramImporter.apply(contents, into: church)
        #expect(result.playlistID == home.playlistID)
        #expect(try await describe(church, playlist: home.playlistID) == expected)
        #expect(!expected.contains { $0.contains("MISSING") })
        #expect(expected.count >= 14)

        // Themes, Looks and media assets arrived and their files read back as the same bytes.
        let themes = try await church.themes()
        #expect(themes.map(\.name) == ["Sky"])
        if case .image(let path) = themes[0].background { #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == themeBytes) }
        else { Issue.record("theme lost its picture") }
        #expect(try await church.looks().map(\.name) == ["Morning"])
        let assets = try await church.mediaAssets(kind: nil)
        #expect(assets.map(\.id) == [home.assetID])
        #expect(try Data(contentsOf: URL(fileURLWithPath: assets[0].path)) == rig.bytes(seed: 4, count: 5_000))
        #expect(assets[0].duration == 3 && assets[0].pixelWidth == 640)

        // The slide actions came with their slides, unknown kinds included.
        let actions = try await church.programRead { db in
            try String.fetchAll(db, sql: "SELECT definition FROM cueSlideActions")
        }
        #expect(actions.count == 1)
        #expect(actions[0].contains("future.thing") && actions[0].contains(home.assetID.uuidString.lowercased()))
        // Ids are kept: the same playlist, items, presentations.
        #expect(try await church.playlistItems(of: home.playlistID).map(\.id) == home.items.map(\.id))
    }

    @Test func importingTwiceCreatesNoDuplicates() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        let counts = try await rowCounts(church)
        let files = rig.listing(rig.url("church", "Media"))
        #expect(counts["presentation"] == 2 && counts["playlist"] == 1 && counts["playlistItem"] == 5)

        let second = try await ProgramImporter.summarize(contents, into: church)
        #expect(second.isNothingToImport)
        #expect(second.alreadyPresent.sorted() == ["Invented Song One", "Invented Sermon"].sorted())
        #expect(second.playlist == .alreadyPresent)
        let again = try await ProgramImporter.apply(contents, into: church)
        #expect(again.presentationsAdded == 0 && again.mediaFilesCopied == 0)
        #expect(try await rowCounts(church) == counts)
        #expect(rig.listing(rig.url("church", "Media")) == files)
    }

    @Test func theSummaryTellsWhatIsNewBeforeAnythingIsWritten() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try FileManager.default.removeItem(at: home.imageC)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let summary = try await ProgramImporter.summarize(try ProgramPackageContents.open(package), into: church)
        #expect(summary.playlistName == "Sunday plan" && summary.playlist == .new)
        #expect(summary.newPresentations.sorted() == ["Invented Sermon", "Invented Song One"])
        #expect(summary.alreadyPresent.isEmpty && summary.conflicting.isEmpty && !summary.hasConflicts)
        #expect(summary.newThemes == 1 && summary.newLooks == 1 && summary.newMediaAssets == 1)
        #expect(summary.mediaFilesToCopy == 3 && summary.mediaBytesToCopy == 2_000 + 2_000 + 5_000)
        #expect(summary.missingMedia == ["c.jpg"])
        #expect(summary.scriptureNotInstalled == ["John 3:16 (inv)"])
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church", "Media")).isEmpty)
    }

    /// A church library that already has the home program, then the home copy of one song is edited.
    private func clash(_ rig: Rig) async throws -> (church: LibraryStore, package: URL, home: HomeProgram) {
        let home = try await HomeProgram.make(rig)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(try await home.export(as: "First")), into: church)
        // At church somebody changes a lyric; at home the same song is changed differently.
        var churchSlides = try await church.slides(of: home.songOne)
        churchSlides[0].content.primary = "Church changed this line"
        try await church.updateSlide(churchSlides[0])
        var homeSlides = try await home.store.slides(of: home.songOne)
        homeSlides[0].content.primary = "Home changed this line"
        try await home.store.updateSlide(homeSlides[0])
        let second = try await home.export(as: "Second")
        return (church, second, home)
    }

    @Test func anIdClashAsksOnceAndTheDefaultKeepsBoth() async throws {
        let rig = try Rig()
        let (church, package, home) = try await clash(rig)
        let contents = try ProgramPackageContents.open(package)
        let summary = try await ProgramImporter.summarize(contents, into: church)
        #expect(summary.conflicting == ["Invented Song One"] && summary.hasConflicts)
        #expect(summary.alreadyPresent == ["Invented Sermon"])
        #expect(ProgramConflictChoice.default == .keepBoth)
        let result = try await ProgramImporter.apply(contents, into: church)
        #expect(result.presentationsKeptAsCopies == 1)
        let all = try await church.presentations(in: church.onlyLibraryID())
        let titles = all.map(\.title).sorted()
        #expect(titles == ["Invented Sermon", "Invented Song One", "Invented Song One (imported)"])
        let mine = try await church.slides(of: home.songOne)
        #expect(mine[0].content.primary == "Church changed this line")
        let copy = try #require(all.first { $0.title.hasSuffix("(imported)") })
        #expect(copy.id != home.songOne)
        let copySlides = try await church.slides(of: copy.id)
        #expect(copySlides[0].content.primary == "Home changed this line")
        #expect(copySlides.count == 3)
        // Its own arrangement and sections, none shared with the original.
        let originalGroups = Set(try await church.groups(of: home.songOne).map(\.id))
        let copyGroups = Set(try await church.groups(of: copy.id).map(\.id))
        #expect(copyGroups.count == 2 && originalGroups.isDisjoint(with: copyGroups))
        // The program as prepared at home has to play the imported text, so its playlist is kept next to the library's own.
        let playlists = try await church.playlists()
        #expect(playlists.map(\.name).sorted() == ["Sunday plan", "Sunday plan (imported)"])
        let imported = try #require(playlists.first { $0.name == "Sunday plan (imported)" })
        #expect(result.playlistID == imported.id && imported.id != home.playlistID)
        let importedItems = try await church.playlistItems(of: imported.id)
        #expect(importedItems.map(\.title) == ["Worship", "Invented Song One (imported)", "Start", "Invented Sermon", "John 3:16 (inv)"])
        #expect(Set(importedItems.map(\.id)).isDisjoint(with: Set(home.items.map(\.id))))
        #expect(try await church.playlistItems(of: home.playlistID).map(\.title).contains("Invented Song One"))
    }

    @Test func keepMineLeavesTheLibraryWithItsOwnVersion() async throws {
        let rig = try Rig()
        let (church, package, home) = try await clash(rig)
        let result = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church, choice: .keepMine)
        #expect(result.presentationsKeptAsCopies == 0 && result.presentationsReplaced == 0)
        #expect(try await church.presentations(in: church.onlyLibraryID()).count == 2)
        #expect(try await church.slides(of: home.songOne)[0].content.primary == "Church changed this line")
        #expect(try await church.playlists().count == 1 && result.playlistID == home.playlistID)
    }

    @Test func useImportedReplacesTheLibrarysVersionWithTheImportedOne() async throws {
        let rig = try Rig()
        let (church, package, home) = try await clash(rig)
        let result = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church, choice: .useImported)
        #expect(result.presentationsReplaced == 1)
        #expect(try await church.presentations(in: church.onlyLibraryID()).count == 2)
        let slides = try await church.slides(of: home.songOne)
        #expect(slides.count == 3 && slides[0].content.primary == "Home changed this line")
        // The search index follows the replaced text in the same transaction.
        #expect(try await church.search("Home changed", limit: 5).map(\.presentationID) == [home.songOne])
        #expect(try await church.search("Church changed", limit: 5).isEmpty)
        #expect(try await church.playlistItems(of: home.playlistID).map(\.id) == home.items.map(\.id))
        #expect(try await church.playlists().count == 1 && result.playlistID == home.playlistID)
    }

    @Test func aFailureInTheMiddleOfAnImportLeavesTheLibraryAndTheMediaFolderAsTheyWere() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        _ = try await church.createLibrary(name: "Existing")
        let before = try await rowCounts(church)
        let contents = try ProgramPackageContents.open(package)

        await #expect(throws: Boom.self) {
            _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(insideTransaction: { throw Boom() }))
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church", "Media")).isEmpty)

        await #expect(throws: Boom.self) {
            _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(afterMediaCopied: { throw Boom() }))
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church", "Media")).isEmpty)

        // And a cancel part way through the copying.
        let polls = Counter()
        await #expect(throws: ProgramPackageError.cancelled) {
            _ = try await ProgramImporter.apply(contents, into: church, isCancelled: { polls.next() > 2 })
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church", "Media")).isEmpty)

        // The same import then works, so nothing was left half-done.
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await rowCounts(church)["presentation"] == 2)
    }

    @Test func aFailureKeepsMediaThatWasAlreadyThereFromAnEarlierImport() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(try await home.export())
        _ = try await ProgramImporter.apply(contents, into: church)
        let files = rig.listing(rig.url("church", "Media"))
        #expect(!files.isEmpty)
        // Same program again with a changed song, so it has something to write, and a failure at the end.
        var slides = try await home.store.slides(of: home.songOne)
        slides[0].content.primary = "Edited"
        try await home.store.updateSlide(slides[0])
        let again = try ProgramPackageContents.open(try await home.export(as: "Again"))
        await #expect(throws: Boom.self) {
            _ = try await ProgramImporter.apply(again, into: church, hooks: ProgramImportHooks(insideTransaction: { throw Boom() }))
        }
        #expect(rig.listing(rig.url("church", "Media")) == files)
    }

    @Test func identicalMediaAlreadyInTheManagedFolderIsReusedNotCopiedAgain() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(try await home.export())
        let first = try await ProgramImporter.apply(contents, into: church)
        #expect(first.mediaFilesCopied == 4 && first.mediaFilesReused == 0)
        var slides = try await home.store.slides(of: home.songOne)
        slides[0].content.primary = "Edited"
        try await home.store.updateSlide(slides[0])
        let again = try ProgramPackageContents.open(try await home.export(as: "Again"))
        let second = try await ProgramImporter.apply(again, into: church, choice: .keepBoth)
        // The copy of the song uses two different pictures (the two copies of one picture are one file): both are already there.
        #expect(second.mediaFilesCopied == 0 && second.mediaFilesReused == 2)
        let managed = rig.listing(rig.url("church", "Media", "Imported", home.playlistID.uuidString))
        #expect(managed.count == 4)
    }

    @Test func aScriptureItemRoundTripsAsAReferenceWithoutAnyVerseText() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let text = try String(contentsOf: package.appendingPathComponent("program.json"), encoding: .utf8)
        #expect(!text.contains(HomeProgram.verseMarker) && !text.contains(HomeProgram.verseMarker.lowercased()))
        #expect(text.contains("inv-en") && text.contains("JHN"))
        let all = await rig.listing(package).asyncCount { entry in
            let url = package.appendingPathComponent(entry)
            guard let data = FileManager.default.contents(atPath: url.path) else { return false }
            return String(decoding: data, as: UTF8.self).contains(HomeProgram.verseMarker)
        }
        #expect(all == 0)

        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        let items = try await church.playlistItems(of: home.playlistID)
        #expect(items.last?.kind == .scripture(home.scriptureSpec))
        // The translation is not installed in the church library: the item imports and the existing state shows it.
        let counts = try await rowCounts(church)
        #expect(counts["scriptureTranslation"] == 0 && counts["scriptureVerse"] == 0)
    }

    @Test func importingNeedsNoExistingLibraryAndUsesTheFirstOneWhenThereIsOne() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let empty = try rig.openStore("empty")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: empty)
        #expect(try await empty.libraries().count == 1)

        let church = try rig.openStore("church")
        let mine = try await church.createLibrary(name: "My songs")
        _ = try await church.createLibrary(name: "Other")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.libraries().count == 2)
        #expect(try await church.presentations(in: mine.id).count == 2)
    }

    @Test func aPackageFromALaterBuildWithExtraFieldsStillReads() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let url = package.appendingPathComponent("program.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var presentations = try #require(object["presentations"] as? [[String: Any]])
        var slides = try #require(presentations[0]["slides"] as? [[String: Any]])
        slides[0]["background"] = ["kind": "video", "media": "media/whatever.mov"]       // a field this build does not know
        presentations[0]["slides"] = slides
        object["presentations"] = presentations
        object["somethingNew"] = true
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await rowCounts(church)["presentation"] == 2)
    }
}

extension Sequence where Element: Sendable {
    func asyncCount(_ test: (Element) async throws -> Bool) async rethrows -> Int {
        var n = 0
        for element in self where try await test(element) { n += 1 }
        return n
    }
}

extension LibraryStore {
    /// The library an import created in an empty church library.
    func onlyLibraryID() async throws -> UUID {
        let all = try await libraries()
        try #require(all.count == 1)
        return all[0].id
    }
}
