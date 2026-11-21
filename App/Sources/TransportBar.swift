// OUT-004 / OUT-002: Go Live, Next, Previous, Clear, Stop and the live status, along the bottom of the window.
import SwiftUI
import Domain
import OperatorCore

struct TransportBar: View {
    @Bindable var app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            stateBadge
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(Tok.text)
                if let detail { Text(detail).font(.wfCaption).lineLimit(1).truncationMode(.tail).foregroundStyle(Tok.muted) }
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { app.previous() } label: { hinted("backward.fill", "Previous", "←") }
                .buttonStyle(TransportButtonStyle()).help("Left arrow")
            Button { app.goLive() } label: { hinted("play.fill", "Go Live", "↩", onFill: true) }
                .buttonStyle(TransportButtonStyle(prominent: true)).help("Return: take the selected slide live")
            Button { app.next() } label: { hinted("forward.fill", "Next", "→") }
                .buttonStyle(TransportButtonStyle()).help("Right arrow or Space")
            Divider().frame(height: 26)
            clearControl
            Button { app.blackout() } label: { hinted("rectangle.fill", "Blackout", "B") }
                .buttonStyle(TransportButtonStyle(active: workspace.show.isBlackedOut))
                .disabled(workspace.show.isStopped)
                .help("B: every audience screen goes black and every broadcast screen transparent. Press again, or go to another slide, to bring the picture back.")
                .accessibilityValue(workspace.show.isBlackedOut ? "on" : "off")
            Button { app.stopShow() } label: { hinted("stop.fill", "Stop", nil) }
                .buttonStyle(TransportButtonStyle())
                .disabled(workspace.show.isStopped).help("Empty every screen and drop the live slide")
            health
        }
        .padding(.horizontal, Space.s5)
        .frame(height: Space.transportBarHeight)
        .background(Tok.surface)
        .overlay(alignment: .top) { Rectangle().fill(Tok.border).frame(height: 1) }
        .overlay(alignment: .topTrailing) { if app.ui.showClearMenuPreview { clearMenuPreview } }
    }

    /// The Clear menu's entries, drawn (debug pictures only; see `showClearMenuPreview`).
    private var clearMenuPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([ClearControl.Action.clearAll] + ClearControl.layerMenu, id: \.title) { action in
                HStack { Text(action.title); Spacer(minLength: 16); Text(action.shortcut).foregroundStyle(Tok.muted) }
                    .font(.system(size: 13))
            }
        }
        .padding(10).frame(width: 250)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.surface2)
        .offset(x: -330, y: -128)
    }

    private func hinted(_ symbol: String, _ title: String, _ key: String?, onFill: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
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
                Image(systemName: "rectangle.slash")
                Text("Clear")
                KeyHint(key: "esc")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .transportChrome()
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
        case .live: Text("LIVE").font(.system(size: 11, weight: .bold)).tracking(0.66).foregroundStyle(Tok.onLive)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Tok.liveFill, in: RoundedRectangle(cornerRadius: Radius.sm))
            .accessibilityLabel("Show state: live")
        case .stopped: badge("STOPPED", Tok.muted)
        case .cleared: badge("CLEARED", Tok.warning)
        case .blackout: badge("BLACKOUT", Tok.warning)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(0.66).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Circle().fill(h.needsAttention ? Tok.warning : Tok.cyan).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(h.rateText).foregroundStyle(h.needsAttention ? Tok.warning : Tok.text)
                    }
                    Text(h.countsText).foregroundStyle(Tok.muted)
                }
                .font(.system(size: 11, design: .monospaced))
                if let audio = app.audio { MiniMeter(audio: audio) }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Output health: \(h.rateText), \(h.countsText)")
        } else {
            Text("screens closed").font(.system(size: 11, design: .monospaced)).foregroundStyle(Tok.muted).fixedSize()
        }
    }
}

struct SplitLeadingStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).frame(height: Space.transportHeight)
            .foregroundStyle(Tok.text).background(Tok.surface2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The look of a transport button, for controls that are not a plain Button (the Clear menu).
    func transportChrome() -> some View {
        self.font(.system(size: 13, weight: .semibold)).foregroundStyle(Tok.text)
            .padding(.horizontal, 16).frame(height: Space.transportHeight)
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
            }
        }
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
            Text("Quick edit live slide").font(.headline)
            Text("This changes what the audience sees now, and saves the new words.")
                .font(.caption).foregroundStyle(.secondary)
            Text("First language").font(.caption)
            editor($primary)
            Text("Second language").font(.caption)
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
        TextEditor(text: text).font(.body).frame(height: 76)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
    }
}
