// FIX-V item 2 (REVIEW-4 M4): Remove screen is refused while that screen's output is running or it is the only enabled screen of its role while
// the screens are open; the confirmation names what goes with it; the stage layout choice goes with the screen.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct FIXV_RemoveScreenRuleTests {
    let a = ScreenProfile(name: "Projector", role: .audience, destination: .display(5))
    let a2 = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
    let s = ScreenProfile(name: "Stage", role: .stage, destination: .display(6))

    @Test func aRunningScreenCannotBeRemoved() {
        let why = ScreenListEditing.removalBlock(a.id, profiles: [a, a2, s], activeOutputs: [a.id], screensOpen: true)
        #expect(why?.contains("Close the screens first") == true)
        #expect(ScreenListEditing.removalBlock(a2.id, profiles: [a, a2, s], activeOutputs: [a.id], screensOpen: true) == nil, "a screen that is not running can go")
    }

    @Test func theOnlyEnabledScreenOfItsRoleCannotBeRemovedWhileTheScreensAreOpen() {
        var onlyOne = a; onlyOne.isEnabled = true
        var other = a2; other.isEnabled = false
        #expect(ScreenListEditing.removalBlock(onlyOne.id, profiles: [onlyOne, other, s], activeOutputs: [], screensOpen: true) != nil)
        #expect(ScreenListEditing.removalBlock(onlyOne.id, profiles: [onlyOne, other, s], activeOutputs: [], screensOpen: false) == nil, "screens closed: nothing is on air")
        other.isEnabled = true
        #expect(ScreenListEditing.removalBlock(onlyOne.id, profiles: [onlyOne, other, s], activeOutputs: [], screensOpen: true) == nil, "a sibling of the role stays on air")
    }

    @Test func theLastScreenAndAnUnknownScreenAreRefusedToo() {
        #expect(ScreenListEditing.removalBlock(a.id, profiles: [a], activeOutputs: [], screensOpen: false) != nil)
        #expect(ScreenListEditing.removalBlock(UUID(), profiles: [a, s], activeOutputs: [], screensOpen: false) != nil)
    }

    @Test func theConfirmationNamesWhatGoesWithTheScreen() {
        let entry = ScreenLook(themeID: UUID(), visibleLayers: [.background])
        let l1 = Look(id: UUID(), name: "Worship", screens: [a.id: entry])
        let l2 = Look(id: UUID(), name: "Sermon", screens: [a.id: entry, a2.id: .standard])
        let l3 = Look(id: UUID(), name: "Other", screens: [s.id: .standard])
        let impact = ScreenListEditing.removalImpact(a.id, profiles: [a, a2, s], looks: [l1, l2, l3], hasStageLayoutChoice: true)
        #expect(impact.lookCount == 2)
        #expect(impact.handedTo == ["Worship": "Lobby"], "the Look with no entry for the other audience screen hands this one's entry to it; the other keeps its own")
        #expect(impact.text.contains("2 Looks") && impact.text.contains("Worship") && impact.text.contains("Lobby") && impact.text.contains("stage layout"))
        let none = ScreenListEditing.removalImpact(s.id, profiles: [a, a2, s], looks: [l1], hasStageLayoutChoice: false)
        #expect(none.lookCount == 0 && !none.text.contains("Looks"))
    }
}

@MainActor
@Suite struct FIXV_RemoveScreenModelTests {
    func model(_ seed: [ScreenProfile]) async throws -> SettingsModel {
        let m = SettingsModel(store: try LibraryStore.inMemory(), legacy: nil, defaultProfiles: { seed })
        await m.load()
        return m
    }

    @Test func aRunningScreenIsRefusedAndNothingChanges() async throws {
        let a = ScreenProfile(name: "Projector", role: .audience, destination: .window, isEnabled: true)
        let a2 = ScreenProfile(name: "Lobby", role: .audience, destination: .window, isEnabled: true)
        let m = try await model([a, a2])
        var removed: [UUID] = []
        m.onProfileRemoved = { removed.append($0) }
        let why = m.removeProfile(a.id, activeOutputs: [a.id], screensOpen: true)
        #expect(why != nil)
        #expect(m.profiles.map(\.id) == [a.id, a2.id] && removed.isEmpty)
    }

    @Test func aRemovedScreenIsForgottenByEveryPerScreenSetting() async throws {
        let a = ScreenProfile(name: "Projector", role: .audience, destination: .window)
        let a2 = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        let m = try await model([a, a2])
        var removed: [UUID] = []
        m.onProfileRemoved = { removed.append($0) }
        #expect(m.removeProfile(a.id) == nil)
        #expect(m.profiles.map(\.id) == [a2.id] && removed == [a.id])
    }

    @Test func theStageLayoutChoiceGoesWithTheScreen() async throws {
        let store = try LibraryStore.inMemory()
        let stage = StageModel(store: store)
        await stage.load()
        guard let layout = stage.createLayout(name: "Band") else { Issue.record("no layout"); return }
        let screen = UUID()
        stage.setLayout(layout.id, forScreen: screen)
        #expect(stage.layoutChoices[screen] == layout.id)
        stage.forgetScreen(screen)
        #expect(stage.layoutChoices[screen] == nil)
        #expect(stage.layoutChoices.isEmpty)
    }
}
