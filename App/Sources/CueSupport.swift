// CUE-002b: small helpers the Cues mode and the Show mode's Cues tab share. Decisions live in OperatorCore; this only gathers what
// the pickers can choose from and gives each action kind its symbol.
import SwiftUI
import Domain
import CueEngine
import OperatorCore

extension AppModel {
    /// What a picker in the Cues mode can choose from, read from the models as they are now.
    func cueChoices() -> CueChoices {
        var c = CueChoices()
        c.looks = looks.map { CueChoice(id: $0.id, name: $0.name) }
        c.props = props.map { CueChoice(id: $0.id, name: $0.name) }
        c.timers = (stage?.timers ?? []).map { CueChoice(id: $0.id, name: $0.name) }
        let assets = media?.assets ?? []
        c.pictures = assets.filter { $0.kind != .audio }.map { CueChoice(id: $0.id, name: $0.name) }
        c.sounds = assets.filter { $0.kind == .audio }.map { CueChoice(id: $0.id, name: $0.name) }
        c.macros = (cue?.macros ?? []).map { CueChoice(id: $0.id, name: $0.name) }
        return c
    }
}

extension CueActionKind {
    var symbol: String {
        switch self {
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .goToSlide: "arrow.right.to.line"
        case .clear, .clearAll: "rectangle.slash"
        case .clearLiveBackground: "rectangle.slash"
        case .clearLiveForeground: "play.slash"
        case .clearMusic: "speaker.slash"
        case .blackout: "rectangle.fill"
        case .stop: "stop.fill"
        case .look: "square.stack.3d.up"
        case .prop: "photo"
        case .showMessage, .hideMessage: "text.bubble"
        case .startTimer, .pauseTimer, .resetTimer: "timer"
        case .setBackground, .clearBackground: "film"
        case .playClip, .stopClip: "play.rectangle"
        case .playSound, .stopSound: "speaker.wave.2"
        case .midiOut: "pianokeys"
        case .runMacro: "bolt"
        case .wait: "hourglass"
        }
    }
}

extension CueScreen {
    var color: Color {
        switch self { case .audience: Tok.roleAudience; case .stage: Tok.roleStage; case .broadcast: Tok.roleBroadcast }
    }
}

/// AUD / STG / BRD tags of a row.
struct ScreenTags: View {
    let screens: [CueScreen]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(screens, id: \.self) { PillTag(text: $0.tag, color: $0.color, height: 18) }
        }
    }
}

extension CommandSource {
    var activityColor: Color { self == .slideAction || self == .schedule ? Tok.cyan : Tok.muted }
}

/// One line of "Order is fixed and visible" style help.
struct CueNote: View {
    let text: String
    var systemImage = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(Tok.muted).accessibilityHidden(true)
            Text(text).font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)      // ui.css `.card`: padding 10 x 12 plus the border
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tok.border, lineWidth: 1))
    }
}
