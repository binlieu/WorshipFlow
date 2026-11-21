// FIX-G item 10 (LIB-005): while the show is live an import does not replace themes or Looks in use; a Look that names this
// Mac's screens is mapped by role; the summary lists slide actions by kind before the operator confirms.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXG_LiveAndLooksTests {
    private func imported(_ rig: Rig) async throws -> (HomeProgram, LibraryStore, ProgramPackageContents) {
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        return (home, church, contents)
    }

    private func edit(_ church: LibraryStore, _ home: HomeProgram) async throws {
        var theme = try #require(try await church.themes().first { $0.id == home.themeID })
        theme.name = "Sky (church)"
        try await church.saveTheme(theme)
        var look = try #require(try await church.looks().first { $0.id == home.lookID })
        look.name = "Morning (church)"
        try await church.saveLook(look)
    }

    @Test func whileTheShowIsLiveAThemeAndALookInUseAreKeptBesideTheImportedOnes() async throws {
        let rig = try Rig()
        let (home, church, contents) = try await imported(rig)
        try await edit(church, home)
        let live = ProgramLiveContext(isShowLive: true, themeIDsInUse: [home.themeID], lookIDsInUse: [home.lookID])
        let result = try await ProgramImporter.apply(contents, into: church, choice: .useImported, live: live)
        let themes = try await church.themes().map(\.name).sorted()
        #expect(themes == ["Sky (church)", "Sky (imported)"])
        let looks = try await church.looks().map(\.name).sorted()
        #expect(looks == ["Morning (church)", "Morning (imported)"])
        #expect(result.warnings.contains { $0.contains("Sky") && $0.contains("in use") })
        #expect(result.warnings.contains { $0.contains("Morning") && $0.contains("in use") })
    }

    @Test func withNothingLiveTheyAreReplacedAsBefore() async throws {
        let rig = try Rig()
        let (home, church, contents) = try await imported(rig)
        try await edit(church, home)
        _ = try await ProgramImporter.apply(contents, into: church, choice: .useImported, live: .none)
        #expect(try await church.themes().map(\.name) == ["Sky"])
        #expect(try await church.looks().map(\.name) == ["Morning"])
    }

    @Test func aThemeNotInUseIsStillReplacedWhileTheShowIsLive() async throws {
        let rig = try Rig()
        let (home, church, contents) = try await imported(rig)
        try await edit(church, home)
        _ = try await ProgramImporter.apply(contents, into: church, choice: .useImported, live: ProgramLiveContext(isShowLive: true))
        #expect(try await church.themes().map(\.name) == ["Sky"])
        #expect(try await church.looks().map(\.name) == ["Morning"])
    }

    @Test func aLookNamesScreensByRoleSoItWorksOnAnotherMac() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let homeAudience = ScreenProfile(name: "Front", role: .audience, destination: .window)
        let homeStage = ScreenProfile(name: "Pulpit", role: .stage, destination: .window)
        let homeBroadcast = ScreenProfile(name: "Stream", role: .broadcast, destination: .window)
        try await home.store.saveScreenProfiles([homeAudience, homeStage, homeBroadcast])
        try await home.store.saveLook(Look(id: home.lookID, name: "Morning", screens: [
            homeAudience.id: ScreenLook(themeID: nil, visibleLayers: [.slide, .background]),
            homeStage.id: ScreenLook(themeID: nil, visibleLayers: [.slide]),
            homeBroadcast.id: ScreenLook(themeID: nil, visibleLayers: [.slide, .props])]))
        let package = try await home.export()

        // The package says which role each screen had, and holds no other Mac's profile in any other form.
        let contents = try ProgramPackageContents.open(package)
        let entry = try #require(contents.document.looks.first)
        #expect(Set(entry.roles.values) == ["audience", "stage", "broadcast"])

        // Another Mac: other profile ids, and no broadcast screen.
        let church = try rig.openStore("church")
        let churchAudience = ScreenProfile(name: "Main", role: .audience, destination: .window)
        let churchStage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
        try await church.saveScreenProfiles([churchAudience, churchStage])
        let result = try await ProgramImporter.apply(contents, into: church)
        let look = try #require(try await church.looks().first { $0.id == home.lookID })
        #expect(Set(look.screens.keys) == [churchAudience.id, churchStage.id])
        #expect(look.screens[churchAudience.id]?.visibleLayers == [.slide, .background])
        #expect(look.screens[churchStage.id]?.visibleLayers == [.slide])
        #expect(result.warnings.contains { $0.contains("Morning") && $0.contains("broadcast") }, "what cannot be mapped is recorded")
    }

    @Test func aLookFromAnOlderPackageWithoutRolesKeepsTheScreensThatThisMacHas() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { root in
            var looks = root["looks"] as? [[String: Any]] ?? []
            for i in looks.indices { looks[i].removeValue(forKey: "roles") }
            root["looks"] = looks
        }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        #expect(try await church.looks().map(\.name) == ["Morning"])
    }

    @Test func theSummaryListsTheSlideActionsByKindAndCountBeforeAnythingIsImported() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let summary = try await ProgramImporter.summarize(try ProgramPackageContents.open(package), into: church)
        #expect(summary.slideActionKinds == ["media.playForeground": 1, "look.select": 1, "future.thing": 1])
        #expect(try await rowCounts(church)["presentation"] == 0)
    }
}
