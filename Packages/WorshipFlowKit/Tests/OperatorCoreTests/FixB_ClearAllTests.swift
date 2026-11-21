// FIX-B R8 / R17: Clear hides the words only; Clear all also stops the foreground clip; closing the screens stops it too.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct ClearAllTests {
    struct Rig {
        let workspace: WorkspaceModel
        let media: MediaModel
        let clip: MediaAsset
    }

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let media = MediaModel(store: store, prober: FakeProber(), isAvailable: { _ in true })
        await media.load()
        let clip = try #require(await media.add(url: URL(fileURLWithPath: "/media/loop.mov")))
        // The same wiring the app makes.
        workspace.onShowChange = { state in media.showStateChanged(isLive: !state.isStopped) }
        workspace.onClearAll = { media.stopForeground() }
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        media.playForeground(clip.id)
        #expect(media.layers.foreground != nil)
        return Rig(workspace: workspace, media: media, clip: clip)
    }

    @Test func clearHidesTheWordsButLeavesTheClipPlaying() async throws {
        let r = try await rig()
        r.workspace.clear()
        #expect(r.workspace.show.isCleared && r.workspace.show.liveSlide == nil)
        #expect(r.media.layers.foreground != nil)
    }

    @Test func clearAllHidesTheWordsAndStopsTheClip() async throws {
        let r = try await rig()
        r.workspace.clearAll()
        #expect(r.workspace.show.isCleared && r.workspace.show.liveSlide == nil)
        #expect(r.media.layers.foreground == nil)
        #expect(r.workspace.show.liveIndex == 0)              // the place is kept, as with Clear
    }

    @Test func clearAllWithNothingLiveDoesNothingAndDoesNotFail() async throws {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        workspace.clearAll()
        #expect(workspace.show.isStopped && workspace.lastError == nil)
    }

    @Test func clearAllThenNextBringsTheWordsBack() async throws {
        let r = try await rig()
        r.workspace.clearAll()
        await r.workspace.next()                              // after Clear all, the next press brings the words back
        #expect(!r.workspace.show.isCleared)
    }

    // R17

    @Test func closingTheScreensStopsTheForegroundClip() async throws {
        let r = try await rig()
        r.media.screensClosed()
        #expect(r.media.layers.foreground == nil)
    }

    @Test func closingTheScreensKeepsTheBackgroundForWhenTheyOpenAgain() async throws {
        let r = try await rig()
        r.media.setBackground(r.clip.id)
        r.media.screensClosed()
        #expect(r.media.layers.background != nil)
    }
}

@Suite struct ClearAllCommandTests {
    @Test func clearAllMovesTheShowToTheClearedStateAndKeepsThePlace() {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "a"), SlideContent(primary: "b")])))
        state.apply(.trigger(index: 1))
        state.apply(.clearAll)
        #expect(state.isCleared && state.liveSlide == nil && state.liveIndex == 1)
        var viaClear = state
        viaClear.apply(.trigger(index: 1))
        viaClear.apply(.clear)
        #expect(viaClear == state)                            // for the show state, Clear all is Clear
    }

    @Test func clearAllWhenStoppedChangesNothing() {
        var state = ShowState()
        state.apply(.clearAll)
        #expect(state.isStopped)
    }
}
