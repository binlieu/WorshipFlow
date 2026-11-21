// FIX-G items 8 and 14 (LIB-005): hostile packages the review found untested: a symlinked directory inside media/, a hard
// link, ids that are not UUIDs, deeply nested JSON, the media-file limit and a custom theme that claims a built-in id.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXG_HostilePackageTests {
    private func refused(_ package: URL, into church: LibraryStore) async throws -> ProgramPackageError? {
        do {
            let contents = try ProgramPackageContents.open(package)
            _ = try await ProgramImporter.apply(contents, into: church)
            return nil
        } catch let error as ProgramPackageError {
            return error
        }
    }

    private func assertNothingWritten(_ rig: Rig, _ church: LibraryStore, _ before: [String: Int], _ folder: [String]) async throws {
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folder)
    }

    @Test func aSymlinkedDirectoryInsideMediaIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: package.appendingPathComponent("program.json")))
        let included = try #require(document.media.first { $0.status == .included })
        // media/sub is a link to a folder outside the package that holds the same bytes.
        let outside = rig.url("outside", "folder")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: package.appendingPathComponent(included.file), to: outside.appendingPathComponent("x.png"))
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("media/sub"), withDestinationURL: outside)
        try editManifest(package) { root in
            var media = root["media"] as? [[String: Any]] ?? []
            for i in media.indices where media[i]["file"] as? String == included.file { media[i]["file"] = "media/sub/x.png" }
            root["media"] = media
            root["presentations"] = [[String: Any]]()
            root["themes"] = [[String: Any]]()
            root["mediaAssets"] = [[String: Any]]()
            root["items"] = [[String: Any]]()
        }
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        #expect(error != nil, "a folder link inside media/ must be refused")
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func theMediaFolderItselfBeingALinkIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let moved = rig.url("outside", "media")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: package.appendingPathComponent("media"), to: moved)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("media"), withDestinationURL: moved)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        #expect(try await refused(package, into: church) != nil)
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func aHardLinkedMediaFileIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: package.appendingPathComponent("program.json")))
        let included = try #require(document.media.first { $0.status == .included })
        // A second name for the same file outside the package: a hard link cannot be told from a plain file by lstat's type.
        let target = package.appendingPathComponent(included.file)
        let outside = rig.url("outside", "same.bin")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: target, to: outside)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        #expect(error != nil, "a hard-linked file is not something this app ever writes")
        if let error { #expect(error.localizedDescription.contains("link")) }
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func idsThatAreNotUUIDsAreRefusedAsUnreadable() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { $0["programID"] = "not-a-uuid" }
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        guard case .manifestUnreadable = error else { Issue.record("expected manifestUnreadable, got \(String(describing: error))"); return }
        try await assertNothingWritten(rig, church, before, folder)
        try editManifest(package) { root in
            root["programID"] = UUID().uuidString
            var presentations = root["presentations"] as? [[String: Any]] ?? []
            presentations[0]["id"] = "../../etc"
            root["presentations"] = presentations
        }
        guard case .manifestUnreadable = try await refused(package, into: church) else { Issue.record("a path-like id must be refused"); return }
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func veryDeeplyNestedJSONIsRefusedWithoutCrashing() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let manifest = package.appendingPathComponent("program.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        let depth = 200_000
        let nest = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        // The slide actions are free-form JSON; put the nesting there.
        let range = try #require(text.range(of: "\"actions\" :"))
        text.replaceSubrange(range, with: "\"actions\" : \(nest), \"ignored\" :")
        try Data(text.utf8).write(to: manifest)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        guard case .manifestUnreadable = error else { Issue.record("expected manifestUnreadable, got \(String(describing: error))"); return }
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func moreMediaFilesThanTheLimitAreRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { root in
            var media = root["media"] as? [[String: Any]] ?? []
            for i in 0...ProgramFormat.maxMediaFiles {
                media.append(["file": "media/missing/n\(i).png", "name": "n\(i).png", "status": "missing"])
            }
            root["media"] = media
        }
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        guard case .tooManyFiles = error else { Issue.record("expected tooManyFiles, got \(String(describing: error))"); return }
        try await assertNothingWritten(rig, church, before, folder)
    }

    @Test func aCustomThemeThatUsesABuiltInIdIsRefusedInPlainWords() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let builtIn = try #require(Theme.builtIn.first)
        try editManifest(package) { root in
            var themes = root["themes"] as? [[String: Any]] ?? []
            themes[0]["id"] = builtIn.id.uuidString
            root["themes"] = themes
        }
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let error = try await refused(package, into: church)
        let message = try #require(error?.localizedDescription)
        #expect(message.contains("built-in") && message.contains("Sky") && message.contains("Nothing was imported"))
        try await assertNothingWritten(rig, church, before, folder)
        #expect(try await church.themes().isEmpty)
    }
}
