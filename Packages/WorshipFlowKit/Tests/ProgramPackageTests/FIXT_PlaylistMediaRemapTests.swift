// FIX-T item 5 (M7, UI-005b): a package's media item and announcements loop point at bin entries by id. When the library already holds a bin
// entry for the same file under another id, the importer skips the package's entry; the items must then point at the existing entry,
// inside the same import transaction, so they never name a row that does not exist.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct FIXT_PlaylistMediaRemapTests {
    @Test func aSkippedBinEntryRemapsTheMediaItemAndTheLoopToTheExistingEntry() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let video = try await home.store.addMediaAsset(name: "Testimony", kind: .video, path: rig.url("ExternalDrive", "pictures", "film.mov").path,
                                                       bookmark: nil, duration: 12, pixelWidth: 640, pixelHeight: 360)
        try rig.write(rig.bytes(seed: 11, count: 3_000), to: URL(fileURLWithPath: video.path))
        let picture = try await home.store.addMediaAsset(name: "Welcome", kind: .image, path: rig.url("ExternalDrive", "pictures", "welcome.png").path,
                                                         bookmark: nil, duration: nil, pixelWidth: 100, pixelHeight: 100)
        try rig.write(rig.bytes(seed: 12, count: 2_500), to: URL(fileURLWithPath: picture.path))
        _ = try await home.store.addPlaylistMedia(MediaItemSpec(assetID: video.id, name: video.name, kind: .video), to: home.playlistID)
        _ = try await home.store.addPlaylistAnnouncements(AnnouncementsSpec(label: "Loop",
                items: [MediaItemSpec(assetID: picture.id, name: picture.name, kind: .image)], secondsPerPicture: 12), to: home.playlistID)
        let package = try await home.export()
        let contents = try ProgramPackageContents.open(package)

        // The church library already has bin entries for exactly these files, under other ids.
        let church = try rig.openStore("church")
        let folder = "Media/Imported/\(contents.document.programID.uuidString)"
        func localPath(of asset: MediaAsset) throws -> String {
            let entry = try #require(contents.document.mediaAssets.first { $0.id == asset.id })
            let media = try #require(contents.document.media.first { $0.file == entry.file })
            return rig.url("church", folder, "\(try #require(media.sha256)).\((media.name as NSString).pathExtension.lowercased())").path
        }
        let existingVideo = try await church.addMediaAsset(name: "Testimony (mine)", kind: .video, path: try localPath(of: video), bookmark: nil,
                                                           duration: 12, pixelWidth: 640, pixelHeight: 360)
        let existingPicture = try await church.addMediaAsset(name: "Welcome (mine)", kind: .image, path: try localPath(of: picture), bookmark: nil,
                                                             duration: nil, pixelWidth: 100, pixelHeight: 100)
        #expect(existingVideo.id != video.id && existingPicture.id != picture.id)

        _ = try await ProgramImporter.apply(contents, into: church)

        let binIDs = Set(try await church.mediaAssets(kind: nil).map(\.id))
        let kinds = try await church.playlistItems(of: contents.document.playlist.id).map(\.kind)
        var mediaIDs: [UUID] = []
        for kind in kinds {
            switch kind {
            case .media(let spec): mediaIDs.append(spec.assetID)
            case .announcements(let spec): mediaIDs += spec.assetIDs
            default: break
            }
        }
        #expect(mediaIDs.count == 2)
        #expect(mediaIDs.allSatisfy { binIDs.contains($0) }, "every media reference names a bin row that exists")
        #expect(Set(mediaIDs) == [existingVideo.id, existingPicture.id])
        let loop = kinds.compactMap { kind -> AnnouncementsSpec? in if case .announcements(let s) = kind { return s } else { return nil } }.first
        #expect(loop?.label == "Loop" && loop?.secondsPerPicture == 12, "the rest of the loop is unchanged")
    }

    @Test func withNoSkippedEntryTheItemsKeepThePackagesIds() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let video = try await home.store.addMediaAsset(name: "Testimony", kind: .video, path: rig.url("ExternalDrive", "pictures", "film.mov").path,
                                                       bookmark: nil, duration: 12, pixelWidth: 640, pixelHeight: 360)
        try rig.write(rig.bytes(seed: 11, count: 3_000), to: URL(fileURLWithPath: video.path))
        _ = try await home.store.addPlaylistMedia(MediaItemSpec(assetID: video.id, name: video.name, kind: .video), to: home.playlistID)
        let contents = try ProgramPackageContents.open(try await home.export())
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        let kinds = try await church.playlistItems(of: contents.document.playlist.id).map(\.kind)
        #expect(kinds.contains(.media(MediaItemSpec(assetID: video.id, name: "Testimony", kind: .video))))
    }
}
