// OUT-004 / OUT-002: Go Live, Next, Previous, Clear, Stop and the live status, along the bottom of the window.
import SwiftUI
import Domain
import OperatorCore

struct TransportBar: View {
    @Bindable var app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            stateBadge.wfRect("tp.badge", size: 11, weight: 700, radius: Radius.sm)
            VStack(alignment: .leading, spacing: 0) {
                Text(headline).font(.wf(13, .semibold)).lineLimit(1).truncationMode(.tail).wfLine().frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Tok.text).wfRect("tp.headline", size: 13, weight: 600)
                if let detail { Text(detail).font(.wfCaption).lineLimit(1).truncationMode(.tail).foregroundStyle(Tok.muted).wfLine().frame(maxWidth: .infinity, alignment: .leading).wfRect("tp.detail", size: 11, weight: 400) }
            }
            // The design's text block is as wide as its longer line, and the buttons are pushed to the right edge by a spacer.
            .frame(width: textBlockWidth, alignment: .leading)
            .wfRect("tp.text")
            .accessibilityElement(children: .combine)
            Spacer(minLength: 10)
            Button { app.previous() } label: { hinted("backward.fill", "Previous", TransportKeyHints.previous) }
                .buttonStyle(TransportButtonStyle()).wfRect("tp.previous", size: 13, weight: 600, radius: Radius.lg).help("Shift-Space: back one slide (the arrow keys only move the selection)")
            Button { app.goLive() } label: { hinted("play.fill", "Go Live", TransportKeyHints.goLive, onFill: true) }
                .buttonStyle(TransportButtonStyle(prominent: true)).wfRect("tp.golive", size: 13, weight: 600, radius: Radius.lg).help("Return: take the selected slide live, or send the selected media item live when the media bin has the arrow keys")
            Button { app.next() } label: { hinted("forward.fill", "Next", TransportKeyHints.next) }
                .buttonStyle(TransportButtonStyle()).wfRect("tp.next", size: 13, weight: 600, radius: Radius.lg).help("Space: on to the next slide")
            Rectangle().fill(Tok.border).frame(width: 1, height: 28).wfRect("tp.sep.0")
            clearControl
            Button { app.blackout() } label: { hinted("rectangle.fill", "Blackout", "B") }
                .buttonStyle(TransportButtonStyle(active: workspace.show.isBlackedOut)).wfRect("tp.blackout", size: 13, weight: 600, radius: Radius.lg)
                .disabled(workspace.show.isStopped)
                .help("B: every audience screen goes black and every broadcast screen transparent. Press again, or go to another slide, to bring the picture back.")
                .accessibilityValue(workspace.show.isBlackedOut ? "on" : "off")
            Button { app.stopShow() } label: { hinted("stop.fill", "Stop", nil) }
                .buttonStyle(TransportButtonStyle()).wfRect("tp.stop", size: 13, weight: 600, radius: Radius.lg)
                .disabled(workspace.show.isStopped).help("Empty every screen and drop the live slide")
            Rectangle().fill(Tok.border).frame(width: 1, height: 28).wfRect("tp.sep.1")
            health
        }
        .padding(.horizontal, Space.s5)
        .frame(height: Space.transportBarHeight)
        .background(Tok.surface)
        .wfRect("tp")
        .overlay(alignment: .top) { Rectangle().fill(Tok.border).frame(height: 1) }
        .overlay(alignment: .topTrailing) { if app.ui.showClearMenuPreview { clearMenuPreview } }
    }

    /// UI-005j: the width of the text block: the longer of its two lines as set in Inter, at most 440 pt (a longer headline is cut with an ellipsis).
    private var textBlockWidth: CGFloat {
        let widest = max(InterFont.textWidth(headline, size: 13, weight: 600), detail.map { InterFont.textWidth($0, size: 11, weight: 400) } ?? 0)
        return min(440, ceil(widest))
    }

    /// The Clear menu's entries, drawn (debug pictures only; see `showClearMenuPreview`).
    private var clearMenuPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([ClearControl.Action.clearAll] + ClearControl.layerMenu, id: \.title) { action in
                HStack { Text(action.title); Spacer(minLength: 16); Text(action.shortcut).foregroundStyle(Tok.muted) }
                    .font(.wf(13))
            }
        }
        .padding(10).frame(width: 250)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.surface2)
        .offset(x: -330, y: -128)
    }

    private func hinted(_ symbol: String, _ title: String, _ key: String?, onFill: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 15, height: 15)
            Text(title)
            if let key { KeyHint(key: key, onFill: onFill) }
        }
    }

    // MARK: Pieces

    /// The design's ONE button "Clear ⌄": it opens the menu whose first entry is the words-only clear (Escape).
    private var clearControl: some View {
        Menu {
            Button("\(ClearControl.primary.title) (Escape)") { app.clear() }.help(ClearControl.primary.detail)
            ForEach(ClearControl.menu, id: \.title) { action in
                Button("\(action.title) (Shift-Escape)") { app.clearAll() }.help(action.detail)
            }
            Divider()
            // MEDIA-010: one clear per layer. Each is reversible: Go Live, Next or a new choice brings content back.
            ForEach(ClearControl.layerMenu, id: \.title) { action in
                Button("\(action.title) (\(action.shortcut))") { performLayerClear(action) }.help(action.detail)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.slash").frame(width: 15, height: 15)
                Text("Clear")
                Image(systemName: "chevron.down").font(.wf(10, .bold)).frame(width: 12, height: 12)
            }
            .transportChrome()
            .wfRect("tp.clear", size: 13, weight: 600, radius: Radius.lg)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(workspace.show.isStopped)
        .opacity(workspace.show.isStopped ? 0.45 : 1)
        .help("Escape clears the words. The menu also has Clear all and one clear per layer.")
        .accessibilityLabel("Clear")
    }

    private func performLayerClear(_ action: ClearControl.Action) {
        switch action {
        case .clearBackground: app.clearBackground()
        case .clearForeground: app.clearForeground()
        case .clearMusic: app.clearMusic()
        case .clearWords: app.clear()
        case .clearAll: app.clearAll()
        }
    }

    @ViewBuilder private var stateBadge: some View {
        switch app.mode {
        case .live: Text("LIVE").font(.wf(11, .bold)).tracking(0.66).wfLine().foregroundStyle(Tok.onLive)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Tok.liveFill, in: RoundedRectangle(cornerRadius: Radius.sm))      // ui.css `.badge`: padding 3 x 8 plus the 1 pt border
            .accessibilityLabel("Show state: live")
        case .stopped: badge("STOPPED", Tok.muted)
        case .cleared: badge("CLEARED", Tok.warning)
        case .blackout: badge("BLACKOUT", Tok.warning)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.wf(11, .bold)).tracking(0.66).wfLine().foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: color)
            .accessibilityLabel("Show state: \(text.lowercased())")
    }

    private var headline: String {
        switch app.mode {
        case .stopped: return "Nothing is on the screens"
        case .cleared: return "Cleared: the screens are blank, your place is kept"
        case .blackout: return "Blackout: audience screens are black, your place is kept"
        case .live:
            // UI-005a: the lines of the first language joined with a comma, as the design draws it.
            guard let slide = workspace.show.liveSlide else { return "" }
            let text = slide.primary.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
            return text.isEmpty ? "(blank slide)" : text
        }
    }

    private var detail: String? { app.mode == .stopped ? nil : workspace.livePositionLine }

    private var screensButton: some View {
        Button { app.screensOn ? app.stopScreens() : app.startScreens() } label: {
            Image(systemName: app.screensOn ? "display.trianglebadge.exclamationmark" : "display")
        }
        .buttonStyle(HeaderButtonStyle())
        .help(app.screensOn ? "Close screens" : "Open screens")
        .accessibilityLabel(app.screensOn ? "Close screens" : "Open screens")
    }

    @ViewBuilder private var health: some View {
        if let h = app.outputHealth {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(h.needsAttention ? Tok.warning : Tok.cyan).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(h.rateText).foregroundStyle(h.needsAttention ? Tok.warning : Tok.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 14)
                    .wfRect("tp.health.rate", size: 11, weight: 400)
                    Text(h.countsText).foregroundStyle(Tok.muted).frame(maxWidth: .infinity, alignment: .leading).wfRect("tp.health.counts", size: 11, weight: 400)
                }
                .wfRect("tp.health")
                .font(.wfMono(11))
                if let audio = app.audio { MiniMeter(audio: audio) }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Output health: \(h.rateText), \(h.countsText)")
        } else {
            Text("screens closed").font(.wfMono(11)).foregroundStyle(Tok.muted).fixedSize()
        }
    }
}

