// UI-005b item 6: the design's four Looks are seeded on a NEW library only. An existing library keeps its Looks exactly.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI005b_SeedLooksTests {
    func model(_ store: LibraryStore) -> SettingsModel {
        SettingsModel(store: store, legacy: nil, defaultProfiles: SettingsModelTests.defaults)
    }

    @Test func aNewLibraryGetsTheFourLooksWithFullSelected() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        await settings.seedDesignLooks(isNewLibrary: true)
        await settings.flush()
        #expect(settings.looks.map(\.name) == ["Full", "Notes", "Lower 3rd", "BG only"])
        #expect(settings.currentLook?.name == "Full")
        #expect(try await store.looks().map(\.name).sorted() == ["BG only", "Full", "Lower 3rd", "Notes"])
        // Stored, so the next launch reads the same four and the selection.
        let again = model(store)
        await again.load()
        #expect(Set(again.looks.map(\.name)) == ["Full", "Notes", "Lower 3rd", "BG only"] && again.currentLook?.name == "Full")
        // Seeding twice (a second launch of a new library) changes nothing.
        let ids = Set(again.looks.map(\.id))
        await again.seedDesignLooks(isNewLibrary: true)
        #expect(Set(again.looks.map(\.id)) == ids)
    }

    @Test func notesSeedsTheRolesOfTheScreensTheLibraryHas() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        await settings.seedDesignLooks(isNewLibrary: true)
        let notes = try #require(settings.looks.first { $0.name == "Notes" })
        let byRole = Dictionary(uniqueKeysWithValues: settings.profiles.map { ($0.role, notes.screenLook(for: $0.id).visibleLayers) })
        #expect(byRole[.audience] == [.background, .slide] && byRole[.broadcast] == [.slide] && byRole[.stage] == [.background, .slide, .props])
    }

    @Test func anExistingLibraryIsNotChanged() async throws {
        let store = try LibraryStore.inMemory()
        let first = model(store)
        await first.load()                                        // a library that has been used: its single Standard Look
        await first.flush()
        let before = first.looks
        let settings = model(store)
        await settings.load()
        await settings.seedDesignLooks(isNewLibrary: false)       // the app says it is not new
        #expect(settings.looks == before && settings.looks.map(\.name) == ["Standard"])
        #expect(try await store.looks().map(\.name) == ["Standard"])
    }

    @Test func aLibraryWhoseLooksTheOperatorChangedIsNeverReplaced() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        settings.renameLook(try #require(settings.looks.first).id, to: "Sunday")
        _ = settings.addLook()
        await settings.flush()
        let before = settings.looks
        await settings.seedDesignLooks(isNewLibrary: true)       // even if the app wrongly said new: only a pristine Standard is replaced
        #expect(settings.looks == before)
    }
}
