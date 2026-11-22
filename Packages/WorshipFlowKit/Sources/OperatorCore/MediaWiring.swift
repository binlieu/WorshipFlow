// The two hooks between the workspace and the media layers, in one place so the app and its tests wire them the same way.
import Foundation

public enum MediaWiring {
    /// R8: Clear all also stops the clip. FIX-I item 4: it also drops the background chosen from the bin. A new background choice brings a
    /// hidden background back.
    @MainActor public static func connect(workspace: WorkspaceModel, media: MediaModel) {
        workspace.onClearAll = { [weak media] in media?.stopForeground(); media?.dropBackgroundOverride() }
        media.onBackgroundChosen = { [weak workspace] in workspace?.showBackground() }
    }
}
