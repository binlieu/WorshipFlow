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

/// FIX-G: what an import tells the workspace when it is done.
public struct ProgramImportOutcome: Sendable, Equatable {
    public var playlistID: UUID?
    public var replaced: [UUID]
    public init(playlistID: UUID?, replaced: [UUID]) { self.playlistID = playlistID; self.replaced = replaced }
}

extension WorkspaceModel {
    /// Presentations that are on air now (the live deck's), which an import must not replace.
    public var livePresentationIDs: Set<UUID> { show.liveDeck.map { [$0.presentationID] } ?? [] }

    /// Runs a program import around the workspace's own state (FIX-G item 3). Typing that is still waiting to be saved is written
    /// first, so the import (and the backup it makes) sees it and nothing is lost silently. When `perform` is done, drafts of the
    /// presentations it replaced are dropped, so a stale draft can never be written over what was imported, and the lists and the
    /// open presentation are reloaded from the library. If `perform` throws, nothing else happens.
    @discardableResult
    public func importingProgram(_ perform: () async throws -> ProgramImportOutcome) async throws -> ProgramImportOutcome {
        await flush()
        let outcome = try await perform()
        dropDrafts(ofPresentations: Set(outcome.replaced))
        await reloadAfterProgramImport(selecting: outcome.playlistID, replaced: outcome.replaced)
        return outcome
    }
}
