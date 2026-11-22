// FIX-H item 5 (UI-005b): a program package whose announcements loop asks for a time outside the allowed range is refused in plain
// words before anything is written. (Decoding alone would hold the value in range; a package is untrusted input, so the operator is told.)
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXH_LoopValuesProgramTests {
    private func packageWithLoop(seconds: Any) async throws -> (Rig, URL) {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let picture = try await home.store.addMediaAsset(name: "Welcome", kind: .image, path: rig.url("ExternalDrive", "pictures", "welcome.png").path,
                                                         bookmark: nil, duration: nil, pixelWidth: 100, pixelHeight: 100)
        try rig.write(rig.bytes(seed: 12, count: 2_500), to: URL(fileURLWithPath: picture.path))
        _ = try await home.store.addPlaylistAnnouncements(AnnouncementsSpec(label: "Announcements loop",
            items: [MediaItemSpec(assetID: picture.id, name: picture.name, kind: .image)], secondsPerPicture: 12), to: home.playlistID)
        let package = try await home.export()
        try editManifest(package) { root in
            var items = root["items"] as? [[String: Any]] ?? []
            for i in items.indices where items[i]["kind"] as? String == "announcements" {
                var loop = items[i]["announcements"] as? [String: Any] ?? [:]
                loop["secondsPerPicture"] = seconds
                items[i]["announcements"] = loop
            }
            root["items"] = items
        }
        return (rig, package)
    }

    @Test func aLoopWithZeroSecondsPerPictureIsRefusedInPlainWordsAndNothingIsWritten() async throws {
        let (rig, package) = try await packageWithLoop(seconds: 0)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        do {
            _ = try ProgramPackageContents.open(package)
            Issue.record("the package should have been refused")
        } catch let error as ProgramPackageError {
            let text = error.errorDescription ?? ""
            #expect(text.contains("Announcements loop") && text.contains("0 seconds") && text.contains("between 3 and 120") && text.contains("Nothing was imported"))
        }
        #expect(try await rowCounts(church) == before)
    }

    @Test func aLoopWithAnAbsurdTimeIsRefusedToo() async throws {
        let (rig, package) = try await packageWithLoop(seconds: 900_000)
        defer { withExtendedLifetime(rig) {} }
        do { _ = try ProgramPackageContents.open(package); Issue.record("should be refused") } catch let error as ProgramPackageError { #expect((error.errorDescription ?? "").contains("900000 seconds")) }
    }

    @Test func aLoopWithAllowedTimeStillImports() async throws {
        let (rig, package) = try await packageWithLoop(seconds: 30)
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        let loop = try await church.playlistItems(of: contents.document.playlist.id).compactMap { item -> AnnouncementsSpec? in
            if case .announcements(let spec) = item.kind { return spec } else { return nil }
        }
        #expect(loop.map(\.secondsPerPicture) == [30])
    }
}
