// UI-005f: the small pieces the Screens mode needs that the shared components do not have (CSS line boxes for wrapped text, a form row,
// a read-only field, the BNC ring, a label the operator typed). Defined here because the shared files are not edited by this slice;
// listed in the report as wanted in `Components.swift`.
import SwiftUI
import CoreText
import AppKit

extension Text {
    /// The CSS line box for text that may wrap: every line is `lineHeight` tall (ui.css gives most text 16), whatever the font's own
    /// height. SwiftUI adds the difference between lines (`lineSpacing`) and half of it above and below, so n lines are n * lineHeight.
    func screensLines(_ size: CGFloat, _ weight: Font.Weight = .regular, lineHeight: CGFloat = 16, mono: Bool = false) -> some View {
        let natural: CGFloat = {
            if mono { return (size * 1.27).rounded() }      // SwiftUI's monospaced system face: 14 pt for 11 pt text
            if let f = InterFont.ctFont(size: size, weight: InterFont.cssWeight(weight)) { return f.lineHeight }
            return size * 1.21
        }()
        let extra = max(0, lineHeight - natural)
        return self.font(mono ? .wfMono(size, weight) : .wf(size, weight)).lineSpacing(extra).padding(.vertical, extra / 2)
    }
}

private extension CTFont {
    /// SwiftUI's own line height: the ascent, descent and leading each rounded to whole points.
    var lineHeight: CGFloat { CTFontGetAscent(self).rounded() + CTFontGetDescent(self).rounded() + CTFontGetLeading(self).rounded() }
}

/// One row of the form: a 96 pt right-aligned label (`label.k`), 8 pt, then the content; at least 32 pt tall (`.fr`).
struct ScreensFormRow<Content: View>: View {
    let label: String
    var rectID = ""
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.wf(12)).foregroundStyle(Tok.muted).wfLine().frame(width: 96, alignment: .trailing)
                .wfRect(rectID.isEmpty ? "" : "\(rectID).label", size: 12, weight: 400)
            content()
        }
        .frame(minHeight: 32)
        .wfRect(rectID)
    }
}

/// A field that shows what the app does and cannot be changed (the design's pop-up chrome with no chevron, in the muted text colour).
struct ScreensReadOnlyField: View {
    let text: String
    var help: String = ""
    var rectID = ""
    var body: some View {
        Text(text).font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
            .frame(maxWidth: .infinity, alignment: .leading)
            .wfField()
            .wfRect(rectID, size: 12, weight: 400, radius: Radius.md)
            .help(help.isEmpty ? text : help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help.isEmpty ? text : "\(text). \(help)")
    }
}

/// The design's `.bnc`: a 20 pt ring, 3 pt thick, with a 6 pt dot in the middle, in the role colour.
struct ScreensBNC: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 3)
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// A node of the signal map (`.node`): `surface-2`, 1 pt `border-strong`, radius 8, padding 8 x 10, 15 pt lines.
struct ScreensNodeChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11).padding(.vertical, 9)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.lg), stroke: Tok.borderStrong, fill: Tok.surface2)
    }
}

/// A label the operator typed for where a connector goes (a switcher input, a projector). It is drawn as a node, with the words
/// "typed by you" in the sub line: WorshipFlow cannot see what is plugged in, so nothing here is presented as detected.
struct ScreensTypedNode: View {
    let text: String
    var rectID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text).font(.wf(12, .bold)).lineLimit(1).frame(height: 15, alignment: .leading)
                .wfRect(rectID.isEmpty ? "" : "\(rectID).text", size: 12, weight: 700)
            Text("typed by you").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).frame(height: 15, alignment: .leading)
                .wfRect(rectID.isEmpty ? "" : "\(rectID).sub", size: 11, weight: 400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ScreensNodeChrome())
        .wfRect(rectID, radius: Radius.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connected to \(text), typed by you")
    }
}
