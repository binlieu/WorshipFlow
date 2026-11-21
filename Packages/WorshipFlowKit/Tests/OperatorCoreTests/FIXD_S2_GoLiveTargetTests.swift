// FIX-D S2: Go Live acts on what the operator chose last. Choosing a slide after choosing a countdown makes the slide the
// target, and the live place is recorded against the playlist item the slide belongs to, so Next and Previous step from the
// right place. Only API that existed before FIX-D, so the tests can be run against the earlier model to see them fail.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXD_S2_GoLiveTargetTests {
    struct Rig {
        let store: LibraryStore
        let model: WorkspaceModel
        let songA: Presentation
        let songB: Presentation
        let itemA: UUID
        let countdown: UUID
        let itemB: UUID
    }

    /// Playlist: song A (two slides), a countdown, song B (two slides).
    func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        await model.addToPlaylist(a.id)
        await model.addCountdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))
        await model.addToPlaylist(b.id)
        let ids = model.playlistItems.map(\.id)
        return Rig(store: store, model: model, songA: a, songB: b, itemA: ids[0], countdown: ids[1], itemB: ids[2])
    }

    // MARK: the sequence in the finding

    @Test func aSlideChosenAfterACountdownIsWhatGoLiveStarts() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)          // click the countdown
        r.model.selectSlide(1)                                // then a slide of the song still shown
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "a2", "\(String(describing: r.model.show.liveSlide?.primary))")
        #expect(r.model.liveCountdown == nil)
        #expect(r.model.liveItemID == r.itemA)                // recorded against the item the slide belongs to
        #expect(r.model.selectedPlaylistItemID == r.itemA)
    }

    @Test func nextAfterThatStepsFromTheSongNotFromTheCountdown() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)
        r.model.selectSlide(0)
        await r.model.goLive()
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "a2")      // within the song
        await r.model.next()
        #expect(r.model.liveCountdown?.itemID == r.countdown) // then into the countdown that follows the song
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "b1" && r.model.liveItemID == r.itemB)
    }

    @Test func previousAfterThatStepsBackFromTheSong() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemB)
        await r.model.openPlaylistItem(r.countdown)
        r.model.selectSlide(0)                                // slide 0 of song B, still the open presentation
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "b1" && r.model.liveItemID == r.itemB)
        await r.model.previous()                              // before the first slide of B is the countdown
        #expect(r.model.liveCountdown?.itemID == r.countdown)
        await r.model.previous()
        #expect(r.model.show.liveSlide?.primary == "a2" && r.model.liveItemID == r.itemA)
    }

    // MARK: the countdown is still chosen when it was chosen last

    @Test func aCountdownChosenLastStillStartsTheCountdown() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        r.model.selectSlide(1)
        await r.model.openPlaylistItem(r.countdown)           // the countdown is chosen last
        await r.model.goLive()
        #expect(r.model.liveCountdown?.itemID == r.countdown)
        #expect(r.model.liveItemID == r.countdown)
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "b1")      // from the countdown to the next song
        await r.model.previous()
        #expect(r.model.liveCountdown?.itemID == r.countdown)
    }

    @Test func aSlideChosenWhileTheCountdownIsLiveStartsThatSlideAndNextStepsFromIt() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)
        await r.model.goLive()                                // the countdown is live
        #expect(r.model.liveCountdown != nil)
        r.model.selectSlide(1)                                // the operator now picks a slide of song A
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "a2" && r.model.liveCountdown == nil && r.model.liveItemID == r.itemA)
        await r.model.next()
        #expect(r.model.liveCountdown?.itemID == r.countdown)
    }

    @Test func aDoubleClickedSlideIsRecordedAgainstItsOwnItemWhileACountdownIsSelected() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)
        r.model.goLive(at: 1)                                 // double-click on a slide
        #expect(r.model.show.liveSlide?.primary == "a2" && r.model.liveItemID == r.itemA && r.model.liveCountdown == nil)
        await r.model.previous()
        #expect(r.model.show.liveSlide?.primary == "a1")
    }

    @Test func nextWithNothingLiveAndACountdownSelectedPutsTheSongsSlideLiveAgainstTheSong() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)
        await r.model.next()                                  // nothing live yet: the preview's slide goes live
        #expect(r.model.show.liveSlide?.primary == "a1" && r.model.liveCountdown == nil)
        #expect(r.model.liveItemID == r.itemA)
        await r.model.next(); await r.model.next()
        #expect(r.model.liveCountdown?.itemID == r.countdown)
    }

    @Test func aSongOpenedFromTheLibraryHasNoItemAndASlideChosenAfterACountdownStartsTheSlide() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.countdown)           // countdown selected, no song open yet
        await r.model.openPresentation(r.songA.id)            // a song opened from the library: not from the playlist
        #expect(r.model.selectedPlaylistItemID == nil)
        r.model.selectSlide(1)
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "a2" && r.model.liveCountdown == nil)
        #expect(r.model.liveItemID == nil)
    }

    @Test func aCountdownSelectedAfterALibrarySongThenASlideStillGoesToTheSlide() async throws {
        let r = try await rig()
        await r.model.openPresentation(r.songA.id)
        await r.model.openPlaylistItem(r.countdown)
        r.model.selectSlide(0)
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "a1" && r.model.liveCountdown == nil)
    }

    @Test func theSavedPlaceFollowsTheLastChoice() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.itemA)
        await r.model.openPlaylistItem(r.countdown)
        r.model.selectSlide(1)
        #expect(r.model.selectedPlaylistItemID == r.itemA)
        await r.model.flush()
        let again = WorkspaceModel(store: r.store)
        await again.load()
        #expect(again.selectedPlaylistItemID == r.itemA)
        #expect(again.slides.count == 2 && again.show.selectedIndex == 1)
    }
}
