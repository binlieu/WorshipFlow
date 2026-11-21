// UI-001: small shared pieces drawn from the design's component sheet (08-components): badges, role pills, key hints,
// section labels and the transport button style. Red is used only for "on screen now".
import SwiftUI
import Domain
import OperatorCore

// UI-004: one way to draw a rounded outline. The fill and the stroke come from the SAME shape (so the radii cannot differ) and the
// stroke is inset by half its width (`strokeBorder`), so nothing of it lies outside the view's frame. A plain `.stroke` is centred on
// the edge: half of it falls outside the frame and is cut off by whatever clips the view (a toolbar item, a scroll view, a
// parent frame), which flattened the ends of every pill and segmented control. Capsules are `.circular`: the default
// `.continuous` capsule stroked with a 1 pt line drew a short straight stub at each end on this macOS.
extension View {
    func wfOutline<S: InsettableShape>(_ shape: S, stroke: Color, fill: Color = .clear, lineWidth: CGFloat = 1) -> some View {
        background { shape.fill(fill) }
            .overlay { shape.strokeBorder(stroke, lineWidth: lineWidth) }
    }
}

/// A one-line outlined pill with a word in it (AUD, BRD, a media chip, the Preview-only chip): the shared pill for the app.
struct PillTag: View {
    let text: String
    let color: Color
    var height: CGFloat = 20
    var weight: Font.Weight = .semibold
    var size: CGFloat = 11
    var tracking: CGFloat = 0
    var maxWidth: CGFloat? = nil
    /// `.dot`: the design's status dot before the word (Running); `.symbol`: an icon (Signal lost).
    var lead: Lead = .none
    enum Lead { case none, dot, symbol(String) }

    var body: some View {
        HStack(spacing: 5) {
            switch lead {
            case .none: EmptyView()
            case .dot: Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            case .symbol(let name): Image(systemName: name).font(.system(size: 10)).accessibilityHidden(true)
            }
            Text(text).font(.system(size: size, weight: weight)).tracking(tracking).lineLimit(1).truncationMode(.tail)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).frame(height: height)
            .wfOutline(Capsule(style: .circular), stroke: Tok.borderStrong)
            .frame(maxWidth: maxWidth ?? .infinity)
            .fixedSize(horizontal: true, vertical: true)
    }
}

/// Uppercase tag: LIVE (red fill), PREVIEW (blue fill), SIMULATED (outlined in the broadcast colour), and so on.
struct Badge: View {
    enum Style { case live, preview, outline(Color), warning }
    let text: String
    let style: Style

    var body: some View {
        Text(text).font(.wfBadge).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(foreground)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: stroke, fill: background)
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .live: Tok.onLive
        case .preview: Tok.blue
        case .outline(let c): c
        case .warning: Tok.warning
        }
    }
    private var background: Color {
        switch style {
        case .live: Tok.liveFill
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
            Text(pill.abbreviation).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pill.status == .off ? Tok.muted : pill.role.tokenColor)
        }
        .padding(.horizontal, 8).frame(height: 20)
        .wfOutline(Capsule(style: .circular), stroke: Tok.borderStrong)
        .padding(1)   // room inside a toolbar item, which clips to its bounds
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
        // The design's `.kbd`: mono 10/14 medium, padding 0 4, radius 3, the border and the text in the label colour at 75 %.
        Text(key).font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 4).frame(height: 14)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.xs), stroke: (onFill ? Tok.onLive : Tok.text).opacity(0.75))
            .foregroundStyle((onFill ? Tok.onLive : Tok.text).opacity(0.75))
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
            .padding(.horizontal, 16)
            .frame(height: Space.transportHeight)
            .foregroundStyle(prominent ? Tok.onLive : Tok.text)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.lg),
                       stroke: prominent ? Tok.liveFill : (active ? Tok.warning : Tok.borderStrong),
                       fill: prominent ? Tok.liveFill : (active ? Tok.surface3 : Tok.surface2), lineWidth: active ? 2 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

/// A 26 pt control (the design's `.btn`): resting, `primary` (brand gradient, "Run"), or `ghost` (no fill or outline, "Configure…").
/// Disabled is 45 % opacity, as in the design (`.btn.off`).
struct HeaderButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, ghost }
    var selected = false
    var kind: Kind = .normal
    /// A 1.5 pt ring in the selection blue (the Look row's selected button, the Quick edit button while its tab is open).
    var ring: Color? = nil
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, compact ? 4 : 10).frame(height: Space.controlHeight)
            .foregroundStyle(kind == .primary ? Tok.onBrand : (kind == .ghost ? Tok.muted : Tok.text))
            .background {
                switch kind {
                case .primary: shape.fill(Tok.brandGradient)
                case .ghost: Color.clear
                case .normal: shape.fill(selected ? Tok.surface3 : Tok.surface2)
                }
            }
            .overlay { if kind == .normal { shape.strokeBorder(Tok.borderStrong, lineWidth: 1) } }
            .overlay { if let ring { shape.strokeBorder(ring, lineWidth: 1.5) } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(shape)
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
    var ring: Color? = nil
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
        .buttonStyle(HeaderButtonStyle(ring: ring))
        .help(control.tooltip)
        .accessibilityLabel(control.accessibilityLabel)
    }
}

/// Measures the width it is given and passes the decision "words or icons" to its content.
struct AdaptiveHeader<Content: View>: View {
    /// The width at which the labelled version fits (measured on the default layout).
    let labelledWidth: Double
    /// Show's header is the design's 42 pt (padding 8 around a 26 pt control); the other modes keep `Space.headerHeight`.
    var height: CGFloat = Space.headerHeight
    @ViewBuilder let content: (_ compact: Bool) -> Content

    var body: some View {
        GeometryReader { geo in
            content(!HeaderChrome.showsLabels(availableWidth: geo.size.width, labelledWidth: labelledWidth))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: height)
    }
}
