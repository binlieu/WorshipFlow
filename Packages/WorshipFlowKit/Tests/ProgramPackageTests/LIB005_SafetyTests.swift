// LIB-005 item 4: a package is untrusted input. Nothing in one can make the app read or write outside the package and the
// library's own folders, and a refused package writes nothing.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct LIB005_SafetyTests {
    enum Attack: String, CaseIterable, Sendable {
        case absoluteMediaPath, parentFolderPath, absoluteSlideImagePath, symlinkToOutside, oversizedJSON, newerFormat, wrongFormatName,
             notJSON, missingManifest, backslashPath, fileListedButNotInPackage, symlinkedManifest
    }

    /// Exports the home program, then damages the package as `attack` says. Returns the package and a file outside it.
    private func hostile(_ attack: Attack, _ rig: Rig) async throws -> URL {
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let manifest = package.appendingPathComponent("program.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        let document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: manifest))
        let included = try #require(document.media.first { $0.status == .included })
        func replace(_ old: String, _ new: String) { text = text.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"") }
        switch attack {
        case .absoluteMediaPath: replace(included.file, "/etc/hosts")
        case .parentFolderPath: replace(included.file, "media/../../outside.bin")
        case .backslashPath: replace(included.file, "media\\\\..\\\\x.png")
        case .absoluteSlideImagePath:
            let imagePath = try #require(document.presentations.flatMap(\.slides).flatMap(\.objects).compactMap { o -> String? in
                if case .image(let i) = o.content { return i.path } else { return nil }
            }.first)
            // Only the slide's reference is changed; the media list stays as written.
            text = text.replacingOccurrences(of: "\"path\":\"\(imagePath)\"", with: "\"path\":\"/Users/someone/secret.png\"")
            if text.contains("\"path\" : \"\(imagePath)\"") {
                text = text.replacingOccurrences(of: "\"path\" : \"\(imagePath)\"", with: "\"path\" : \"/Users/someone/secret.png\"")
            }
        case .symlinkToOutside:
            let outside = try rig.write(Data("outside".utf8), to: rig.url("outside", "secret.txt"))
            let target = package.appendingPathComponent(included.file)
            try FileManager.default.removeItem(at: target)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        case .oversizedJSON: text += String(repeating: " ", count: ProgramFormat.maxManifestBytes + 1)
        case .newerFormat: text = text.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")
        case .wrongFormatName: text = text.replacingOccurrences(of: "worshipflow-program", with: "something-else")
        case .notJSON: text = "this is not json"
        case .missingManifest: try FileManager.default.removeItem(at: manifest)
        case .fileListedButNotInPackage: try FileManager.default.removeItem(at: package.appendingPathComponent(included.file))
        case .symlinkedManifest:
            let outside = try rig.write(Data(text.utf8), to: rig.url("outside", "program.json"))
            try FileManager.default.removeItem(at: manifest)
            try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: outside)
        }
        if attack != .missingManifest && attack != .symlinkedManifest && attack != .symlinkToOutside && attack != .fileListedButNotInPackage {
            try Data(text.utf8).write(to: manifest)
        }
        return package
    }

    @Test(arguments: Attack.allCases)
    func aHostilePackageIsRefusedAndNothingIsWritten(_ attack: Attack) async throws {
        let rig = try Rig()
        let package = try await hostile(attack, rig)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folderBefore = rig.listing(rig.url("church"))
        var refused = false
        do {
            let contents = try ProgramPackageContents.open(package)
            _ = try await ProgramImporter.summarize(contents, into: church)
            _ = try await ProgramImporter.apply(contents, into: church)
        } catch is ProgramPackageError {
            refused = true
        }
        #expect(refused, "\(attack) must be refused")
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folderBefore)
        #expect(!FileManager.default.fileExists(atPath: rig.url("outside.bin").path))
    }

    @Test func eachRefusalSaysWhatIsWrongInPlainWords() async throws {
        let rig = try Rig()
        let newer = try await hostile(.newerFormat, rig)
        do { _ = try ProgramPackageContents.open(newer); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError {
            #expect(error == .newerFormat(found: 99, supported: 1))
            let message = try #require(error.errorDescription)
            #expect(message.contains("newer") && message.contains("Update WorshipFlow"))
        }
        let rig2 = try Rig()
        let big = try await hostile(.oversizedJSON, rig2)
        do { _ = try ProgramPackageContents.open(big); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError {
            guard case .manifestTooLarge(let size) = error else { Issue.record("wrong refusal \(error)"); return }
            #expect(size > ProgramFormat.maxManifestBytes)
        }
        let rig3 = try Rig()
        let link = try await hostile(.symlinkToOutside, rig3)
        do { _ = try ProgramPackageContents.open(link); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError {
            guard case .linkNotAllowed = error else { Issue.record("wrong refusal \(error)"); return }
        }
        let rig4 = try Rig()
        let parent = try await hostile(.parentFolderPath, rig4)
        do { _ = try ProgramPackageContents.open(parent); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError {
            guard case .unsafePath = error else { Issue.record("wrong refusal \(error)"); return }
        }
    }

    @Test func aDamagedMediaFileIsRefusedWhileCopyingAndLeavesNothing() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: package.appendingPathComponent("program.json")))
        let victim = try #require(document.media.first { $0.status == .included })
        let file = package.appendingPathComponent(victim.file)
        var bytes = try Data(contentsOf: file)
        bytes[0] ^= 0xFF
        try bytes.write(to: file)
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        await #expect(throws: ProgramPackageError.self) {
            _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church", "Media")).isEmpty)
    }

    @Test func packagePathRules() {
        for good in ["media/abc.png", "media/missing/c.jpg", "media/a b/c d.mov"] { #expect(ProgramPathRules.isSafePackagePath(good), "\(good)") }
        for bad in ["/media/abc.png", "media/../x", "media/./x", "media//x", "media/x/", "x/abc.png", "media", "~/media/x", "media\\x", "",
                    "media/a\u{0}b", "media/..", "../media/x", "file:///etc/hosts", "media/a\nb"] {
            #expect(!ProgramPathRules.isSafePackagePath(bad), "\(bad.debugDescription)")
        }
    }

    @Test func aFileNamedByAnAttackerNeverDecidesWhereItIsWritten() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let manifest = package.appendingPathComponent("program.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        // A display name full of path characters changes nothing about where the copy goes.
        text = text.replacingOccurrences(of: "\"name\" : \"loop.mov\"", with: "\"name\" : \"../../../../etc/evil.mov\"")
        try Data(text.utf8).write(to: manifest)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        let written = rig.listing(rig.url("church", "Media"))
        #expect(written.allSatisfy { !$0.contains("..") && !$0.contains("evil") })
        #expect(!FileManager.default.fileExists(atPath: rig.url("etc").path))
    }
}
