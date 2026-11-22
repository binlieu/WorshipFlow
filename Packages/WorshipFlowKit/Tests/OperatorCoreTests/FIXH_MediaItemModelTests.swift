// FIX-H items 2, 3, 6, 11 and 15 (UI-005b): the workspace model's handling of media-file and loop playlist items.
//   2  taking a media item live lifts Blackout, Cleared and background-hidden like a slide does
//   3  switching or deleting the playlist ends the live media item, and Next / Previous never go dead
//   6  a file that cannot start is not marked live, the operator is told which file, the audience keeps what it had
//  11  the live chip names the item; a loop that ended by itself no longer shows as live
//  15  relaunch restore for each new kind, and the cue path
import Testing
import Foundation
import CueEngine
import CueStore
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXH_MediaItemModelTests {
    let video = MediaItemSpec(assetID: UUID(), name: "Baptism testimony.mov", kind: .video)
    let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in music.m4a", kind: .audio)
    let loop = AnnouncementsSpec(label: "Announcements loop",
                                 items: [MediaItemSpec(assetID: UUID(), name: "Welcome.png", kind: .image), MediaItemSpec(assetID: UUID(), name: "Picnic.png", kind: .image)],
                                 secondsPerPicture: 10)

    struct Rig {
        var model: WorkspaceModel
        var store: LibraryStore
        var commands: MediaCommands
        var ids: (a: UUID, video: UUID, sound: UUID, loop: UUID, b: UUID)
    }

    /// Playlist order: A (two slides), video, sound, loop, B.
    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        let commands = MediaCommands()
        commands.attach(to: model)
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 2))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 2))
        await model.addToPlaylist(a.id)
        await model.addMediaItem(video)
        await model.addMediaItem(sound)
        await model.addAnnouncementsItem(loop)
        await model.addToPlaylist(b.id)
        let items = model.playlistItems
        try #require(items.count == 5)
        return Rig(model: model, store: store, commands: commands, ids: (items[0].id, items[1].id, items[2].id, items[3].id, items[4].id))
    }

    // MARK: Item 2

    @Test func nextOntoAVideoWhileBlackedOutLiftsBlackoutAndPlaysFromItsStart() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        r.model.blackout()
        #expect(r.model.show.isBlackedOut)
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.next()                                   // a2
        r.model.blackout()
        r.commands.list = []
        await r.model.next()                                   // onto the video
        #expect(r.model.liveMediaItemID == r.ids.video)
        #expect(!r.model.show.isBlackedOut)
        #expect(r.commands.list == [.play(video)])
    }

    @Test func goLiveOnAVideoWhileBlackedOutClearedOrBackgroundHiddenLiftsEachOfThem() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        r.model.blackout()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(!r.model.show.isBlackedOut && !r.model.show.isCleared)
        r.model.clear()
        r.model.clearBackground()
        #expect(r.model.show.isCleared && r.model.show.isBackgroundCleared)
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        #expect(!r.model.show.isCleared && !r.model.show.isBackgroundCleared)
        #expect(r.model.show.liveSlide?.primary == "a1")        // the slide underneath is where it was
        r.model.blackout()
        await r.model.openPlaylistItem(r.ids.sound)
        await r.model.goLive()
        #expect(!r.model.show.isBlackedOut)                      // a sound starts audibly, not under Blackout
    }

    // MARK: Item 3

    @Test func switchingPlaylistWhileALoopIsLiveEndsTheLoopAndNextStillWorks() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        await r.model.createPlaylist(name: "Other")
        #expect(r.commands.list.last == .stopLoop(loop))
        #expect(r.model.liveMediaItemID == nil)
        await r.model.next()                                     // not dead: the slide of the song still on the screens moves
        #expect(r.model.show.liveSlide?.primary == "a2")
    }

    @Test func selectingAnotherPlaylistWithAnAudioItemLiveStopsTheSound() async throws {
        let r = try await rig()
        await r.model.createPlaylist(name: "Other")
        let other = try #require(r.model.selectedPlaylistID)
        let first = try #require(r.model.playlists.first { $0.id != other })
        await r.model.selectPlaylist(first.id)
        await r.model.openPlaylistItem(r.ids.sound)
        await r.model.goLive()
        #expect(r.commands.list.last == .play(sound))
        await r.model.selectPlaylist(other)
        #expect(r.commands.list.last == .stop(sound))
        #expect(r.model.liveMediaItemID == nil)
    }

    @Test func deletingThePlaylistWithALoopOrASoundLiveEndsThem() async throws {
        let r = try await rig()
        let playlist = try #require(r.model.selectedPlaylistID)
        await r.model.createPlaylist(name: "Spare")
        await r.model.selectPlaylist(playlist)
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        await r.model.deletePlaylist(id: playlist)
        #expect(r.commands.list.last == .stopLoop(loop) && r.model.liveMediaItemID == nil)
        // A sound, in a second playlist.
        await r.model.addMediaItem(sound)
        let item = try #require(r.model.playlistItems.first)
        await r.model.openPlaylistItem(item.id)
        await r.model.goLive()
        #expect(r.commands.list.last == .play(sound))
        let current = try #require(r.model.selectedPlaylistID)
        await r.model.deletePlaylist(id: current)
        #expect(r.commands.list.last == .stop(sound) && r.model.liveMediaItemID == nil)
    }

    @Test func nextAndPreviousFallThroughWhenTheLiveItemIsNoLongerInTheList() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        try await r.store.removePlaylistItem(id: r.ids.video)       // behind the model's back (an import, another window)
        await r.model.reloadPlaylistItems()
        await r.model.next()
        #expect(r.model.liveMediaItemID == nil && r.commands.list.last == .stop(video))      // ended from the stored copy
        #expect(r.model.show.liveSlide?.primary == "a2")                                      // and Next moved the slide
        await r.model.previous()
        #expect(r.model.show.liveSlide?.primary == "a1")
    }

    // MARK: Item 15

    @Test func aRelaunchBringsEachNewKindBackToPreviewAndNeverLive() async throws {
        let r = try await rig()
        for id in [r.ids.sound, r.ids.loop, r.ids.video] {
            await r.model.openPlaylistItem(id)
            await r.model.flush()
            let again = WorkspaceModel(store: r.store)
            let commands = MediaCommands()
            commands.attach(to: again)
            await again.load()
            #expect(again.selectedPlaylistItemID == id)
            #expect(again.show.isStopped && again.liveMediaItemID == nil && again.liveItemID == nil)
            #expect(!commands.list.contains { if case .play = $0 { true } else if case .startLoop = $0 { true } else { false } })
        }
    }

    @Test func aRelaunchOnASermonOpensItInPreviewOnly() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        await model.createLibrary(name: "Sermons", kind: .sermons)
        let sermon = try #require(await model.importLyrics(title: "Saved by Grace", primaryText: "s1", secondaryText: nil, maxLines: 2))
        await model.addToPlaylist(sermon.id)
        let item = try #require(model.playlistItems.first)
        await model.openPlaylistItem(item.id)
        await model.flush()
        let again = WorkspaceModel(store: store)
        await again.load()
        #expect(again.selectedPlaylistItemID == item.id && again.openPresentationID == sermon.id)
        #expect(again.show.isStopped && again.show.liveDeck == nil)
    }

    @Test func theCuePathStepsOutOfALiveMediaItemInsteadOfMovingTheSlideUnderIt() async throws {
        let r = try await rig()
        let show = FakeShow()
        let cue = CueModel(store: CueStore(library: r.store), ports: CuePorts(transport: r.model, looks: show, stage: show, media: show, midiOut: { show }), clock: TestCueClock())
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        _ = await cue.run(.transport(.next), from: .midi)
        #expect(r.commands.list.contains(.stop(video)))
        #expect(r.model.liveMediaItemID == r.ids.sound)           // the next playable item, as the Next key does
        #expect(r.model.show.liveSlide?.primary == "a1")           // and the slide underneath did not move
        _ = await cue.run(.transport(.previous), from: .midi)
        #expect(r.model.liveMediaItemID == r.ids.video)
    }

    @Test func aMediaItemIsAskedForByTheCueGoLiveToo() async throws {
        let r = try await rig()
        let show = FakeShow()
        let cue = CueModel(store: CueStore(library: r.store), ports: CuePorts(transport: r.model, looks: show, stage: show, media: show, midiOut: { show }), clock: TestCueClock())
        await r.model.openPlaylistItem(r.ids.loop)
        _ = await cue.run(.goLive, from: .button)
        #expect(r.commands.list.last == .startLoop(loop) && r.model.liveMediaItemID == r.ids.loop)
    }
}
