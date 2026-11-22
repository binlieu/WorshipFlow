// UI-005c: the small pieces of the Edit mode that the shared controls do not cover: a segmented control that can fill its row or take
// the design's `padding: 4px 6px` segments, the inspector's row, section and field, and a text field that commits on Return or when it
// loses focus. Built from docs/UI/mockups/02-editor.html and ui.css; wanted in the shared files: `EditSegmented` as a `WFSegmented` option.
import SwiftUI
import OperatorCore

// MARK: Segmented control, wide or narrow

/// `.seg` with the options the Edit mockup uses: segments that share the row (`flex: 1`, the Object / Slide / Theme tabs) or
/// segments with their own side padding (Top / Mid / Bot are 6, icon segments 11). Same look as `WFSegmented`.
struct EditSegmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        var title: String? = nil
        var symbol: String? = nil
        var label: String
    }
    let items: [Item]
    @Binding var selection: Value
    var accessibilityName = ""
    var rectID = ""
    /// Segments share the width (`flex: 1`); the control then fills the row.
    var fill = false
    /// Side padding of a segment with words (the design's default is 11; Top / Mid / Bot use 6).
    var sidePadding: CGFloat = 11
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let on = item.value == selection
                Button { selection = item.value } label: {
                    HStack(spacing: 5) {
                        if let symbol = item.symbol { Image(systemName: symbol).font(.wf(12)).frame(width: 12, height: 12) }
                        if let title = item.title { Text(title).font(.wf(12, .medium)).wfLine() }
                    }
                    .padding(.horizontal, item.title == nil ? 11 : sidePadding).padding(.vertical, 4)
                    .frame(maxWidth: fill ? .infinity : nil, minHeight: item.title == nil ? 20 : 24)
                    .foregroundStyle(on ? Tok.text : Tok.muted)
                    .background { if on { RoundedRectangle(cornerRadius: Radius.segment).fill(Tok.surface3) } }
                    .overlay { if on { RoundedRectangle(cornerRadius: Radius.segment).strokeBorder(Tok.borderStrong, lineWidth: 1) } }
                    .contentShape(RoundedRectangle(cornerRadius: Radius.segment))
                    .wfRect(rectID.isEmpty ? "" : "\(rectID).\(index)", size: 12, weight: 500, radius: Radius.segment)
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
                .accessibilityValue(on ? "Selected" : "")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .frame(maxWidth: fill ? .infinity : nil)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.track), stroke: Tok.border, fill: Tok.surface2)
        .wfRect(rectID, radius: Radius.track)
        .fixedSize(horizontal: !fill, vertical: true)
        .opacity(ControlEnabledStyle.opacity(isEnabled: isEnabled))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: Inspector pieces

/// `.sec`: padding 10 x 12, a 1 pt `border` line above every section but the first. The caller says which one this is.
struct EditSection<Content: View>: View {
    var first = false
    var rectID = ""
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .padding(.top, first ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .top) { if !first { Rectangle().fill(Tok.border).frame(height: 1) } }
            .wfRect(rectID)
    }
}

/// `.h` with the design's 6 pt gap under it.
struct EditHeading: View {
    let text: String
    var rectID = ""
    var body: some View {
        Text(text.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(Tok.muted).wfLine()
            .frame(maxWidth: .infinity, alignment: .leading)
            .wfRect(rectID, size: 11, weight: 600)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `.fr`: a 30 pt row of `label.k` (64 wide, right-aligned, 12 muted) and its controls with 8 between them.
struct EditRow<Content: View>: View {
    var label: String? = nil
    var rectID = ""
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            if let label {
                Text(label).font(.wf(12)).foregroundStyle(Tok.muted).wfLine().frame(width: 64, alignment: .trailing)
                    .wfRect(rectID.isEmpty ? "" : "\(rectID).k", size: 12, weight: 400)
            }
            content()
        }
        .frame(width: 295, height: 30, alignment: .leading)      // the inspector's 320 less its line and 12 pt either side; a row wider than that overflows, as in the mockup
        .wfRect(rectID)
    }
}

/// `.field.mono`: 26 pt, mono 11, an optional muted prefix (X, Y, W, H). Commits on Return and when it loses focus; an entry that does not
/// parse goes back to what the model has.
struct EditNumberField: View {
    let value: String
    var prefix: String? = nil
    var mono = true
    var label: String
    var rectID = ""
    /// Returns false when the text could not be used (the field then shows the model's value again).
    let commit: (String) -> Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let prefix { Text(prefix).font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine().accessibilityHidden(true) }
            TextField("", text: $text).textFieldStyle(.plain).font(mono ? .wfMono(11) : .wf(12)).foregroundStyle(Tok.text)
                .focused($focused)
                .onSubmit { apply() }
                .onChange(of: focused) { _, now in if !now { apply() } }
                .accessibilityLabel(label)
        }
        .wfField()
        .wfRect(rectID, size: 11, weight: 400, radius: Radius.md)
        .onAppear { text = value }
        .onChange(of: value) { _, new in if !focused { text = new } }
    }

    private func apply() {
        if text == value { return }
        if !commit(text) { text = value }
    }
}

/// A closed `.field` showing a value in a pop-up menu with the design's chevron; the choices are the menu's items.
struct EditPopup<Content: View>: View {
    let title: String
    var accessibilityName: String
    var rectID = ""
    @ViewBuilder let content: () -> Content
    var body: some View {
        WFPopup(title: title, accessibilityName: accessibilityName, rectID: rectID, content: content)
    }
}

/// `.sw`: a 22 pt rounded swatch with a 1 pt `border-strong` outline. A click opens `popover`.
struct EditSwatch<Popover: View>: View {
    let color: Color
    var label: String
    var rectID = ""
    @ViewBuilder let popover: () -> Popover
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tok.borderStrong, lineWidth: 1))
                .wfRect(rectID, radius: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .leading) { popover().padding(12) }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A 14 pt line of design-sized icon and words, used by the inspector's layer and tab text.
extension View {
    /// The design's checkbox label: 13 pt text beside a 14 pt box with 8 between.
    func editLabel() -> some View { font(.wf(13)).foregroundStyle(Tok.text).wfLine() }
}

/// `.chk` with its label: a 14 pt box (radius 3, 1 pt `border-strong`; on = `blue` fill) and 13 pt words 8 pt after it. Still a toggle for
/// VoiceOver and the keyboard. `rectID` names the box, `<rectID>.label` the words.
struct EditCheckbox: View {
    @Binding var isOn: Bool
    let title: String
    var rectID = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { if ControlEnabledStyle.acceptsInput(isEnabled: isEnabled) { isOn.toggle() } } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(isOn ? Tok.blue : .clear)
                    RoundedRectangle(cornerRadius: 3).strokeBorder(isOn ? Tok.blue : Tok.borderStrong, lineWidth: 1)
                    if isOn { Image(systemName: "checkmark").font(.wf(9, .bold)).foregroundStyle(scheme == .light ? Color.white : Tok.onBrand) }
                }
                .frame(width: 14, height: 14)
                .wfRect(rectID, radius: 3)
                Text(title).editLabel().wfRect(rectID.isEmpty ? "" : "\(rectID).label", size: 13, weight: 400)
            }
            .contentShape(Rectangle())
            .opacity(ControlEnabledStyle.opacity(isEnabled: isEnabled))
            .wfFocusReport(.checkbox)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: $isOn) { Text(title) } }
    }
}
