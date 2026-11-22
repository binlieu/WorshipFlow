// FIX-I items 2 and 3: the arrow keys move the Preview selection and never the show; moving past the last slide of a presentation that was
// opened from the playlist selects the next playable playlist item (headers skipped), and the other way round; Return and Space keep
// their meaning. Everything here is Preview only: the live deck, the live place and the published scenes never change from an arrow key.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXI_SelectionMoveTests {
    struct Rig {
        let model: WorkspaceModel
        let a: UUID, countdown: UUID, b: UUID, loop: UUID, video: UUID
        let songA: Presentation
    }

    let loop = AnnouncementsSpec(label: "Announcements loop",
                                 items: [MediaItemSpec(assetID: UUID(), name: "Welcome.png", kind: .image)], secondsPerPicture: 10)
    let video = MediaItemSpec(assetID: UUID(), name: "Testimony.mov", kind: .video)

    /// Playlist: A (a1, a2), a header, a countdown, B (b1, b2), an announcements loop, a video.
    private func rig() async throws -> Rig {
        let model = WorkspaceModel(store: try LibraryStore.inMemory())
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        await model.addToPlaylist(a.id)
        await model.addHeader("Worship")
        await model.addCountdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))
        await model.addToPlaylist(b.id)
        await model.addAnnouncementsItem(loop)
        await model.addMediaItem(video)
        let ids = model.playlistItems.map(\.id)
        try #require(ids.count == 6)
        return Rig(model: model, a: ids[0], countdown: ids[2], b: ids[3], loop: ids[4], video: ids[5], songA: a)
    }

    private func audienceScene(_ model: WorkspaceModel) -> SceneDescription {
        let audience = ScreenProfile(name: "A", role: .audience, destination: .window)
        return PublishedScenes(state: model.show, clockText: nil, profiles: [audience]).scene(forScreen: audience.id) ?? SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
    }

    // MARK: item 2: the arrows never change what is live

    @Test func arrowsMoveThePreviewSelectionAndNeverTheLiveSlideOrThePublishedScenes() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        await r.model.goLive()
        let liveBefore = (r.model.show.liveIndex, r.model.show.liveSlide?.primary, r.model.liveItemID)
        let sceneBefore = audienceScene(r.model)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.show.selectedIndex == 1)
        await r.model.moveSelection(.left, columns: 3)
        #expect(r.model.show.selectedIndex == 0)
        await r.model.moveSelection(.down, columns: 1)
        #expect(r.model.show.selectedIndex == 1)
        await r.model.moveSelection(.up, columns: 1)
        #expect(r.model.show.selectedIndex == 0)
        #expect(r.model.show.liveIndex == liveBefore.0 && r.model.show.liveSlide?.primary == liveBefore.1 && r.model.liveItemID == liveBefore.2)
        #expect(audienceScene(r.model) == sceneBefore)
    }

    @Test func arrowsNeverGoLiveWhenNothingIsLive() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        for move: SelectionMove in [.right, .right, .right, .left, .down, .up] { await r.model.moveSelection(move, columns: 2) }
        #expect(r.model.show.liveDeck == nil && r.model.liveCountdown == nil && r.model.liveMediaItemID == nil)
    }

    @Test func returnTakesTheSelectedSlideLiveAndSpaceIsStillNext() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        await r.model.moveSelection(.right, columns: 3)
        await r.model.goLive()                              // Return from the slide grid
        #expect(r.model.show.liveSlide?.primary == "a2")
        await r.model.openPlaylistItem(r.a)
        await r.model.goLive(at: 0)
        await r.model.moveSelection(.right, columns: 3)     // an arrow, then Space: Next moves the live slide in one press
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "a2")
    }

    @Test func spaceFromThePlaylistsLastLiveSlideKeepsItsRuleOfCrossingIntoTheNextItem() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        await r.model.goLive(at: 1)
        await r.model.next()
        #expect(r.model.liveCountdown?.itemID == r.countdown)
    }

    // MARK: item 3: moving the selection past the end of a presentation

    @Test func rightPastTheLastSlideSelectsTheNextPlayableItemSkippingTheHeader() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        r.model.selectSlide(1)
        await r.model.goLive()
        let live = (r.model.show.liveIndex, r.model.liveItemID)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.selectedPlaylistItemID == r.countdown, "the countdown item is selected as an item")
        #expect(r.model.liveCountdown == nil, "selected, not started")
        #expect(r.model.show.liveIndex == live.0 && r.model.liveItemID == live.1, "live did not move")
    }

    @Test func rightFromAnItemSelectsTheNextOneAndOpensASongOnItsFirstSlide() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.countdown)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.openPlaylistItemID == r.b && r.model.selectedPlaylistItemID == r.b)
        #expect(r.model.show.selectedIndex == 0)
        #expect(r.model.show.liveDeck == nil)
    }

    @Test func leftBeforeTheFirstSlideSelectsTheLastSlideOfThePreviousItem() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.b)
        await r.model.moveSelection(.left, columns: 3)
        #expect(r.model.selectedPlaylistItemID == r.countdown)
        await r.model.moveSelection(.left, columns: 3)       // the header is skipped on the way back
        #expect(r.model.openPlaylistItemID == r.a)
        #expect(r.model.show.selectedIndex == 1, "the last slide of A")
        #expect(r.model.show.liveDeck == nil)
    }

    @Test func rightWalksOnThroughALoopAndAMediaItemAndStopsAtTheEndOfThePlaylist() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.b)
        r.model.selectSlide(1)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.selectedPlaylistItemID == r.loop)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.selectedPlaylistItemID == r.video)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.selectedPlaylistItemID == r.video, "the end of the playlist: it stops")
        #expect(r.model.show.liveDeck == nil && r.model.liveMediaItemID == nil, "nothing went live")
    }

    @Test func leftBeforeTheFirstSlideOfTheFirstItemStops() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        await r.model.moveSelection(.left, columns: 3)
        #expect(r.model.openPlaylistItemID == r.a && r.model.show.selectedIndex == 0)
    }

    @Test func aPresentationOpenedFromTheLibraryStopsAtItsLastSlide() async throws {
        let r = try await rig()
        await r.model.openPresentation(r.songA.id)           // from the library: no playlist item is open
        #expect(r.model.openPlaylistItemID == nil)
        r.model.selectSlide(1)
        await r.model.moveSelection(.right, columns: 3)
        #expect(r.model.show.selectedIndex == 1 && r.model.openPresentationID == r.songA.id)
        r.model.selectSlide(0)
        await r.model.moveSelection(.left, columns: 3)
        #expect(r.model.show.selectedIndex == 0 && r.model.openPresentationID == r.songA.id)
    }

    @Test func upAndDownStopAtTheEndsAndNeverCrossItems() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        r.model.selectSlide(1)
        await r.model.moveSelection(.down, columns: 3)
        #expect(r.model.openPlaylistItemID == r.a && r.model.show.selectedIndex == 1)
        r.model.selectSlide(0)
        await r.model.moveSelection(.up, columns: 3)
        #expect(r.model.openPlaylistItemID == r.a && r.model.show.selectedIndex == 0)
    }

    @Test func returnAfterCrossingTakesTheSelectedItemLiveAsToday() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.a)
        r.model.selectSlide(1)
        await r.model.moveSelection(.right, columns: 3)      // the countdown item
        await r.model.goLive()                                // Return
        #expect(r.model.liveCountdown?.itemID == r.countdown)
    }
}

@MainActor
@Suite struct FIXI_SelectionMoveScriptureTests {
    @Test func aPassageIsSelectedAsAnItemWhenTheSelectionCrossesIntoIt() async throws {
        let r = try await L4C.rig()
        let a = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await r.workspace.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(a.id)
        await r.scripture.show("John 3:16-17")
        await r.scripture.addToPlaylist()
        await r.workspace.addToPlaylist(b.id)
        let ids = r.workspace.playlistItems.map(\.id)
        await r.workspace.openPlaylistItem(ids[0])
        r.workspace.selectSlide(1)
        await r.workspace.moveSelection(.right, columns: 3)
        #expect(r.workspace.selectedPlaylistItemID == ids[1] && r.workspace.openPlaylistItemID == ids[1])
        #expect(r.workspace.show.liveDeck == nil)
        for _ in 0..<12 where r.workspace.openPlaylistItemID != ids[2] { await r.workspace.moveSelection(.right, columns: 3) }
        #expect(r.workspace.openPlaylistItemID == ids[2], "past the passage's last slide it goes on to the next song")
        #expect(r.workspace.show.liveDeck == nil)
    }
}
