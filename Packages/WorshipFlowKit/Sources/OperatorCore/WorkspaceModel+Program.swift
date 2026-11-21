// LIB-005: after a program import has written to the library behind the workspace's back, bring the lists up to date.
import Foundation
import Domain

extension WorkspaceModel {
    /// Re-reads the libraries, presentations and playlists, selects the playlist the import made or kept, and reloads the open
    /// presentation if the import replaced it. The live show is not touched: Live keeps the slides it has.
    public func reloadAfterProgramImport(selecting playlistID: UUID?, replaced: [UUID]) async {
        await reloadLibraries()
        await reloadPlaylists()
        await reloadPresentations()
        if let playlistID, playlists.contains(where: { $0.id == playlistID }) {
            await selectPlaylist(playlistID)
        } else {
            await reloadPlaylistItems()
        }
        if let open = openPresentationID, replaced.contains(open) { await openPresentation(open) }
    }
}
