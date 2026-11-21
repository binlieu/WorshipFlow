// UI-005a: the design's custom controls, built once from docs/UI/mockups/ui.css and used app-wide where they replace the same
// control. Every one keeps what the system control it replaces gives: a label for VoiceOver, its value, and keyboard operation
// (Tab to reach it with full keyboard access, Space or Return to act, arrows for sliders).
import SwiftUI

// MARK: Segmented control (`.seg`)

/// The design's segmented control: a `surface-2` track with a 1 pt `border`, radius 7, padding 2; the selected segment is
/// `surface-3` with a 1 pt `border-strong` ring, its text stays `text`. A segment is a word, an icon, or both.
struct WFSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        var title: String? = nil
        var symbol: String? = nil
        var label: String
        var id: String { label }
    }
    let items: [Item]
    @Binding var selection: Value
    var accessibilityName = ""

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item.value == selection
                Button { selection = item.value } label: {
                    HStack(spacing: 5) {
                        if let symbol = item.symbol { Image(systemName: symbol).font(.system(size: item.title == nil ? 12 : 11)) }
                        if let title = item.title { Text(title).font(.system(size: 12, weight: .medium)) }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .frame(minHeight: 24)
                    .foregroundStyle(on ? Tok.text : Tok.muted)
                    .background { if on { RoundedRectangle(cornerRadius: Radius.segment).fill(Tok.surface3) } }
                    .overlay { if on { RoundedRectangle(cornerRadius: Radius.segment).strokeBorder(Tok.borderStrong, lineWidth: 1) } }
                    .contentShape(RoundedRectangle(cornerRadius: Radius.segment))
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.track), stroke: Tok.border, fill: Tok.surface2)
        .padding(1)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: Toggle and checkbox (`.tgl`, `.chk`)

/// 30 x 18 pill: on = `cyan`, off = `border-strong`, a 14 pt white knob. Still a `Toggle` for VoiceOver and the keyboard.
struct WFToggleStyle: ToggleStyle {
    /// False for a toggle with no visible label (`.labelsHidden()` is not passed on to a custom style).
    var showsLabel = true
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Tok.cyan : Tok.borderStrong)
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                }
                .frame(width: Metric.toggleWidth, height: Metric.toggleHeight)
                if showsLabel { configuration.label }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// 14 x 14, radius 3, 1 pt `border-strong`; checked = `blue` fill with the check in `on-brand` (white in light).
struct WFCheckboxStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(configuration.isOn ? Tok.blue : .clear)
                    RoundedRectangle(cornerRadius: 3).strokeBorder(configuration.isOn ? Tok.blue : Tok.borderStrong, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(scheme == .light ? Color.white : Tok.onBrand)
                    }
                }
                .frame(width: 14, height: 14)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == WFToggleStyle {
    static var wf: WFToggleStyle { WFToggleStyle() }
    static var wfBare: WFToggleStyle { WFToggleStyle(showsLabel: false) }
}
extension ToggleStyle where Self == WFCheckboxStyle { static var wfCheckbox: WFCheckboxStyle { WFCheckboxStyle() } }

// MARK: Slider (`.scrub`)

/// A 5 pt track (`surface-3`), a fill (cyan, or blue for volume), a 13 pt white thumb with a 1 pt `border-strong` ring.
/// Dragging and VoiceOver adjustment change `value`; `onEditingChanged` is called like the system slider's.
struct WFSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var fill: Color = Tok.cyan
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = CGFloat((value - range.lowerBound) / span).clamped01
            ZStack(alignment: .leading) {
                Capsule().fill(Tok.surface3).frame(height: 5)
                Capsule().fill(fill).frame(width: width * fraction, height: 5)
                Circle().fill(.white).frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(Tok.borderStrong, lineWidth: 1))
                    .offset(x: width * fraction - 6.5)
            }
            .frame(height: geo.size.height)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = range.lowerBound + Double((drag.location.x / width).clamped01) * span
                }
                .onEnded { _ in dragging = false; onEditingChanged(false) }, including: isEnabled ? .all : .none)
        }
        .frame(height: 13)
        .accessibilityRepresentation { Slider(value: $value, in: range, onEditingChanged: onEditingChanged) }
    }
}

extension CGFloat { var clamped01: CGFloat { Swift.min(Swift.max(self, 0), 1) } }

// MARK: Field and pop-up (`.field`)

/// The design's field chrome: 26 pt, radius 6, `bg` fill, 1 pt `border-strong`, padding 0 8, 12 pt text.
struct WFFieldChrome: ViewModifier {
    var height: CGFloat = Space.controlHeight
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12))
            .padding(.horizontal, 8).frame(height: height)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.bg)
    }
}
extension View { func wfField(height: CGFloat = Space.controlHeight) -> some View { modifier(WFFieldChrome(height: height)) } }