struct SplitLeadingStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wf(13, .semibold)).padding(.horizontal, 16).frame(height: Space.transportHeight)
            .foregroundStyle(Tok.text).background(Tok.surface2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The look of a transport button, for controls that are not a plain Button (the Clear menu).
    func transportChrome() -> some View {
        self.font(.wf(13, .semibold)).foregroundStyle(Tok.text)
            .padding(.horizontal, 17).frame(height: Space.transportHeight)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.lg), stroke: Tok.borderStrong, fill: Tok.surface2)
    }
}

/// Two thin bars: the programme audio level (cyan, never red: red means on screen).
private struct MiniMeter: View {
    @Bindable var audio: AudioModel

    var body: some View {
        let levels = audio.levels
        HStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { channel in
                let rms = channel < levels.rms.count ? levels.rms[channel] : 0
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Tok.surface3)
                        // Cyan up to 70 %, then warning; never red (red means on air; ADR plan default A4).
                        Rectangle().fill(LinearGradient(stops: [.init(color: Tok.cyan, location: 0), .init(color: Tok.cyan, location: 0.7), .init(color: Tok.warning, location: 0.88), .init(color: Tok.warning, location: 1)], startPoint: .bottom, endPoint: .top))
                            .frame(height: geo.size.height * Self.position(rms))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .frame(width: 6, height: 34)
                .wfRect("tp.meter.\(channel)", radius: 2)
            }
        }
        .wfRect("tp.meters")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sound level")
    }

    private static func position(_ amplitude: Float) -> CGFloat {
        guard amplitude > 0.000_001 else { return 0 }
        return CGFloat(min(1, max(0, (20 * log10(Double(amplitude)) + 60) / 60)))
    }
}

/// The one action that changes what is on screen without going live again. It also saves the words.
struct QuickEditView: View {
    let workspace: WorkspaceModel
    let done: () -> Void
    @State private var primary = ""
    @State private var secondary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick edit live slide").font(.wfHeadline)
            Text("This changes what the audience sees now, and saves the new words.")
                .font(.wfSmall).foregroundStyle(.secondary)
            Text("First language").font(.wfSmall)
            editor($primary)
            Text("Second language").font(.wfSmall)
            editor($secondary)
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Apply to live") {
                    // Start from the live slide so its objects stay on screen; only the words change.
                    var content = workspace.show.liveSlide ?? SlideContent(primary: "")
                    content.primary = primary
                    content.secondary = secondary.isEmpty ? nil : secondary
                    Task { await workspace.quickEditLiveSlide(content); done() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).frame(width: 440)
        .onAppear {
            primary = workspace.show.liveSlide?.primary ?? ""
            secondary = workspace.show.liveSlide?.secondary ?? ""
        }
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text).font(.wfBody).frame(height: 76)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
    }
}
