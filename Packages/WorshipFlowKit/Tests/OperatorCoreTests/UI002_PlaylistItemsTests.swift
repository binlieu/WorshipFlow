// UI-002 Part 5: playlist headers and countdowns in the workspace: stepping across them, going live on a countdown,
// the countdown reaching zero without moving the show on, deleting the live countdown, restoring onto a header.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI002_PlaylistItemsTests {
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    struct Rig {
        let store: LibraryStore
        let model: WorkspaceModel
        let clock = Clock()
        let songA: Presentation
        let songB: Presentation
    }

    func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        let r = Rig(store: store, model: model, songA: a, songB: b)
        model.countdownClock = { [clock = r.clock] in clock.now }
        return r
    }

    func build(_ r: Rig, _ steps: [String]) async {
        for s in steps {
            switch s {
            case "A": await r.model.addToPlaylist(r.songA.id)
            case "B": await r.model.addToPlaylist(r.songB.id)
            case "H": await r.model.addHeader("Worship")
            case "C": await r.model.addCountdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))
            default: break
            }
        }
    }

    @Test func headersAndCountdownsAreAddedInOrder() async throws {
        let r = try await rig()
        await build(r, ["H", "A", "C"])
        #expect(r.model.playlistItems.map(\.kind) == [.header(label: "Worship"), .presentation,
                                                       .countdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))])
    }

    @Test func nextAtTheEndOfASongSkipsTheHeaderAndStartsTheNextSong() async throws {
        let r = try await rig()
        await build(r, ["A", "H", "B"])
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive(at: 1)               // last slide of A
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "b1")
        #expect(r.model.liveCountdown == nil)
    }

    @Test func previousAtTheStartOfASongSkipsTheHeader() async throws {
        let r = try await rig()
        await build(r, ["A", "H", "B"])
        await r.model.openPlaylistItem(r.model.playlistItems[2].id)
        await r.model.goLive(at: 0)
        await r.model.previous()
        #expect(r.model.show.liveSlide?.primary == "a2")
    }

    @Test func nextIntoACountdownStartsItAndShowsTheTimeAsTheSlide() async throws {
        let r = try await rig()
        await build(r, ["A", "C"])
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive(at: 1)
        await r.model.next()
        #expect(r.model.liveCountdown?.itemID == r.model.playlistItems[1].id)
        #expect(r.model.show.liveSlide?.primary == "5:00")
        #expect(r.model.livePositionLine?.contains("Starting soon") == true)
    }

    @Test func theCountdownTicksDownAndStaysAtZeroWithoutMovingOn() async throws {
        let r = try await rig()
        await build(r, ["C", "B"])
        let countdown = r.model.playlistItems[0].id
        await r.model.openPlaylistItem(countdown)
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "5:00")
        r.clock.now.addTimeInterval(10)
        r.model.countdownTick()
        #expect(r.model.show.liveSlide?.primary == "4:50")
        r.clock.now.addTimeInterval(1000)
        r.model.countdownTick()
        #expect(r.model.show.liveSlide?.primary == "0:00")
        r.clock.now.addTimeInterval(1000)
        r.model.countdownTick()
        #expect(r.model.show.liveSlide?.primary == "0:00")
        #expect(r.model.liveItemID == countdown, "it never advances by itself")
        #expect(r.model.liveCountdown?.isFinished(at: r.clock.now) == true)
        await r.model.next()                                  // only the operator moves on
        #expect(r.model.show.liveSlide?.primary == "b1" && r.model.liveCountdown == nil)
    }

    @Test func aCountdownAsTheLastItemEndsTheStepping() async throws {
        let r = try await rig()
        await build(r, ["A", "C"])
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive(at: 1)
        await r.model.next()
        await r.model.next()                                  // nothing after the countdown
        #expect(r.model.liveCountdown != nil && r.model.show.liveSlide?.primary == "5:00")
    }

    @Test func aHeaderCannotBeSelectedOrTakenLive() async throws {
        let r = try await rig()
        await build(r, ["A", "H"])
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        let before = r.model.selectedPlaylistItemID
        await r.model.openPlaylistItem(r.model.playlistItems[1].id)
        #expect(r.model.selectedPlaylistItemID == before)
    }

    @Test func anEmptyPlaylistOrOneOfHeadersOnlyDoesNothingOnNext() async throws {
        let r = try await rig()
        await r.model.next()
        #expect(r.model.show.isStopped)
        await build(r, ["H", "H"])
        await r.model.next()
        #expect(r.model.show.isStopped && r.model.liveCountdown == nil)
    }

    @Test func deletingTheLiveCountdownClearsTheScreensAndStopsTheTimer() async throws {
        let r = try await rig()
        await build(r, ["C"])
        let id = r.model.playlistItems[0].id
        await r.model.openPlaylistItem(id)
        await r.model.goLive()
        await r.model.removePlaylistItem(id: id)
        #expect(r.model.liveCountdown == nil)
        #expect(r.model.show.liveSlide == nil || r.model.show.isCleared)
        r.clock.now.addTimeInterval(5)
        r.model.countdownTick()                               // no live countdown: nothing happens
        #expect(r.model.liveCountdown == nil)
    }

    @Test func stoppingTheShowStopsTheCountdown() async throws {
        let r = try await rig()
        await build(r, ["C"])
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive()
        r.model.stop()
        #expect(r.model.liveCountdown == nil && r.model.show.isStopped)
    }

    @Test func relaunchOnAHeaderLandsOnTheNextPlayableItem() async throws {
        let r = try await rig()
        await build(r, ["H", "A"])
        let header = r.model.playlistItems[0].id
        let place = WorkspacePlace(libraryID: r.model.selectedLibraryID, playlistID: r.model.selectedPlaylistID,
                                   playlistItemID: header, presentationID: nil, slideIndex: 0)
        try await r.store.setState(String(data: JSONEncoder().encode(place), encoding: .utf8) ?? "", for: WorkspaceModel.placeKey)
        let second = WorkspaceModel(store: r.store)
        await second.load()
        #expect(second.selectedPlaylistItemID == second.playlistItems[1].id)
        #expect(second.openPresentationID == r.songA.id)
    }

    @Test func relaunchOnACountdownSelectsItWithoutGoingLive() async throws {
        let r = try await rig()
        await build(r, ["A", "C"])
        let countdown = r.model.playlistItems[1].id
        let place = WorkspacePlace(libraryID: r.model.selectedLibraryID, playlistID: r.model.selectedPlaylistID,
                                   playlistItemID: countdown, presentationID: nil, slideIndex: 0)
        try await r.store.setState(String(data: JSONEncoder().encode(place), encoding: .utf8) ?? "", for: WorkspaceModel.placeKey)
        let second = WorkspaceModel(store: r.store)
        await second.load()
        #expect(second.selectedPlaylistItemID == countdown && second.show.isStopped && second.liveCountdown == nil)
    }
}