/// A dropdown that looks like a design field with its chevron at the right. Still a system `Menu` (keyboard and VoiceOver unchanged).
struct WFPopup<Content: View>: View {
    let title: String
    var accessibilityName: String = ""
    var height: CGFloat = Space.controlHeight
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu { content() } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tok.muted)
            }
            .foregroundStyle(Tok.text)
            .wfField(height: height)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel(accessibilityName.isEmpty ? title : accessibilityName)
        .accessibilityValue(title)
    }
}

/// A text field in the design's look (`bg` fill, strong outline); an optional icon and trailing view (the ⌘F key hint).
struct WFTextField<Trailing: View>: View {
    let prompt: String
    @Binding var text: String
    var symbol: String? = nil
    var height: CGFloat = Space.controlHeight
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Tok.muted).accessibilityHidden(true) }
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Tok.muted)).textFieldStyle(.plain)
            trailing()
        }
        .wfField(height: height)
    }
}
extension WFTextField where Trailing == EmptyView {
    init(prompt: String, text: Binding<String>, symbol: String? = nil, height: CGFloat = Space.controlHeight) {
        self.init(prompt: prompt, text: text, symbol: symbol, height: height) { EmptyView() }
    }
}

// MARK: Tabs (`.tabs`)

/// Tabs with the 2 pt selection-blue underline: 12/500, padding 7 x 9, a 1 pt `border` line under the strip.
struct WFTabs<Value: Hashable>: View {
    struct Tab: Identifiable {
        let value: Value
        var title: String
        var symbol: String? = nil
        var dot: Bool = false
        var id: String { title }
    }
    let tabs: [Tab]
    @Binding var selection: Value
    var inset: CGFloat = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                WFTabButton(title: tab.title, symbol: tab.symbol, dot: tab.dot, on: tab.value == selection) { selection = tab.value }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
    }
}

/// One tab: 12/500, padding 7 x 9, the selected one in `text` with the 2 pt selection-blue underline sitting on the strip's line.
struct WFTabButton: View {
    let title: String
    var symbol: String? = nil
    var dot = false
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
                Text(title).font(.system(size: 12, weight: .medium)).fixedSize()
                if dot { Circle().fill(Tok.blue).frame(width: 6, height: 6).accessibilityHidden(true) }
            }
            .foregroundStyle(on ? Tok.text : Tok.muted)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .overlay(alignment: .bottom) { if on { Rectangle().fill(Tok.blue).frame(height: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Thumbnail rings and tags (`.thumb`)

extension View {
    /// The design's thumbnail outline: idle = 1 pt `border`; preview = 2 pt `sel` blue; live = 3 pt `live-fill` (or the warning
    /// colour while cleared); the ring sits OUTSIDE the picture at a 2 pt offset and follows the picture's radius, so it never covers words.
    func wfThumbState(radius: CGFloat = 4, preview: Bool = false, live: Bool = false, liveColor: Color = Tok.liveFill) -> some View {
        overlay {
            if live {
                RoundedRectangle(cornerRadius: radius + 5, style: .continuous).strokeBorder(liveColor, lineWidth: 3).padding(-5)
            } else if preview {
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous).strokeBorder(Tok.blue, lineWidth: 2).padding(-4)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Tok.border, lineWidth: 1).padding(-1)
            }
        }
    }
}

/// The LIVE / PREVIEW tag on a thumbnail: 9/800, tracking .08em, padding 1 x 5, radius 3.
struct ThumbTag: View {
    enum Kind { case live, preview, warning }
    let text: String
    let kind: Kind
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).font(.system(size: 9, weight: .heavy)).tracking(0.72)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(kind == .live ? Tok.onLive : (kind == .preview ? (scheme == .light ? Color.white : Tok.onBrand) : Tok.onBrand))
            .background(RoundedRectangle(cornerRadius: Radius.xs).fill(kind == .live ? Tok.liveFill : (kind == .preview ? Tok.blue : Tok.warning)))
            .fixedSize()
    }
}

// MARK: Message card (`.err`)

/// The design's message: padding 8 x 12, radius 8, 1 pt warning border, `surface-2` fill, a 15 pt icon; the first sentence is bold.
struct MessageCard<Trailing: View>: View {
    let message: String
    @ViewBuilder var trailing: () -> Trailing

    private var parts: (String, String) {
        if let r = message.range(of: ". ") { return (String(message[..<r.upperBound]).trimmingCharacters(in: .whitespaces), String(message[r.upperBound...])) }
        return (message, "")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 15)).foregroundStyle(Tok.text).accessibilityHidden(true)
            (Text(parts.0).fontWeight(.semibold) + Text(parts.1.isEmpty ? "" : " " + parts.1))
                .font(.system(size: 13)).foregroundStyle(Tok.text)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.lg), stroke: Tok.warning, fill: Tok.surface2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
extension MessageCard where Trailing == EmptyView {
    init(message: String) { self.init(message: message) { EmptyView() } }
}
