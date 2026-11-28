// FIX-AC item B (LIB-005, KI-285): an export writes format version 2 (a package may hold a video object, marks and markers that a version 1 build
// would misread); import reads 1 and 2; above 2 is refused as "made by a newer version", not "damaged".
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXAC_PackageFormatVersionTests {
    @Test func theFormatBuildsWriteAndReadIsTwo() {
        #expect(ProgramFormat.version == 2)
    }

    @Test func anExportWritesVersionTwoToTheManifest() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent(ProgramFormat.manifestName))) as? [String: Any])
        #expect(object["formatVersion"] as? Int == 2)
    }

    @Test func aVersionOnePackageStillImportsExactlyAsBefore() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { $0["formatVersion"] = 1 }                       // a package an older build wrote
        let contents = try ProgramPackageContents.open(package)
        #expect(contents.document.formatVersion == 1)
        let church = try rig.openStore("church")
        let result = try await ProgramImporter.apply(contents, into: church)
        #expect(result.presentationsReplaced + result.presentationsKeptAsCopies >= 0)
        #expect(try await church.slides(of: home.songOne).isEmpty == false)
    }

    @Test func aVersionTwoPackageImports() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let contents = try ProgramPackageContents.open(package)
        #expect(contents.document.formatVersion == 2)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await church.slides(of: home.songOne).isEmpty == false)
    }

    @Test(arguments: [3, 99, Int.max])
    func aVersionAboveTwoIsRefusedAsNewerAndNothingIsWritten(_ version: Int) async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { $0["formatVersion"] = version }
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        do { _ = try ProgramPackageContents.open(package); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError {
            #expect(error == .newerFormat(found: version, supported: 2))
            let message = try #require(error.errorDescription)
            #expect(message.contains("newer") && !message.contains("damaged") && !message.contains("wrong shape"))
        }
        #expect(try await rowCounts(church) == before)
    }

    @Test(arguments: [0, -1])
    func aVersionBelowOneIsStillNotAProgram(_ version: Int) async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { $0["formatVersion"] = version }
        do { _ = try ProgramPackageContents.open(package); Issue.record("expected a refusal") }
        catch let error as ProgramPackageError { if case .notAProgramPackage = error {} else { Issue.record("wrong refusal \(error)") } }
    }
}
