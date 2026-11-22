// FIX-T items 1 and 2 (LIB-005, SYS): a program package is untrusted input. A media duration, a picture size or a file size that is
// absurd, negative or not a number is refused in plain words before anything is written, and adding up sizes cannot overflow.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXT_ManifestNumbersTests {
    private func refusal(_ package: URL) -> String? {
        do { _ = try ProgramPackageContents.open(package); return nil } catch let error as ProgramPackageError { return error.errorDescription } catch { return "other: \(error)" }
    }

    private func editAssets(_ package: URL, _ change: (inout [String: Any]) -> Void) throws {
        try editManifest(package) { root in
            var assets = root["mediaAssets"] as? [[String: Any]] ?? []
            for i in assets.indices { change(&assets[i]) }
            root["mediaAssets"] = assets
        }
    }

    @Test func aHugeNegativeOrTooLargeAssetDurationIsRefused() async throws {
        for bad: Any in [1e300, -1e300, -1.0, 1e12] {
            let rig = try Rig()
            let home = try await HomeProgram.make(rig)
            let package = try await home.export()
            try editAssets(package) { $0["duration"] = bad }
            let text = try #require(refusal(package), "duration \(bad) should be refused")
            #expect(text.contains("Nothing was imported"), "\(text)")
        }
    }

    @Test func aSlideBackgroundWithAnAbsurdDurationIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        var changed = 0
        try editSlides(package) { slide in
            if var background = slide["background"] as? [String: Any] { background["duration"] = 1e300; slide["background"] = background; changed += 1 }
        }
        if changed == 0 {
            // The shared fixture has no slide background: add one that names the first listed media file.
            try editManifest(package) { root in
                let media = root["media"] as? [[String: Any]] ?? []
                let file = media.first { $0["status"] as? String == "included" }?["file"] as? String ?? ""
                var presentations = root["presentations"] as? [[String: Any]] ?? []
                var slides = presentations[0]["slides"] as? [[String: Any]] ?? []
                slides[0]["background"] = ["assetID": UUID().uuidString, "kind": "video", "duration": 1e300, "file": file]
                presentations[0]["slides"] = slides
                root["presentations"] = presentations
            }
        }
        #expect(refusal(package) != nil)
    }

    @Test func absurdPictureSizesAreRefused() async throws {
        for (key, value) in [("pixelWidth", -5), ("pixelHeight", 1_000_000_000), ("pixelWidth", Int.max)] {
            let rig = try Rig()
            let home = try await HomeProgram.make(rig)
            let package = try await home.export()
            try editAssets(package) { $0[key] = value }
            #expect(refusal(package) != nil, "\(key) \(value) should be refused")
        }
    }

    @Test func aNegativeOrAbsurdFileSizeIsRefused() async throws {
        for bad in [-1, Int(Int64.max)] {
            let rig = try Rig()
            let home = try await HomeProgram.make(rig)
            let package = try await home.export()
            try editManifest(package) { root in
                var media = root["media"] as? [[String: Any]] ?? []
                for i in media.indices where media[i]["status"] as? String == "included" { media[i]["size"] = bad }
                root["media"] = media
            }
            #expect(refusal(package) != nil, "size \(bad) should be refused")
        }
    }

    @Test func sizesThatAreEachSmallEnoughButAddUpToMoreThanInt64DoNotTrapAndAreNotImported() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { root in
            var media = root["media"] as? [[String: Any]] ?? []
            for i in media.indices where media[i]["status"] as? String == "included" { media[i]["size"] = 4_000_000_000_000_000_000 }
            root["media"] = media
        }
        // Either the reader refuses it, or summarising it does not trap; both are safe. Either way nothing is written.
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        if let contents = try? ProgramPackageContents.open(package) { _ = try? await ProgramImporter.summarize(contents, into: church) }
        #expect(try await rowCounts(church) == before)
    }

    @Test func anOrdinaryPackageStillOpensAndImports() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let contents = try ProgramPackageContents.open(package)
        let church = try rig.openStore("church")
        let summary = try await ProgramImporter.summarize(contents, into: church)
        #expect(summary.mediaBytesToCopy > 0)
    }
}
