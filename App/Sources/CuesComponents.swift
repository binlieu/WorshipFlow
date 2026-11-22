// UI-005g: the pieces the Cues mode draws from docs/UI/mockups/06-cues.html and ui.css: the 26 pt list row (`.li`), the padded section
// with its hairline (`.sec`), the page bar (`.bar`), the table rows and the inline key chip (`.kbd` in a cell). Defined here, in the
// Cues files, because the shared components do not have them yet (listed as "wanted in the shared files" in the report).
import SwiftUI
import OperatorCore

// MARK: Section (`.sec`)

/// `.sec`: padding 10 x 12 and a 1 pt `border` line above every section but the first.
struct CuesSection<Content: View>: View {
    var first = false
    var rectID = ""
    var grows = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { Rectangle().fill(Tok.border).frame(height: 1) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: grows ? .infinity : nil, alignment: .topLeading)
        }
        .wfRect(rectID)
    }
}

// MARK: List row (`.li`)

/// `.li`: 26 pt, padding 0 8, gap 8, radius 6, a 15 pt icon in the text colour, 13 pt title, the count or state at the right in `muted` 11 pt.
struct CuesListRow: View {
    let symbol: String
    let title: String
    var count: String? = nil
    var trailing: AnyView? = nil
    var selected = false
    var enabled = true
    var rectID = ""
    var accessibility = ""
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.wf(13)).frame(width: 15, height: 15).accessibilityHidden(true)
                Text(title).font(.wf(13)).lineLimit(1).wfLine()
                Spacer(minLength: 4)
                if let count { Text(count).font(.wf(11)).foregroundStyle(Tok.muted).wfLine().wfRect(rectID.isEmpty ? "" : "\(rectID).n", size: 11, weight: 400) }
                if let trailing { trailing }
            }
                        .padding(.horizontal, 8).frame(height: 26)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .wfRect(rectID, size: 13, weight: 400, radius: Radius.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibility.isEmpty ? title : accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Page bar (`.bar`)

/// `.bar`: padding 8 x 14, a 1 pt `border` line under it; 43 pt with a 26 pt control in it.
struct CuesPage<Leading: View, Trailing: View, Content: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                leading()
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 14).frame(height: 42)
            .wfRect("main.bar")
            Rectangle().fill(Tok.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// The bar's 17 pt bold title on a 22 pt line.
struct CuesTitle: View {
    let text: String
    var body: some View { Text(text).font(.wf(17, .bold)).lineLimit(1).wfLine(22).wfRect("main.title", size: 17, weight: 700).accessibilityAddTraits(.isHeader) }
}

extension CuesPage where Leading == CuesTitle, Trailing == EmptyView {
    /// A bar with only a title.
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(leading: { CuesTitle(text: title) }, trailing: { EmptyView() }, content: content)
    }
}
extension CuesPage where Leading == CuesTitle {
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.init(leading: { CuesTitle(text: title) }, trailing: trailing, content: content)
    }
}

// MARK: Small button (`.btn` at 22 pt)

struct CuesSmallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wf(12, .medium)).padding(.horizontal, 11).frame(height: 22)
            .foregroundStyle(Tok.text)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.surface2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            .wfFocusReport(.button)
    }
}

// MARK: Table (`table` in 06-cues.html)

/// One table row: cells with padding 6 x 8 (12 pt text on a 16 pt line), a 1 pt `border` line under it. 29 pt; the first row of a table
/// without a header is 28 (collapsed borders).
struct CuesTableRow<Content: View>: View {
    var height: CGFloat = 29
    var line = true
    var rectID = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) { content() }
            .frame(height: height, alignment: .center)
            .overlay(alignment: .bottom) { if line { Rectangle().fill(Tok.border).frame(height: 1) } }
            .wfRect(rectID)
    }
}

/// A cell: its own width, 8 pt of padding at each side.
struct CuesCell<Content: View>: View {
    var width: CGFloat?
    var rectID = ""
    var size: Double = 12
    var weight: Double = 400
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity, alignment: .leading)
            .wfRect(rectID, size: size, weight: weight)
    }
}

/// `.kbd` inside a table cell: an inline box, 10 pt mono medium, padding 0 4 and a 1 pt border, 14 pt tall, at 75 %.
struct CuesKbd: View {
    let key: String
    var rectID = ""
    var body: some View {
        Text(key).font(.wfMono(10, .medium)).fixedSize()
            .frame(width: key.count == 1 ? 6.1 : nil)
            .padding(.horizontal, 5).frame(height: 14)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.xs), stroke: Tok.text.opacity(0.75))
            .foregroundStyle(Tok.text.opacity(0.75))
            .wfRect(rectID, size: 10, weight: 500, radius: Radius.xs)
            // The cell's line box is 16 pt and the inline box sits on its baseline, near the line's bottom (the design's top is 1.9 pt down).
            .frame(height: 16, alignment: .bottom)
            .accessibilityHidden(true)
    }
}

/// `th`: 11 pt 600, upper case, tracking .04em, `muted`.
struct CuesTableHead: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.wf(11, .semibold)).tracking(0.44).foregroundStyle(Tok.muted).wfLine()
    }
}

/// The title chip (`.pill`): like `PillTag`, with tabular figures as the mockup's CSS turns on (`tnum`), so "5 actions" is as wide as the design's.
struct CuesChip: View {
    let text: String
    var rectID = ""
    var body: some View {
        Text(text).font(.wf(11, .semibold)).monospacedDigit().lineLimit(1).wfLine()
            .foregroundStyle(Tok.muted)
            .padding(.horizontal, 9).frame(height: 20)
            .wfOutline(RoundedRectangle(cornerRadius: 10, style: .circular), stroke: Tok.borderStrong)
            .wfRect(rectID, size: 11, weight: 600, radius: 10)
            .fixedSize()
    }
}

extension DateFormatter {
    /// `09:03:11`: the Activity list's 24-hour time.
    static let cuesClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
