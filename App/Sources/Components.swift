// UI-001: small shared pieces drawn from the design's component sheet (08-components): badges, role pills, key hints,
// section labels and the transport button style. Red is used only for "on screen now".
import SwiftUI
import Domain
import OperatorCore

extension View {
    /// UI-005j: the CSS line box. ui.css sets `line-height: 16px` on the body, so every text box of the design is 16 points tall whatever
    /// its font size (a 17 pt title is 22). SwiftUI's own text box is the font's height (about 1.21 em); this gives the design's.
    func wfLine(_ height: CGFloat = 16) -> some View { frame(height: height) }
}

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
    /// UI-005j: the dump's name for the pill.
    var rectID = ""
    enum Lead { case none, dot, symbol(String) }

    var body: some View {
        HStack(spacing: 5) {
            switch lead {
            case .none: EmptyView()
            case .dot: Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            case .symbol(let name): Image(systemName: name).font(.wf(10)).accessibilityHidden(true)
            }
            Text(text).font(.wf(size, weight)).tracking(tracking).lineLimit(1).truncationMode(.tail).wfLine()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).frame(height: height)
            .wfOutline(RoundedRectangle(cornerRadius: min(10, height / 2), style: .circular), stroke: Tok.borderStrong)      // ui.css `.pill`: radius 10
            .wfRect(rectID, size: Double(size), weight: weight == .bold ? 700 : 600, radius: Double(min(10, height / 2)))
            .frame(maxWidth: maxWidth ?? .infinity)
            .fixedSize(horizontal: true, vertical: true)
    }
}

/// Uppercase tag: LIVE (red fill), PREVIEW (blue fill), SIMULATED (outlined in the broadcast colour), and so on.
struct Badge: View {
    enum Style { case live, preview, outline(Color), warning }
    let text: String
    let style: Style
    var rectID = ""

    var body: some View {
        Text(text).font(.wfBadge).tracking(0.6).wfLine()
            .padding(.horizontal, 7).padding(.vertical, 2)      // ui.css `.badge`: padding 1 x 6 plus the 1 pt border
            .foregroundStyle(foreground)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: stroke, fill: background)
            .wfRect(rectID, size: 10, weight: 700, radius: Radius.sm)
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
    var rectID = ""

    var body: some View {
        HStack(spacing: 5) {
            switch pill.status {
            case .on: Circle().fill(pill.role.tokenColor).frame(width: 7, height: 7)
            case .off: Circle().stroke(Tok.muted, lineWidth: 1).frame(width: 7, height: 7)
            case .fault: Image(systemName: "exclamationmark.triangle.fill").font(.wf(9)).foregroundStyle(Tok.warning)
            }
            Text(pill.abbreviation).font(.wf(11, .semibold))
                .foregroundStyle(pill.status == .off ? Tok.muted : pill.role.tokenColor)
        }
        .padding(.horizontal, 9).frame(height: 20)
        .wfOutline(Capsule(style: .circular), stroke: Tok.borderStrong)
        .wfRect(rectID, size: 11, weight: 600, radius: 10)
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
    var rectID = ""
    var body: some View {
        // The design's `.kbd`: mono 10/14 medium, padding 0 4, radius 3, the border and the text in the label colour at 75 %.
        Text(key).font(.wfMono(10, .medium)).fixedSize()
            .frame(width: key.count == 1 ? 6.1 : nil)      // one mono cell for a single key, so an arrow drawn in a fallback face is as wide as a letter
            .padding(.horizontal, 5).frame(height: 16)      // ui.css `.kbd`: 14 pt line, padding 0 4, 1 pt border
            .wfOutline(RoundedRectangle(cornerRadius: Radius.xs), stroke: (onFill ? Tok.onLive : Tok.text).opacity(0.75))
            .wfRect(rectID, size: 10, weight: 500, radius: Radius.xs)
            .foregroundStyle((onFill ? Tok.onLive : Tok.text).opacity(0.75))
            .accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    var rectID = ""
    init(_ text: String, rectID: String = "") { self.text = text; self.rectID = rectID }
    var body: some View {
        Text(text.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(Tok.muted).wfLine()
            .wfRect(rectID, size: 11, weight: 600)
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
            .font(.wf(13, .semibold))
            .padding(.horizontal, 17)      // ui.css `.btn.lg`: padding 0 16 plus the 1 pt border
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
            .font(.wf(12, .medium))
            .padding(.horizontal, compact ? 4 : 11).frame(height: Space.controlHeight)      // ui.css `.btn`: padding 0 10 plus the 1 pt border
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
            .wfFocusReport(.button)        // FIX-H item 7: a focused button keeps Space and Return
    }
}

extension SectionTone {
    var color: Color {
        switch self {
        case .verse: Tok.sectionVerse
        case .chorus: Tok.sectionChorus
        case .bridge, .ending: Tok.sectionBridge
        case .other: Tok.broadcast      // the design's `--tag` colour (UI-005b)
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
    var rectID = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 15, height: 15)
                if !compact {
                    Text(control.title)
                    if let hint = control.keyHint { KeyHint(key: hint, rectID: rectID.isEmpty ? "" : "\(rectID).kbd") }
                }
            }
        }
        .buttonStyle(HeaderButtonStyle(ring: ring))
        .wfRect(rectID, size: 12, weight: 500, radius: Radius.md)
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
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height)
    }
}
