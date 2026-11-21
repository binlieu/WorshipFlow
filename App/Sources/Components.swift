// UI-001: small shared pieces drawn from the design's component sheet (08-components): badges, role pills, key hints,
// section labels and the transport button style. Red is used only for "on screen now".
import SwiftUI
import Domain
import OperatorCore

/// Uppercase tag: LIVE (red fill), PREVIEW (blue fill), SIMULATED (outlined in the broadcast colour), and so on.
struct Badge: View {
    enum Style { case live, preview, outline(Color), warning }
    let text: String
    let style: Style

    var body: some View {
        Text(text).font(.wfBadge).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.xs))
            .overlay(RoundedRectangle(cornerRadius: Radius.xs).stroke(stroke, lineWidth: 1))
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .live: Tok.onLive
        case .preview: Tok.bg
        case .outline(let c): c
        case .warning: Tok.warning
        }
    }
    private var background: Color {
        switch style {
        case .live: Tok.liveFill
        case .preview: Tok.blue
        default: .clear
        }
    }
    private var stroke: Color {
        switch style {
        case .live: Tok.liveFill
        case .preview: Tok.blue
        case .outline(let c): c
        case .warning: Tok.warning
        }
    }
}

extension ScreenRole {
    var tokenColor: Color {
        switch self { case .audience: Tok.roleAudience; case .stage: Tok.roleStage; case .broadcast: Tok.roleBroadcast }
    }
}

/// A role tag with its word, for screen cards.
struct RoleChip: View {
    let role: ScreenRole
    var body: some View {
        Badge(text: role.rawValue.uppercased(), style: .outline(role.tokenColor))
    }
}

/// The toolbar's AUD / STG / BRD pill: a dot, the abbreviation and, for fault, an icon. Never colour alone: the state is
/// also read out to VoiceOver as words.
struct RolePillView: View {
    let pill: RolePill

    var body: some View {
        HStack(spacing: 5) {
            switch pill.status {
            case .on: Circle().fill(pill.role.tokenColor).frame(width: 7, height: 7)
            case .off: Circle().stroke(Tok.muted, lineWidth: 1).frame(width: 7, height: 7)
            case .fault: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Tok.warning)
            }
            Text(pill.abbreviation).font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(pill.status == .off ? Tok.muted : pill.role.tokenColor)
        }
        .padding(.horizontal, 9).frame(height: 20)
        .overlay(Capsule().stroke(pill.status == .off ? Tok.borderStrong : pill.role.tokenColor, lineWidth: 1))
        .fixedSize()
        .help("\(pill.accessibilityText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.accessibilityText)
    }
}

/// A key hint on a button: the key in a small outlined box.
struct KeyHint: View {
    let key: String
    var onFill = false
    var body: some View {
        Text(key).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: Radius.xs).stroke(onFill ? Tok.onLive.opacity(0.7) : Tok.borderStrong, lineWidth: 1))
            .foregroundStyle(onFill ? Tok.onLive : Tok.muted)
            .accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(Tok.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 36 pt transport button: resting `surface-2` with a strong outline, or the one filled red Go Live.
struct TransportButtonStyle: ButtonStyle {
    var prominent = false
    var active = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: Space.transportHeight)
            .foregroundStyle(prominent ? Tok.onLive : Tok.text)
            .background(prominent ? Tok.liveFill : (active ? Tok.surface3 : Tok.surface2),
                        in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(prominent ? Tok.liveFill : (active ? Tok.warning : Tok.borderStrong), lineWidth: active ? 2 : 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

/// A 26 pt resting control for headers.
struct HeaderButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).frame(height: Space.controlHeight)
            .foregroundStyle(Tok.text)
            .background(selected ? Tok.surface3 : Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension SectionTone {
    var color: Color {
        switch self {
        case .verse: Tok.sectionVerse
        case .chorus: Tok.sectionChorus
        case .bridge, .ending: Tok.sectionBridge
        case .other: Tok.muted
        }
    }
}

/// A header button from `HeaderChrome.Control`: icon and words, or the icon alone when the header is narrow. Tooltip and
/// accessibility label are the same either way.
struct HeaderControlButton: View {
    let control: HeaderChrome.Control
    let symbol: String
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                if !compact {
                    Text(control.title)
                    if let hint = control.keyHint { KeyHint(key: hint) }
                }
            }
        }
        .buttonStyle(HeaderButtonStyle())
        .help(control.tooltip)
        .accessibilityLabel(control.accessibilityLabel)
    }
}

/// Measures the width it is given and passes the decision "words or icons" to its content.
struct AdaptiveHeader<Content: View>: View {
    /// The width at which the labelled version fits (measured on the default layout).
    let labelledWidth: Double
    @ViewBuilder let content: (_ compact: Bool) -> Content

    var body: some View {
        GeometryReader { geo in
            content(!HeaderChrome.showsLabels(availableWidth: geo.size.width, labelledWidth: labelledWidth))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: Space.headerHeight)
    }
}
