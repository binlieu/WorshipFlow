// CUE-002b (item 5): what a phone sees, built from the models. Plain values only; no show text is ever treated as markup.
import Foundation
import Domain
import CueEngine
import RemoteControl

@MainActor
public enum RemoteStateBuilder {
    public static func make(workspace: WorkspaceModel, stage: StageModel?, macros: [Macro]) -> RemoteState {
        let show = workspace.show
        var mode = RemoteMode.live
        if show.isStopped { mode = .stopped } else if show.isBlackedOut { mode = .blackedOut } else if show.isCleared { mode = .cleared }
        var state = RemoteState(mode: mode)
        if let deck = show.liveDeck, let i = show.liveIndex {
            state.live = text(deck.slides[i])
            if deck.slides.indices.contains(i + 1) { state.next = text(deck.slides[i + 1]) }
            state.position = RemoteState.positionText(index: i, count: deck.slides.count)
            state.presentationTitle = workspace.liveTitle
        }
        state.playlist = workspace.playlistItems.compactMap { item in
            if case .header = item.kind { return nil }
            return RemotePlaylistItem(title: item.title, isLive: !show.isStopped && item.id == workspace.liveItemID)
        }
        if let stage {
            state.timers = stage.timerRows(at: stage.nowSeconds).map { RemoteTimer(name: $0.name, value: $0.text, isRunning: $0.isRunning) }
        }
        state.macros = macros.map { RemoteMacro(id: $0.id, name: $0.name) }
        return state
    }

    private static func text(_ content: SlideContent) -> RemoteSlideText {
        RemoteSlideText(primary: content.primary, secondary: content.secondary)
    }
}
