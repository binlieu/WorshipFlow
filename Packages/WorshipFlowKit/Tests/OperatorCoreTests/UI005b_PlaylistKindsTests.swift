// UI-005b item 4: the playlist item kinds the design shows besides songs: a media file, an announcements loop and a sermon. Each is
// selected (preview only), taken live, stepped from with Next and Previous (never by itself), restored at launch and handled by
// every switch over kinds. The media itself is played by the app; here the model's commands to it are recorded.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
final class MediaCommands {
    var list: [MediaItemCommand] = []
    func attach(to model: WorkspaceModel) { model.onMediaItem = { [self] command in list.append(command) } }
}

@MainActor
@Suite struct UI005b_PlaylistKindsTests {
    let video = MediaItemSpec(assetID: UUID(), name: "Baptism testimony.mov", kind: .video)
    let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in music.m4a", kind: .audio)
    let loop = AnnouncementsSpec(label: "Announcements loop",
                                 items: [MediaItemSpec(assetID: UUID(), name: "Welcome.png", kind: .image), MediaItemSpec(assetID: UUID(), name: "Picnic.png", kind: .image)],
                                 secondsPerPicture: 10)

    struct Rig {
        var model: WorkspaceModel
        var store: LibraryStore
        var commands: MediaCommands
        var a: Presentation, sermon: Presentation, b: Presentation
        /// Playlist order: A, video, sound, announcements loop, sermon, B.
        var ids: (a: UUID, video: UUID, sound: UUID, loop: UUID, sermon: UUID, b: UUID)
    }

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        let commands = MediaCommands()
        commands.attach(to: model)
        await model.load()
        let songs = try #require(model.libraries.first)
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 2))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 2))
        await model.createLibrary(name: "Sermons", kind: .sermons)
        let sermon = try #require(await model.importLyrics(title: "Saved by Grace", primaryText: "s1", secondaryText: nil, maxLines: 2))
        await model.selectLibrary(songs.id)
        await model.addToPlaylist(a.id)
        await model.addMediaItem(video)
        await model.addMediaItem(sound)
        await model.addAnnouncementsItem(loop)
        await model.addToPlaylist(sermon.id)          // from a sermons library: a sermon item
        await model.addToPlaylist(b.id)
        let items = model.playlistItems
        try #require(items.count == 6)
        return Rig(model: model, store: store, commands: commands, a: a, sermon: sermon, b: b,
                   ids: (items[0].id, items[1].id, items[2].id, items[3].id, items[4].id, items[5].id))
    }

    @Test func eachKindIsStoredWithItsTitleAndReadBack() async throws {
        let r = try await rig()
        #expect(r.model.playlistItems.map(\.kind) == [.presentation, .media(video), .media(sound), .announcements(loop), .sermon, .presentation])
        #expect(r.model.playlistItems.map(\.title) == ["A", "Baptism testimony.mov", "Walk-in music.m4a", "Announcements loop", "Saved by Grace", "B"])
        #expect(try await r.store.playlistItems(of: try #require(r.model.selectedPlaylistID)).map(\.kind) == r.model.playlistItems.map(\.kind))
        #expect(r.model.emptyPlaylistItemIDs.isEmpty)           // a file or a loop has no slides, and that is not "empty"
    }

    @Test func selectingAMediaItemPreviewsItAndNeverChangesLive() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        let live = r.model.show.liveSlide
        r.commands.list = []
        for id in [r.ids.video, r.ids.sound, r.ids.loop] { await r.model.openPlaylistItem(id) }
        #expect(r.model.selectedPlaylistItemID == r.ids.loop)
        #expect(r.model.show.liveSlide == live && live?.primary == "a1")
        #expect(r.commands.list == [.preview(video), .preview(sound)])          // a loop is previewed by its pictures in the bin, not played
    }

    @Test func goLiveOnAVideoPlaysItOverTheScreensAndNamesItInTheTransportBar() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(r.commands.list == [.preview(video), .play(video)])
        #expect(r.model.liveMediaItemID == r.ids.video)
        #expect(r.model.show.liveDeck != nil && !r.model.show.isStopped)         // the screens are running, with no words on them
        #expect(r.model.show.liveSlide?.primary == "")
        #expect(r.model.liveTitle == "Baptism testimony.mov")
    }

    @Test func goLiveOnASoundPlaysItAndLeavesTheSlideAlone() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        await r.model.openPlaylistItem(r.ids.sound)
        await r.model.goLive()
        #expect(r.commands.list.last == .play(sound))
        #expect(r.model.show.liveSlide?.primary == "a1")
        #expect(r.model.liveMediaItemID == r.ids.sound)
    }

    @Test func nextAndPreviousStepOutOfAMediaItemAndNothingMovesItOnItsOwn() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        await r.model.flush()
        r.model.countdownTick()
        #expect(r.model.liveMediaItemID == r.ids.video && r.commands.list == [.preview(video), .play(video)])   // time alone changes nothing
        await r.model.next()
        #expect(r.commands.list.contains(.stop(video)))
        #expect(r.model.liveMediaItemID == r.ids.sound)                      // the next playable item, a sound, played
        #expect(r.commands.list.last == .play(sound))
        await r.model.next()
        #expect(r.commands.list.suffix(2) == [.stop(sound), .startLoop(loop)])
        await r.model.previous()
        #expect(r.commands.list.suffix(2) == [.stopLoop(loop), .play(sound)])
        await r.model.next(); await r.model.next()
        #expect(r.commands.list.suffix(1) == [.stopLoop(loop)])
        #expect(r.model.liveMediaItemID == nil)
        #expect(r.model.show.liveSlide?.primary == "s1")                      // the sermon's own slides
        #expect(r.model.liveItemID == r.ids.sermon)
        await r.model.next()
        #expect(r.model.show.liveSlide?.primary == "b1")
    }

    @Test func previousFromTheFirstMediaItemGoesBackToTheSongsLastSlide() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        await r.model.previous()
        #expect(r.model.show.liveSlide?.primary == "a2")
        #expect(r.model.liveMediaItemID == nil && r.commands.list.contains(.stop(video)))
    }

    @Test func aSlideTakenLiveEndsTheMediaItemThatWasLive() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        #expect(r.commands.list.contains(.stop(video)) && r.model.liveMediaItemID == nil)
    }

    @Test func stopEndsWhateverMediaItemIsPlaying() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        #expect(r.commands.list.last == .startLoop(loop))
        r.model.stop()
        #expect(r.commands.list.last == .stopLoop(loop) && r.model.liveMediaItemID == nil)
    }

    @Test func removingTheLiveItemOrClearingAllEndsIt() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        await r.model.removePlaylistItem(id: r.ids.video)
        #expect(r.commands.list.last == .stop(video) && r.model.liveMediaItemID == nil)
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        r.model.clearAll()
        #expect(r.commands.list.last == .stopLoop(loop) && r.model.liveMediaItemID == nil)
    }

    @Test func aRelaunchBringsTheSelectedMediaItemBackToPreviewOnly() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.flush()
        let again = WorkspaceModel(store: r.store)
        let commands = MediaCommands()
        commands.attach(to: again)
        await again.load()
        #expect(again.selectedPlaylistItemID == r.ids.video)
        #expect(commands.list == [.preview(video)])
        #expect(again.show.isStopped && again.liveMediaItemID == nil)
    }

    @Test func aSermonItemPlaysLikeAPresentation() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.ids.sermon)
        #expect(r.model.openPresentationID == r.sermon.id && r.model.slides.map(\.content.primary) == ["s1"])
        await r.model.goLive()
        #expect(r.model.show.liveSlide?.primary == "s1")
        #expect(r.commands.list.isEmpty)
    }

    @Test func anUnknownKindIsAHeaderAndIsSkipped() {
        let unknown = PlaylistItemKind(storedKind: "from-a-newer-build", payload: "{}")
        #expect(unknown == .header(label: "Unknown item") && !unknown.isSelectableLive)
        #expect(PlaylistStepping.target(kinds: [.presentation, unknown, .sermon], from: 0, direction: 1) == 2)
        #expect(PlaylistItemKind.media(MediaItemSpec(assetID: UUID(), name: "x", kind: .video)).isSelectableLive)
        // A media item whose payload cannot be read degrades to a header instead of failing the playlist.
        #expect(PlaylistItemKind(storedKind: "media", payload: "{not json") == .header(label: "Media file"))
        #expect(PlaylistItemKind(storedKind: "announcements", payload: nil) == .header(label: "Announcements"))
    }

    @Test func theLoopShowsOnePictureAtATimeAndWrapsAround() {
        #expect(loop.pictureIndex(afterSeconds: 0) == 0 && loop.pictureIndex(afterSeconds: 9.9) == 0)
        #expect(loop.pictureIndex(afterSeconds: 10) == 1 && loop.pictureIndex(afterSeconds: 20) == 0 && loop.pictureIndex(afterSeconds: 35) == 1)
        let one = AnnouncementsSpec(label: "One", items: [MediaItemSpec(assetID: UUID(), name: "v.mov", kind: .video)])
        #expect(one.isVideoLoop && one.pictureIndex(afterSeconds: 500) == 0)
        #expect(!loop.isVideoLoop)
        let sounds = AnnouncementsSpec(label: "x", items: [sound], secondsPerPicture: 1)
        #expect(sounds.items.isEmpty && sounds.secondsPerPicture == 3)          // a sound is not an announcement; the time is held in range
    }
}
