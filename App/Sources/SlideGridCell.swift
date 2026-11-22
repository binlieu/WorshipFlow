// FIX-M: one slide thumbnail of the Show grid, split out of `SlideGrid` so it compares by value. A reorder or an edit that changes one slide
// redraws that slide's cell, not every cell; the cell's identity is the slide's (`SlideCellKey`), not its position. The drag image is a small
// label made when the drag starts, never the cell's view hierarchy.
import SwiftUI
import Domain
import OperatorCore

/// A cell's place in a run: where it is now and the identity it keeps across a reorder.
struct CellSlot: Identifiable {
    let index: Int
    let key: SlideCellKey
    var id: SlideCellKey { key }
}

/// The small picture that follows the pointer while something is dragged: a label, not a render of what is dragged.
struct DragChip: View {
    let text: String
    var symbol = "rectangle.on.rectangle"
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.wf(11, .semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Tok.text)
            .background(Tok.surface3, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tok.border, lineWidth: 1))
            .fixedSize()
    }
}

struct SlideGridCell: View, @MainActor Equatable {
    let app: AppModel
    let workspace: WorkspaceModel
    let slide: Slide
    let index: Int
    let isLast: Bool
    let color: Color
    let available: Set<UUID>?
    let onDelete: (Int) -> Void

    static func == (a: SlideGridCell, b: SlideGridCell) -> Bool {
        a.slide == b.slide && a.index == b.index && a.isLast == b.isLast && a.color == b.color && a.available == b.available
    }

    /// FIX-Q: the cell asks for its own marks, so Next, Previous and a selection wake the two cells that change and never the grid's body.
    /// The live mark counts only while the live deck is the open presentation. Only the live cell draws the mode (FIX-O).
    private struct Marks { var selected: Bool; var live: Bool; var mode: LiveMode }
    private var marks: Marks {
        let live = app.showParts.liveDeckID == workspace.openPresentationID && app.showParts.isLive(at: index)
        return Marks(selected: workspace.showParts.isSelected(at: index), live: live, mode: live ? app.mode : .live)
    }

    var body: some View {
        let _ = BodyProbe.hit("SlideGridCell")
        let i = index
        let marks = marks
        let (selected, live, mode) = (marks.selected, marks.live, marks.mode)
        let ringColor = mode == .live ? Tok.liveFill : Tok.warning
        VStack(alignment: .leading, spacing: 3) {
            // The rings are drawn outside the picture (never over the words): idle 1 pt, preview 2 pt blue, live 3 pt red, at a 2 pt offset.
            SlideThumbnail(app: app, slide: slide.content)
                .wfRect("main.cell.\(i).thumb", radius: 4)
                .overlay(alignment: .topLeading) { tags(selected: selected, live: live, mode: mode).wfRect("main.cell.\(i).tag", size: 9, weight: 800, radius: Radius.xs).padding(5) }
                .overlay(alignment: .bottomTrailing) { OwnBackgroundMark(content: slide.content, available: available).padding(5) }
                .wfThumbState(radius: 4, preview: selected && !live, live: live, liveColor: ringColor)
                .padding(5)    // room for the outer ring inside the cell
                .padding(-5)
            HStack(spacing: 6) {
                Text("\(i + 1)").font(.wf(11, .semibold).monospacedDigit()).foregroundStyle(Tok.text).wfLine().wfRect("main.cell.\(i).num", size: 11, weight: 600)
                let first = slide.content.primary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                Text(first.isEmpty ? "Blank · background only" : first)
                    .font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wfRect("main.cell.\(i).cap")
        }
        .wfRect("main.cell.\(i)")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.triggerSlide(i) }
        .onTapGesture { workspace.selectSlide(i) }
        .draggable("\(i)") { DragChip(text: "Slide \(i + 1)") }
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first else { return false }
            // MEDIA-010: a tile from the media bin is this slide's own background; a slide's index is a reorder.
            if let mediaID = SlideBackgroundDrop.mediaID(fromDragText: text) { return app.setSlideBackground(mediaID: mediaID, slideID: slide.id) }
            guard let from = Int(text), from != i else { return false }
            Task { await workspace.moveSlide(from: from, to: i) }
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in app.setSlideBackground(fileURLs: urls, slideID: slide.id) }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)")
        .accessibilityValue(stateWord(selected: selected, live: live, mode: mode))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func tags(selected: Bool, live: Bool, mode: LiveMode) -> some View {
        if live {
            switch mode {
            case .cleared: ThumbTag(text: "CLEARED", kind: .warning)
            case .blackout: ThumbTag(text: "BLACKOUT", kind: .warning)
            default: ThumbTag(text: "LIVE", kind: .live)
            }
        } else if selected {
            ThumbTag(text: "PREVIEW", kind: .preview)
        }
    }

    private func stateWord(selected: Bool, live: Bool, mode: LiveMode) -> String {
        var words: [String] = []
        if live { words.append(mode == .cleared ? "live place, cleared" : (mode == .blackout ? "live place, blackout" : "live")) }
        if selected { words.append("in preview") }
        return words.joined(separator: ", ")
    }

    @ViewBuilder private var menu: some View {
        let i = index
        Button("Go Live") { app.triggerSlide(i) }
        Button("Quick edit") { workspace.selectSlide(i); app.openQuickEdit() }
        SlideBackgroundMenuItems(app: app, slide: slide)
        Divider()
        Button("Move earlier") { Task { await workspace.moveSlide(from: i, to: i - 1) } }.disabled(i == 0)
        Button("Move later") { Task { await workspace.moveSlide(from: i, to: i + 1) } }.disabled(isLast)
        Divider()
        Button("Delete slide…", role: .destructive) { onDelete(i) }
    }
}

/// FIX-M: files dropped from Finder onto a panel. The highlight is this modifier's own state, so entering and leaving the panel while a drag
/// passes over it changes one small overlay and never re-evaluates the panel's content (the 100-tile bin, the dock's strip).
struct FileDropTarget: ViewModifier {
    let color: Color
    let radius: CGFloat
    let onDrop: ([URL]) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(targeted ? color : .clear, lineWidth: 2).allowsHitTesting(false))
            .dropDestination(for: URL.self) { urls, _ in onDrop(urls) } isTargeted: { targeted = $0 }
    }
}

extension View {
    func fileDropTarget(color: Color, radius: CGFloat, onDrop: @escaping ([URL]) -> Bool) -> some View {
        modifier(FileDropTarget(color: color, radius: radius, onDrop: onDrop))
    }
}

extension MediaAsset {
    /// The symbol in a bin tile's drag label.
    var dragSymbol: String { kind == .video ? "film" : (kind == .audio ? "music.note" : "photo") }
}
