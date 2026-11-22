// FIX-T item 7 (low findings L10 and L13): the transport keys are told off by the window's identity, not its title; the slide header's
// source of truth, `openPlaylistItemID`, is observed. Written before the fix where a test can show the old behaviour.
import Testing
import Foundation
import Observation
import Domain
import Persistence
@testable import OperatorCore

final class FIXTChanged: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false
    func fire() { lock.withLock { _fired = true } }
    var fired: Bool { lock.withLock { _fired } }
}

@MainActor
@Suite struct FIXT_LowFindingsTests {
    // MARK: L10

    @Test func aPlaylistNamedLikeTheHardwareTestWindowDoesNotSwitchTheTransportKeysOff() {
        // The operator window's title is the playlist's name; its identifier says what it is.
        #expect(KeyRouting.transportKeysActive(windowTitle: "Hardware Test", windowIdentifier: "workspace-AppWindow-1", launchedWithHardwareTest: false))
        #expect(KeyRouting.transportKeysActive(windowTitle: "About WorshipFlow", windowIdentifier: "workspace-AppWindow-1", launchedWithHardwareTest: false))
        #expect(KeyRouting.isHardwareTestWindow(title: "Hardware Test", identifier: "workspace-AppWindow-1") == false)
        #expect(KeyRouting.isAboutWindow(title: "About WorshipFlow", identifier: "workspace-AppWindow-1") == false)
    }

    @Test func theRealHardwareTestAndAboutWindowsStillSwitchThemOffByIdentifier() {
        #expect(KeyRouting.transportKeysActive(windowTitle: "Anything", windowIdentifier: "hardware-test-AppWindow-2", launchedWithHardwareTest: false) == false)
        #expect(KeyRouting.transportKeysActive(windowTitle: "Anything", windowIdentifier: "about-AppWindow-3", launchedWithHardwareTest: false) == false)
    }

    @Test func aWindowWithNoIdentifierIsStillToldByItsTitle() {
        #expect(KeyRouting.isHardwareTestWindow(title: "Hardware Test", identifier: nil))
        #expect(KeyRouting.isHardwareTestWindow(title: "Hardware Test", identifier: ""))
        #expect(KeyRouting.isAboutWindow(title: "About WorshipFlow", identifier: nil))
        #expect(KeyRouting.isHardwareTestWindow(title: "Sunday", identifier: nil) == false)
    }

    // MARK: L13

    @Test func openingAPlaylistItemNotifiesAReaderOfTheOpenItem() async throws {
        let m = WorkspaceModel(store: try LibraryStore.inMemory(), clock: ManualSaveClock())
        await m.load()
        let a = try #require(await m.importLyrics(title: "A", primaryText: "a1", secondaryText: nil, maxLines: 1))
        let b = try #require(await m.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 1))
        await m.addToPlaylist(a.id)
        await m.addToPlaylist(b.id)
        let items = m.playlistItems.map(\.id)
        await m.openPlaylistItem(items[0])
        let changed = FIXTChanged()
        withObservationTracking { _ = m.openPlaylistItemID } onChange: { changed.fire() }
        await m.openPlaylistItem(items[1])
        #expect(m.openPlaylistItemID == items[1])
        #expect(changed.fired, "a view that reads only the open item is told when it changes")
    }
}
