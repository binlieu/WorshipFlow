// UI-005b item 2: the service date and time travel with a program, and importing a program that differs only by its date
// is a change the operator is asked about, not "already present".
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct UI005b_ServiceDateProgramTests {
    let when = Date(timeIntervalSince1970: 1_795_338_000)

    @Test func theDateRoundTripsIntoAnEmptyLibrary() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try await home.store.setPlaylistServiceDate(id: home.playlistID, to: when)
        let package = try await home.export()
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.playlists().first { $0.id == home.playlistID }?.serviceAt == when)
    }

    @Test func aProgramWithoutADateImportsWithoutOne() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.playlists().first { $0.id == home.playlistID }?.serviceAt == nil)
    }

    @Test func aDifferentDateIsNotAlreadyPresent() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()                                   // no date
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        try await church.setPlaylistServiceDate(id: home.playlistID, to: when)    // the church sets one afterwards
        let summary = try await ProgramImporter.summarize(contents, into: church)
        #expect(!summary.isNothingToImport)                                      // the date differs: not "already present"
        #expect(try await church.playlists().first?.serviceAt == when)           // summarising changed nothing
    }
}
