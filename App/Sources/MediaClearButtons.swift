// UI-005d (the owner's request, 2026-11-21: "have all clear buttons as icon buttons on top menu of media bin next after audio"):
// five icon buttons, Clear lyric, Clear background, Clear foreground, Clear music and Clear all, for the header of the Show dock
// (after the Audio tab) and of the Media mode's bin. Each goes through the same command the Clear menu of the transport bar uses
// (`AppModel.clear`, `clearBackground`, `clearForeground`, `clearMusic`, `clearAll`: the one serial command path), has a tooltip with
// its name and key, a VoiceOver label, and looks disabled while there is nothing of its kind to clear. Never red.
// FIX-K item 1: what lights, the glyph (a film for a video, a photo for a picture, the plain layer glyph when empty) and the tooltip come from the pure
// `ClearIconState` (OperatorCore); the view only draws it.
import SwiftUI
import Domain
import OperatorCore

struct MediaClearButtons: View {
    let app: AppModel

    private func symbol(_ glyph: ClearGlyph) -> String {
        switch glyph {
        case .words: "text.alignleft"
        case .film: "film"
        case .photo: "photo"
        case .backgroundLayer: "square.stack"
        case .foregroundLayer: "rectangle.on.rectangle"
        case .music: "music.note"
        case .all: "rectangle.slash"
        }
    }

    /// What is live now, for the icons: the words, what plays on each layer (a bin choice, else the live slide's own background) and the sound cues.
    private var live: ClearLiveState {
        let show = app.workspace?.show
        let media = app.media
        func name(_ id: UUID?) -> String? { id.flatMap { media?.asset($0)?.name } }
        var background = media?.layers.background?.selection
        if background == nil, show?.isStopped == false, show?.isBackgroundCleared == false { background = show?.liveSlideAtPlace?.background }
        let foreground = media?.layers.foreground?.selection
        let cue = app.audio?.activeCues.last
        return ClearLiveState(hasLiveWords: show?.liveSlide != nil && show?.isCleared == false && show?.isBlackedOut == false,
                              backgroundKind: background?.kind, backgroundName: name(background?.assetID),
                              foregroundKind: foreground?.kind, foregroundName: name(foreground?.assetID),
                              musicName: cue.flatMap { name($0.assetID) }, hasMusic: !(app.audio?.activeCues.isEmpty ?? true))
    }

    var body: some View {
        let live = live
        HStack(spacing: 0) {
            ForEach(ClearIcon.allCases, id: \.self) { icon in
                let state = ClearIconState.state(for: icon, live: live)
                let enabled = state.enabled
                Button { perform(icon) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: symbol(state.glyph)).font(.wf(13)).frame(width: 16, height: 16)
                        if icon != .all {       // the small cross says it is an action (clear), not the thing itself
                            Image(systemName: "xmark").font(.wf(6, .heavy)).foregroundStyle(Tok.surface)
                                .frame(width: 8, height: 8).background(enabled ? Tok.text : Tok.muted, in: Circle()).offset(x: 3, y: 2)
                        }
                    }
                    .frame(width: 20, height: 22)
                    .foregroundStyle(enabled ? Tok.text : Tok.muted.opacity(0.45))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(state.tooltip)
                .accessibilityLabel(state.tooltip)
                .accessibilityHint(enabled ? "" : "Nothing to clear")
            }
        }
    }

    private func perform(_ icon: ClearIcon) {
        switch icon {
        case .lyric: app.clear()
        case .background: app.clearBackground()
        case .foreground: app.clearForeground()
        case .music: app.clearMusic()
        case .all: app.clearAll()
        }
    }
}
