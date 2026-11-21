// UI-005b item 4: a media-file item, an announcements loop and a sermon item travel in a program package with their bin items and
// files, and come back as the same kinds in an empty library (the drive the files were on is not at church).
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct UI005b_ItemKindsProgramTests {
    private func extended(_ home: HomeProgram, _ rig: Rig) async throws -> (video: MediaAsset, picture: MediaAsset) {
        let video = try await home.store.addMediaAsset(name: "Baptism testimony", kind: .video, path: rig.url("ExternalDrive", "pictures", "film.mov").path,
                                                       bookmark: nil, duration: 12, pixelWidth: 640, pixelHeight: 360)
        try rig.write(rig.bytes(seed: 11, count: 3_000), to: URL(fileURLWithPath: video.path))
        let picture = try await home.store.addMediaAsset(name: "Welcome", kind: .image, path: rig.url("ExternalDrive", "pictures", "welcome.png").path,
                                                         bookmark: nil, duration: nil, pixelWidth: 100, pixelHeight: 100)
        try rig.write(rig.bytes(seed: 12, count: 2_500), to: URL(fileURLWithPath: picture.path))
        _ = try await home.store.addPlaylistMedia(MediaItemSpec(assetID: video.id, name: video.name, kind: .video), to: home.playlistID)
        _ = try await home.store.addPlaylistAnnouncements(AnnouncementsSpec(label: "Announcements loop",
                items: [MediaItemSpec(assetID: picture.id, name: picture.name, kind: .image)], secondsPerPicture: 12), to: home.playlistID)
        _ = try await home.store.addPlaylistSermon(home.songTwo, to: home.playlistID)
        return (video, picture)
    }

    @Test func eachNewKindRoundTripsWithItsMediaIntoAnEmptyLibrary() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (video, picture) = try await extended(home, rig)
        let package = try await home.export()
        let expected = try await describe(home.store, playlist: home.playlistID)
        #expect(expected.contains { $0.hasPrefix("media Baptism testimony") } && expected.contains { $0.hasPrefix("announcements Announcements loop") }
                && expected.contains { $0.hasPrefix("sermon ") })
        try FileManager.default.removeItem(at: rig.url("ExternalDrive"))

        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await describe(church, playlist: home.playlistID) == expected)
        let kinds = try await church.playlistItems(of: home.playlistID).map(\.kind)
        #expect(kinds.contains(.media(MediaItemSpec(assetID: video.id, name: "Baptism testimony", kind: .video))))
        #expect(kinds.contains(.sermon))
        // The bin items that only these items use came along, with their bytes.
        let assets = try await church.mediaAssets(kind: nil)
        #expect(Set(assets.map(\.id)).isSuperset(of: [video.id, picture.id]))
        let arrived = try #require(assets.first { $0.id == picture.id })
        #expect(try Data(contentsOf: URL(fileURLWithPath: arrived.path)) == rig.bytes(seed: 12, count: 2_500))
    }

    @Test func importingTheSameProgramAgainChangesNothing() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await extended(home, rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        let counts = try await rowCounts(church)
        #expect(try await ProgramImporter.summarize(contents, into: church).isNothingToImport)
        #expect(try await rowCounts(church) == counts)
    }
}
