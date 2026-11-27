// FIX-Y item 4 (LIB-005, MEDIA; REVIEW-5 L7): importing a package brings only marks and markers the store and the model could have written, and says what
// was kept and what was not. Equal marks, and marks or markers on a picture or a sound, are repaired (dropped) with a sentence in the result; a marker
// whose id is already used is kept under a new id; a clip that is already in the library keeps its own marks and markers, and the result says the
// package's were not added. Hostile input stays bounded.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXY_MarksImportTests {
    private func editAssets(_ package: URL, _ change: (inout [String: Any]) -> Void) throws {
        try editManifest(package) { root in
            var assets = root["mediaAssets"] as? [[String: Any]] ?? []
            for i in assets.indices { change(&assets[i]) }
            root["mediaAssets"] = assets
        }
    }

    private func marker(id: UUID = UUID(), at time: Double, name: String? = nil) -> [String: Any] {
        var m: [String: Any] = ["id": id.uuidString, "time": time, "actions": ["version": 1, "actions": [Any]()] as [String: Any]]
        if let name { m["name"] = name }
        return m
    }

    private func importWith(_ home: HomeProgram, _ rig: Rig, edit: (inout [String: Any]) -> Void) async throws -> (LibraryStore, ProgramImportResult) {
        let package = try await home.export()
        try editAssets(package, edit)
        let church = try rig.openStore("church")
        let result = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        return (church, result)
    }

    @Test func equalMarksAreNotImportedAndTheResultSaysSo() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (church, result) = try await importWith(home, rig) { $0["markIn"] = 1.0; $0["markOut"] = 1.0 }
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(asset.markIn == nil && asset.markOut == nil)
        #expect(result.warnings.contains { $0.contains("Loop") && $0.localizedCaseInsensitiveContains("marks") && $0.contains("not") })
    }

    @Test func marksAndMarkersOnAPictureAreNotImportedAndTheResultSaysSo() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (church, result) = try await importWith(home, rig) {
            $0["kind"] = "image"; $0["markIn"] = 0.5; $0["markOut"] = 2.0; $0["markers"] = [self.marker(at: 1), self.marker(at: 2)]
        }
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(asset.markIn == nil && asset.markOut == nil)
        #expect(try await church.mediaMarkers(forAsset: asset.id).isEmpty)
        #expect(result.warnings.contains { $0.contains("Loop") && $0.contains("picture") && $0.contains("2 marker") })
    }

    @Test func marksAndMarkersOnASoundAreNotImportedAndTheResultSaysSo() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (church, result) = try await importWith(home, rig) { $0["kind"] = "audio"; $0["markIn"] = 0.5; $0["markers"] = [self.marker(at: 1)] }
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(asset.markIn == nil && asset.markOut == nil)
        #expect(try await church.mediaMarkers(forAsset: asset.id).isEmpty)
        #expect(result.warnings.contains { $0.contains("Loop") && $0.contains("sound") })
    }

    @Test func reversedMarksAreStillRefusedBeforeAnythingIsWritten() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editAssets(package) { $0["markIn"] = 2.0; $0["markOut"] = 1.0 }
        #expect(throws: ProgramPackageError.self) { _ = try ProgramPackageContents.open(package) }
    }

    @Test func twoMarkersWithOneIdAreBothKeptTheSecondUnderANewId() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let same = UUID()
        let (church, result) = try await importWith(home, rig) { $0["markers"] = [self.marker(id: same, at: 1, name: "A"), self.marker(id: same, at: 2, name: "B")] }
        let list = try await church.mediaMarkers(forAsset: home.assetID)
        #expect(list.map(\.name) == ["A", "B"] && Set(list.map(\.id)).count == 2 && list.contains { $0.id == same })
        #expect(result.warnings.contains { $0.contains("Loop") && $0.contains("new id") })
    }

    @Test func aMarkerWhoseIdTheLibraryAlreadyUsesIsKeptUnderANewId() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let other = try await church.addMediaAsset(name: "Other", kind: .video, path: rig.url("ExternalDrive", "other.mov").path, bookmark: nil,
                                                   duration: 5, pixelWidth: 64, pixelHeight: 36)
        let theirs = try await church.addMediaMarker(forAsset: other.id, time: 1, name: "Theirs")
        try editAssets(package) { $0["markers"] = [self.marker(id: theirs.id, at: 2, name: "Mine")] }
        let result = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.mediaMarkers(forAsset: other.id).map(\.name) == ["Theirs"])
        let mine = try await church.mediaMarkers(forAsset: home.assetID)
        #expect(mine.map(\.name) == ["Mine"] && mine[0].id != theirs.id)
        #expect(result.warnings.contains { $0.contains("new id") })
    }

    @Test func aClipTheLibraryAlreadyHasKeepsItsOwnMarksAndTheResultSaysThePackagesWereNotAdded() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await home.store.setMediaMarks(markIn: 0.5, markOut: 2.5, forAsset: home.assetID)
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, name: "Chorus in")
        let contents = try ProgramPackageContents.open(try await home.export())
        let entry = try #require(contents.document.mediaAssets.first { $0.id == home.assetID })
        let media = try #require(contents.document.media.first { $0.file == entry.file })
        let folder = "Media/Imported/\(contents.document.programID.uuidString)"
        let church = try rig.openStore("church")
        let mine = try await church.addMediaAsset(name: "Loop (mine)", kind: .video, path: rig.url("church", folder, "\(try #require(media.sha256)).mov").path,
                                                  bookmark: nil, duration: 3, pixelWidth: 640, pixelHeight: 360)
        let result = try await ProgramImporter.apply(contents, into: church)
        let kept = try #require(try await church.mediaAssets(kind: nil).first { $0.id == mine.id })
        let keptMarkers = try await church.mediaMarkers(forAsset: mine.id)
        #expect(kept.markIn == nil && keptMarkers.isEmpty)
        #expect(result.warnings.contains { $0.contains("Loop") && $0.contains("already in the media bin") && $0.contains("1 marker") && $0.localizedCaseInsensitiveContains("marks") && $0.contains("not added") })
    }

    @Test func aHostilePackageOfManyDuplicateIdsStaysBounded() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let same = UUID()
        let (church, result) = try await importWith(home, rig) {
            $0["name"] = String(repeating: "N", count: 100_000)
            $0["markers"] = (0..<MediaMarker.maxPerAsset).map { self.marker(id: same, at: Double($0) / 1000) }
        }
        let list = try await church.mediaMarkers(forAsset: home.assetID)
        #expect(list.count == MediaMarker.maxPerAsset && Set(list.map(\.id)).count == MediaMarker.maxPerAsset)
        #expect(result.warnings.count < 50 && result.warnings.allSatisfy { $0.count < 2_000 })
    }
}
