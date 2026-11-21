// CUE-002b (item 2): slide actions. The workspace tells the model when a slide goes live; the model keeps the actions in step
// with the library, and a re-flow reloads them because the slides' ids change.
import Foundation
import CueEngine
import CueStore
import Persistence

extension CueModel {
    /// Hangs the model on a workspace: slide actions fire when a slide goes live, and a re-flow reloads them.
    public func connect(_ workspace: WorkspaceModel) {
        workspace.onSlideWentLive = { [weak self] event in self?.slideWentLive(event) }
        workspace.onContentReplaced = { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.reload() }
        }
    }

    /// Stores the actions for a slide (an empty list removes them). A transport command, or a macro that contains one, is
    /// refused with the engine's own words; nothing is written then. Sets `lastError` and throws.
    public func setSlideActions(_ actions: [CueAction], for slideID: UUID) async throws {
        do {
            try await store.setSlideActions(actions, for: slideID)
            lastError = nil
            await reload()
        } catch {
            lastError = Self.message(for: error)
            throw error
        }
    }
}
