// UI-005d (the owner's request, 2026-11-21: "have all clear buttons as icon buttons on top menu of media bin next after audio"):
// five icon buttons, Clear lyric, Clear background, Clear foreground, Clear music and Clear all, for the header of the Show dock
// (after the Audio tab) and of the Media mode's bin. Each goes through the same command the Clear menu of the transport bar uses
// (`AppModel.clear`, `clearBackground`, `clearForeground`, `clearMusic`, `clearAll`: the one serial command path), has a tooltip with
// its name and key, a VoiceOver label, and looks disabled while there is nothing of its kind to clear. Never red.
import SwiftUI
import Domain
import OperatorCore

struct MediaClearButtons: View {
    let app: AppModel

    private enum Kind: CaseIterable {
        case lyric, background, foreground, music, all
        var action: ClearControl.Action {
            switch self {
            case .lyric: .clearWords
            case .background: .clearBackground
            case .foreground: .clearForeground
            case .music: .clearMusic
            case .all: .clearAll
            }
        }
        /// "Clear lyric" is the words-only Clear: the transport bar calls it plain "Clear".
        var name: String { self == .lyric ? "Clear lyric" : action.title }
        var symbol: String {
            switch self {
            case .lyric: "text.alignleft"
            case .background: "photo"
            case .foreground: "film"
            case .music: "music.note"
            case .all: "rectangle.slash"
            }
        }
        /// The four layer clears carry a small cross on their glyph; Clear all has its own glyph.
        var crossed: Bool { self != .all }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Kind.allCases, id: \.self) { kind in
                let enabled = canClear(kind)
                Button { perform(kind) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: kind.symbol).font(.wf(13)).frame(width: 16, height: 16)
                        if kind.crossed {
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
                .help("\(kind.name) (\(kind.action.shortcut))")
                .accessibilityLabel(kind.name)
                .accessibilityHint(enabled ? kind.action.detail : "Nothing to clear")
            }
        }
    }

    // MARK: What there is to clear

    private func canClear(_ kind: Kind) -> Bool {
        let show = app.workspace?.show
        let media = app.media
        switch kind {
        case .lyric: return show?.liveSlide != nil
        case .background: return media?.layers.background != nil || (show?.isStopped == false && show?.isBackgroundCleared == false)
        case .foreground: return media?.layers.foreground != nil
        case .music: return !(app.audio?.activeCues.isEmpty ?? true)
        case .all: return Kind.allCases.dropLast().contains { canClear($0) }
        }
    }

    private func perform(_ kind: Kind) {
        switch kind {
        case .lyric: app.clear()
        case .background: app.clearBackground()
        case .foreground: app.clearForeground()
        case .music: app.clearMusic()
        case .all: app.clearAll()
        }
    }
}
