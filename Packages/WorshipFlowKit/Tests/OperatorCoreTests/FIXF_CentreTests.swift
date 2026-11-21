// FIX-F item 1 (LIB-004c): the centre pane shows the passage whenever the workspace has one open, however it was opened.
// Written before the fix. All text is invented.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_CentreTests {
    @Test func nextFromTheLastSongSlideIntoAPassageShowsThePassageInTheCentre() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(song.id)
        await r.scripture.show("Psalm 23:1-2")
        await r.scripture.addToPlaylist()
        let ids = r.workspace.playlistItems.map(\.id)           // [song, passage]
        await r.workspace.openPlaylistItem(ids[0])
        #expect(r.workspace.centreShowsScripture == false)
        await r.workspace.goLive(at: 1)
        await r.workspace.next()
        #expect(r.workspace.liveItemID == ids[1])
        #expect(r.workspace.centreShowsScripture, "the passage is live and open, so the centre must show it")
        // And back into the song: the centre shows the song again.
        await r.workspace.previous()
        #expect(r.workspace.liveItemID == ids[0])
        #expect(r.workspace.centreShowsScripture == false)
    }

    @Test func aPassageItemRestoredAtLaunchIsWhatTheCentreShows() async throws {
        let url = L4C.temp()
        let itemID: UUID
        do {
            let r = try await L4C.rig(store: try LibraryStore.open(at: url))
            await r.scripture.show("John 3:16-17")
            await r.scripture.addToPlaylist()
            itemID = try #require(r.workspace.playlistItems.last).id
            await r.workspace.openPlaylistItem(itemID)
            await r.workspace.flush()
        }
        // The app joins the two models before the workspace loads, so the stored place can open the passage.
        let store = try LibraryStore.open(at: url)
        let workspace = WorkspaceModel(store: store, clock: ManualSaveClock())
        let scripture = ScriptureModel(store: ScriptureStore(library: store), stateStore: store)
        scripture.connect(workspace)
        await scripture.load()
        await workspace.load()
        #expect(workspace.selectedPlaylistItemID == itemID)
        #expect(workspace.openScripture != nil, "the stored place opened the passage")
        #expect(workspace.centreShowsScripture, "restored passage: the centre must show it")
    }

    @Test func noPassageOpenMeansTheCentreShowsThePresentation() async throws {
        let r = try await L4C.rig()
        #expect(r.workspace.centreShowsScripture == false)
        await r.scripture.show("John 3:16")
        #expect(r.workspace.centreShowsScripture)
        r.workspace.closeScripture()
        #expect(r.workspace.centreShowsScripture == false)
    }
}
