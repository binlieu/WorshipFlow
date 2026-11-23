// FIX-W item 3 (LIB-005, CUE-33; REVIEW-5 M3): a marker action that selects a Look imported under a new id selects the imported Look, the same
// as a slide action does; an asset remap and a Look remap on the same marker both apply.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXW_MarkerLookImportTests {
    private func actions(look: UUID, asset: UUID? = nil) -> String {
        let play = asset.map { #"{"kind":"media.playForeground","assetID":"\#($0.uuidString.lowercased())"},"# } ?? ""
        return #"{"version":1,"actions":[\#(play){"kind":"look.select","id":"\#(look.uuidString.lowercased())"}]}"#
    }

    @Test func aMarkerSelectsTheImportedCopyOfAKeptBesideLook() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, actions: actions(look: home.lookID))
        let contents = try ProgramPackageContents.open(try await home.export())
        let church = try rig.openStore("church")
        try await church.saveLook(Look(id: home.lookID, name: "Mine", screens: [:]))          // same id, other content: a conflict
        _ = try await ProgramImporter.apply(contents, into: church, choice: .keepBoth)
        let looks = try await church.looks()
        let copy = try #require(looks.first { $0.name == "Morning (imported)" })
        #expect(copy.id != home.lookID && looks.contains { $0.id == home.lookID && $0.name == "Mine" })
        let marker = try #require(try await church.mediaMarkers(forAsset: home.assetID).first)
        #expect(marker.actions.contains(copy.id.uuidString.lowercased()) && !marker.actions.contains(home.lookID.uuidString.lowercased()))
        // the slide action went the same way
        let slide = try #require(try await church.slides(of: home.songOne).first)
        let stored = try await church.programRead { db in try String.fetchOne(db, sql: "SELECT definition FROM cueSlideActions WHERE slideID = ?", arguments: [slide.id.uuidString]) }
        #expect(stored?.contains(copy.id.uuidString.lowercased()) == true)
    }

    @Test func aMarkerThatNamesAnotherClipAndALookGetsBothRemaps() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let stinger = try await home.store.addMediaAsset(name: "Stinger", kind: .video, path: rig.url("ExternalDrive", "pictures", "stinger.mov").path,
                                                         bookmark: nil, duration: 2, pixelWidth: 64, pixelHeight: 36)
        try rig.write(rig.bytes(seed: 21, count: 1_000), to: URL(fileURLWithPath: stinger.path))
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, actions: actions(look: home.lookID, asset: stinger.id))
        let contents = try ProgramPackageContents.open(try await home.export())
        let entry = try #require(contents.document.mediaAssets.first { $0.id == stinger.id })
        let media = try #require(contents.document.media.first { $0.file == entry.file })
        let folder = "Media/Imported/\(contents.document.programID.uuidString)"
        let church = try rig.openStore("church")
        let mine = try await church.addMediaAsset(name: "Stinger (mine)", kind: .video, path: rig.url("church", folder, "\(try #require(media.sha256)).mov").path,
                                                  bookmark: nil, duration: 2, pixelWidth: 64, pixelHeight: 36)
        try await church.saveLook(Look(id: home.lookID, name: "Mine", screens: [:]))
        _ = try await ProgramImporter.apply(contents, into: church, choice: .keepBoth)
        let copy = try #require(try await church.looks().first { $0.name == "Morning (imported)" })
        let marker = try #require(try await church.mediaMarkers(forAsset: home.assetID).first)
        #expect(marker.actions.contains(mine.id.uuidString.lowercased()) && !marker.actions.contains(stinger.id.uuidString.lowercased()))
        #expect(marker.actions.contains(copy.id.uuidString.lowercased()) && !marker.actions.contains(home.lookID.uuidString.lowercased()))
    }

    @Test func aMarkerKeepsItsLookWhenTheLookIsNotRenamed() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, actions: actions(look: home.lookID))
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(try await home.export()), into: church)
        let marker = try #require(try await church.mediaMarkers(forAsset: home.assetID).first)
        #expect(marker.actions.contains(home.lookID.uuidString.lowercased()))
    }
}
