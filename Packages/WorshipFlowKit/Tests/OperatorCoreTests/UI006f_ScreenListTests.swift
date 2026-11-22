// UI-006f (SC-03, SC-40, SC-21): adding and removing a screen, and the labels "Identify screens" shows.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI006f_ScreenListEditingTests {
    let a = ScreenProfile(name: "Audience", role: .audience, destination: .display(5))
    let s = ScreenProfile(name: "Stage", role: .stage, destination: .display(6))
    let b = ScreenProfile(name: "Livestream", role: .broadcast, destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied))

    @Test func aNewScreenIsOffAndInAWindow() {
        let n = ScreenListEditing.newScreen(existing: [a, s])
        #expect(!n.isEnabled && n.destination == .window && n.mirrors.isEmpty && n.name == "Screen 3")
        #expect(![a.id, s.id].contains(n.id))
    }

    @Test func aNewNameSkipsOneInUse() {
        let taken = ScreenProfile(name: " screen 3 ", role: .audience, destination: .window)
        #expect(ScreenListEditing.freshName(existing: [a, s, taken]) == "Screen 4")
        #expect(ScreenListEditing.freshName(existing: []) == "Screen 1")
    }

    @Test func theLastScreenCannotBeRemoved() {
        #expect(!ScreenListEditing.canRemove(a.id, from: [a]))
        #expect(ScreenListEditing.removing(a.id, from: [a]) == [a])
        #expect(ScreenListEditing.canRemove(a.id, from: [a, s]))
        #expect(!ScreenListEditing.canRemove(UUID(), from: [a, s]))
    }

    @Test func removingKeepsTheOrderOfTheOthers() {
        #expect(ScreenListEditing.removing(s.id, from: [a, s, b]) == [a, b])
    }

    @Test func selectionAfterARemovalIsTheNeighbour() {
        #expect(ScreenListEditing.selection(afterRemoving: s.id, from: [a, s, b]) == b.id)
        #expect(ScreenListEditing.selection(afterRemoving: b.id, from: [a, s, b]) == s.id)
        #expect(ScreenListEditing.selection(afterRemoving: a.id, from: [a]) == nil)
    }

    @Test func aRemovedScreensLookMovesToTheNextOfItsRoleSoNobodyChanges() {
        let a2 = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        let entry = ScreenLook(themeID: UUID(), visibleLayers: [.background])
        let look = Look(id: UUID(), name: "L", screens: [a.id: entry, s.id: .standard])
        #expect(look.screenLook(for: a2.id, in: [a, s, a2]) == entry)       // Lobby has no entry: it follows Audience's
        let after = ScreenListEditing.look(look, afterRemoving: a.id, before: [a, s, a2])
        #expect(after.screens[a.id] == nil && after.screens[s.id] == .standard)
        #expect(after.screenLook(for: a2.id, in: [s, a2]) == entry)
    }

    @Test func aSurvivorWithItsOwnEntryKeepsIt() {
        let a2 = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        let own = ScreenLook(themeID: nil, visibleLayers: [])
        let look = Look(id: UUID(), name: "L", screens: [a.id: .standard, a2.id: own])
        let after = ScreenListEditing.look(look, afterRemoving: a.id, before: [a, a2])
        #expect(after.screens == [a2.id: own])
    }

    @Test func aLookWithNoEntryForTheScreenIsUntouched() {
        let look = Look(id: UUID(), name: "L", screens: [s.id: .standard])
        #expect(ScreenListEditing.look(look, afterRemoving: a.id, before: [a, s]) == look)
    }

    @Test func identifyIsOnlyOfferedWhileTheScreensAreClosed() {
        #expect(ScreenIdentify.isAllowed(screensOpen: false))
        #expect(!ScreenIdentify.isAllowed(screensOpen: true))
    }

    @Test func identifyLabelsTheOperatorDisplayTheScreensDisplayAndAnUnusedOne() {
        let out = ScreenIdentify.labels(displays: [(1, "Built-in"), (5, "Projector"), (9, "Spare")], profiles: [a, s, b], operatorDisplay: 1)
        #expect(out.map(\.displayID) == [1, 5, 9])
        #expect(out[0].title == "Operator display")
        #expect(out[1].title == "Audience" && out[1].detail == "Audience (audience)")
        #expect(out[2].title == "Spare" && out[2].detail == "No screen is set to this display.")
    }

    @Test func identifyNamesEveryScreenSetToOneDisplayAndCountsMirrors() {
        var m = s; m.mirrors = [.display(5)]
        let out = ScreenIdentify.labels(displays: [(5, "Projector")], profiles: [a, m], operatorDisplay: nil)
        #expect(out[0].title == "Audience, Stage")
    }

    @Test func identifyOnTheOperatorDisplayWarnsWhenAScreenIsSetToIt() {
        let out = ScreenIdentify.labels(displays: [(5, "Built-in")], profiles: [a], operatorDisplay: 5)
        #expect(out[0].title == "Operator display" && out[0].detail.contains("Audience"))
    }
}

@MainActor
@Suite struct UI006f_SettingsModelScreenTests {
    func model(_ store: LibraryStore, _ seed: [ScreenProfile]) -> SettingsModel {
        SettingsModel(store: store, legacy: nil, defaultProfiles: { seed })
    }

    @Test func anAddedScreenIsKeptAndSurvivesARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let seed = [ScreenProfile(name: "Audience", role: .audience, destination: .window)]
        let first = model(store, seed)
        await first.load()
        var changes = 0
        first.onProfilesChange = { changes += 1 }
        let added = first.addProfile()
        #expect(first.profiles.count == 2 && first.profiles.last?.id == added?.id && changes == 1)
        await first.flush()
        let second = model(store, seed)
        await second.load()
        #expect(second.profiles.map(\.id) == first.profiles.map(\.id) && second.profiles.last?.isEnabled == false)
    }

    @Test func aRemovedScreenIsGoneAfterARelaunchAndItsLookMovesOn() async throws {
        let store = try LibraryStore.inMemory()
        let a = ScreenProfile(name: "A", role: .audience, destination: .window)
        let b = ScreenProfile(name: "B", role: .audience, destination: .window)
        let first = model(store, [a, b])
        await first.load()
        first.setLayer(.slide, visible: false, forScreen: a.id)
        let before = first.screenLook(for: a.id)
        #expect(first.screenLook(for: b.id) == before)           // B follows A's entry
        var changes = 0
        first.onProfilesChange = { changes += 1 }
        first.removeProfile(a.id)
        #expect(first.profiles.map(\.id) == [b.id] && changes == 1)
        #expect(first.screenLook(for: b.id) == before)
        await first.flush()
        let second = model(store, [a, b])
        await second.load()
        #expect(second.profiles.map(\.id) == [b.id] && second.screenLook(for: b.id) == before)
    }

    @Test func theLastScreenIsNotRemoved() async throws {
        let a = ScreenProfile(name: "A", role: .audience, destination: .window)
        let m = model(try LibraryStore.inMemory(), [a])
        await m.load()
        var changes = 0
        m.onProfilesChange = { changes += 1 }
        m.removeProfile(a.id)
        #expect(m.profiles == [a] && changes == 0)
    }
}
