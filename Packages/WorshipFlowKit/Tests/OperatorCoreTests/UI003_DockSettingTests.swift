// UI-003 Part 1: the media dock's height and collapsed state are remembered with the library's settings.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI003_DockSettingTests {
    func model(_ store: LibraryStore) -> SettingsModel {
        SettingsModel(store: store, legacy: nil, defaultProfiles: { [ScreenProfile(name: "A", role: .audience, destination: .window)] })
    }

    @Test func defaultsAreOpenAtTheDefaultHeight() async throws {
        let m = model(try LibraryStore.inMemory())
        await m.load()
        #expect(m.mediaDock == MediaDockState() && !m.mediaDock.isCollapsed && m.mediaDock.height == MediaDock.defaultHeight)
    }

    @Test func heightAndCollapsedSurviveARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let first = model(store)
        await first.load()
        first.setMediaDock(height: 260)
        first.setMediaDock(collapsed: true)
        #expect(first.mediaDock.height == 260 && first.mediaDock.isCollapsed)
        await first.flush()
        let second = model(store)
        await second.load()
        #expect(second.mediaDock.height == 260 && second.mediaDock.isCollapsed)
    }

    @Test func anUnusableHeightIsIgnored() async throws {
        let m = model(try LibraryStore.inMemory())
        await m.load()
        m.setMediaDock(height: .nan)
        m.setMediaDock(height: -5)
        #expect(m.mediaDock.height == MediaDock.defaultHeight)
    }

    @Test func aDamagedStoredValueFallsBackToTheDefault() async throws {
        let store = try LibraryStore.inMemory()
        try await store.setState("not json", for: SettingsModel.mediaDockKey)
        let m = model(store)
        await m.load()
        #expect(m.mediaDock == MediaDockState())
    }
}
