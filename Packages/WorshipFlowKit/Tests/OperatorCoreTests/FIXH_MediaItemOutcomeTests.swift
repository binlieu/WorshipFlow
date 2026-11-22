// FIX-H items 6 and 11 (UI-005b): a file that cannot start is not marked live (the operator is told which file, the audience keeps
// what it had); the live chip names the live item; a loop that ended by itself no longer shows as live.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXH_MediaItemOutcomeTests {
    let video = MediaItemSpec(assetID: UUID(), name: "Baptism testimony.mov", kind: .video)
    let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in music.m4a", kind: .audio)
    let loop = AnnouncementsSpec(label: "Announcements loop",
                                 items: [MediaItemSpec(assetID: UUID(), name: "Welcome.png", kind: .image), MediaItemSpec(assetID: UUID(), name: "Picnic.png", kind: .image)],
                                 secondsPerPicture: 10)
    typealias Rig = FIXH_MediaItemModelTests.Rig

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

    // MARK: Item 6

    private func wired(_ r: Rig, audio: FIXHAudio? = nil) -> (FIXHForeground, MediaItemRunner) {
        let fg = FIXHForeground()
        for spec in [video] + loop.items { fg.add(spec.assetID, spec.name) }
        let runner = MediaItemRunner(foreground: fg, audio: audio, preview: { _ in }, now: { 0 })
        r.model.mediaItemHandler = { runner.handle($0) }
        r.model.mediaItemPreflight = { runner.preflight($0) }
        runner.onLoopEnded = { [weak model = r.model] in model?.mediaItemEnded() }
        return (fg, runner)
    }

    @Test func aMissingFileIsNotMarkedLiveTheOperatorIsToldAndTheAudienceKeepsItsSlide() async throws {
        let r = try await rig()
        let (fg, _) = wired(r)
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        fg.unreadable = [video.assetID]
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(r.model.liveMediaItemID == nil)
        #expect(r.model.lastError?.contains("Baptism testimony.mov") == true)
        #expect(r.model.show.liveSlide?.primary == "a1" && r.model.liveItemID == r.ids.a)
        #expect(fg.played.isEmpty)
    }

    @Test func aMissingFileWithTheScreensStoppedLeavesThemStopped() async throws {
        let r = try await rig()
        let (fg, _) = wired(r)
        fg.unreadable = [video.assetID]
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(r.model.show.isStopped && r.model.liveMediaItemID == nil && r.model.lastError?.contains("Baptism testimony.mov") == true)
    }

    @Test func nextOntoAnUnreadableFileSaysSoAndKeepsWhatWasLive() async throws {
        let r = try await rig()
        let (fg, _) = wired(r)
        fg.unreadable = [video.assetID]
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        await r.model.next()                                     // a2
        await r.model.next()                                     // onto the unreadable video
        #expect(r.model.liveMediaItemID == nil && r.model.show.liveSlide?.primary == "a2")
        #expect(r.model.lastError?.contains("Baptism testimony.mov") == true)
    }

    @Test func aFileThatStartedIsMarkedLive() async throws {
        let r = try await rig()
        let (fg, _) = wired(r)
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(r.model.liveMediaItemID == r.ids.video && fg.played == [video.assetID] && r.model.lastError == nil)
    }

    @Test func aSoundWithNoAudioPlayerIsNotMarkedLiveAndSaysSo() async throws {
        let r = try await rig()
        _ = wired(r)
        await r.model.openPlaylistItem(r.ids.sound)
        await r.model.goLive()
        #expect(r.model.liveMediaItemID == nil && r.model.lastError?.contains("Walk-in music.m4a") == true)
    }

    // MARK: Item 11

    @Test func theLiveChipNamesTheLiveItemAndAnEndedLoopIsNoLongerLive() async throws {
        let r = try await rig()
        let (fg, runner) = wired(r)
        await r.model.openPlaylistItem(r.ids.a)
        await r.model.goLive()
        #expect(r.model.liveChipLine == "a1")
        await r.model.openPlaylistItem(r.ids.video)
        await r.model.goLive()
        #expect(r.model.liveChipLine == "Baptism testimony.mov")
        await r.model.openPlaylistItem(r.ids.loop)
        await r.model.goLive()
        #expect(r.model.liveChipLine == "Announcements loop" && r.model.liveMediaMarkID == r.ids.loop)
        fg.operatorClears()                                       // the operator clears the foreground
        runner.tick()
        #expect(r.model.liveMediaMarkID == nil)                   // the playlist no longer shows it live
        #expect(r.model.liveChipLine == "a1")                     // the chip is back to the slide under it
        await r.model.next()                                      // and the step still goes on from the loop's place
        #expect(r.model.liveItemID == r.ids.b && r.model.show.liveSlide?.primary == "b1")
    }

    @Test func theRemotePlaylistShowsAMediaItemLiveOnlyWhileItIsLive() async throws {
        let r = try await rig()
        let audio = FIXHAudio()
        audio.names[sound.assetID] = sound.name
        _ = wired(r, audio: audio)
        await r.model.openPlaylistItem(r.ids.sound)
        await r.model.goLive()
        let state = RemoteStateBuilder.make(workspace: r.model, stage: nil, macros: [])
        #expect(state.playlist.map(\.isLive) == [false, false, true, false, false])      // a sound plays with the screens stopped
        r.model.stop()
        #expect(RemoteStateBuilder.make(workspace: r.model, stage: nil, macros: []).playlist.allSatisfy { !$0.isLive })
    }
}
