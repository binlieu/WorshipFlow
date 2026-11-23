// APP-001 / KI-023 / SLIDE-003: the section order editor. A section order is the sequence in which the open song's
// sections are sung (for example Verse 1, Chorus, Verse 2, Chorus, Chorus). Every change is saved at once.
import SwiftUI
import Domain
import OperatorCore

struct SectionOrderSheet: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var nameText = ""
    @State private var pendingDelete = false

    private var presentationTitle: String {
        workspace.presentations.first { $0.id == workspace.openPresentationID }?.title ?? "this song"
    }

    private var selected: Arrangement? { workspace.arrangements.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = workspace.lastError { ErrorBar(message: error) { workspace.dismissError() } }
            HStack {
                Text("Section orders for \"\(presentationTitle)\"").font(.wf(15, .bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("A section order is the sequence the sections are sung in. A playlist item can play its song in natural order or in one of these.")
                .font(.wfSmall).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                orderList.frame(width: 220)
                Divider()
                editor.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if workspace.selectedPlaylistItemID != nil { itemPicker }
        }
        .padding(18)
        .frame(width: 760, height: 520)
        .onAppear { ensureSelection() }
        .onChange(of: workspace.arrangements) { _, _ in ensureSelection() }
        .onChange(of: selectedID) { _, _ in nameText = selected?.name ?? "" }
        .confirmationDialog("Delete the section order \"\(selected?.name ?? "")\"?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete section order", role: .destructive) {
                if let id = selectedID { Task { await workspace.deleteSectionOrder(id: id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Playlist items that used it go back to natural order. The song's slides are not changed.") }
    }

    private func ensureSelection() {
        if selected == nil { selectedID = workspace.arrangements.first?.id }
        nameText = selected?.name ?? ""
    }

    // MARK: Orders

    private var orderList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orders").font(.wfHeadline)
            List(selection: $selectedID) {
                ForEach(workspace.arrangements) { order in
                    Text(order.name).tag(order.id)
                }
            }
            .accessibilityLabel("Section orders")
            .overlay {
                if workspace.arrangements.isEmpty {
                    Text("No section orders yet.\nNew order starts with every section once.")
                        .multilineTextAlignment(.center).font(.wfSmall).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("New order") {
                    Task { if let made = await workspace.createSectionOrder() { selectedID = made.id } }
                }
                Button("Delete…", role: .destructive) { pendingDelete = true }.disabled(selected == nil)
            }
        }
    }

    // MARK: Editing one order

    @ViewBuilder private var editor: some View {
        if let order = selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Name").font(.wfSmall).foregroundStyle(.secondary)
                    TextField("Name", text: $nameText)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .onSubmit { commitName(order) }
                    Button("Rename") { commitName(order) }.disabled(nameText == order.name)
                }
                Text("Add a section").font(.wfHeadline)
                if workspace.groups.isEmpty {
                    Text("This song has no named sections. Import lyrics with section names such as Verse 1 and Chorus.")
                        .font(.wfSmall).foregroundStyle(.secondary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(workspace.groups) { group in
                        Button { Task { await workspace.addSection(group.id, toSectionOrder: order.id) } } label: {
                            Label(group.name, systemImage: "plus.circle")
                        }
                        .help("Add \(group.name) to the end of \(order.name)")
                    }
                }
                HStack {
                    Text("Plays in this order").font(.wfHeadline)
                    Spacer()
                    Text(summary(order)).font(.wfSmall).foregroundStyle(.secondary)
                }
                entries(order)
            }
        } else {
            Text("Choose a section order, or make a new one.").foregroundStyle(.secondary)
        }
    }

    private func summary(_ order: Arrangement) -> String {
        let slides = SectionOrderEditing.slideCount(of: order.groupIDs, counts: workspace.groupSlideCounts)
        return "\(order.groupIDs.count) sections, \(slides) slides"
    }

    private func entries(_ order: Arrangement) -> some View {
        List {
            // FIX-V item 3: each row carries its entry (section and occurrence), never a position, so a quick second click cannot act on a row
            // that has since moved.
            let entries = workspace.sectionEntries(of: order)
            ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                let groupID = entry.groupID
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.wfSmall).foregroundStyle(.secondary).frame(width: 24)
                    Text(workspace.groups.first { $0.id == groupID }?.name ?? "Missing section").frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await workspace.moveSection(entry, by: -1, inSectionOrder: order.id) } } label: {
                        Image(systemName: "arrow.up")
                    }.disabled(index == 0).help("Move earlier").accessibilityLabel("Move \(index + 1) earlier")
                    Button { Task { await workspace.moveSection(entry, by: 1, inSectionOrder: order.id) } } label: {
                        Image(systemName: "arrow.down")
                    }.disabled(index == order.groupIDs.count - 1).help("Move later").accessibilityLabel("Move \(index + 1) later")
                    Button { Task { await workspace.removeSection(entry, fromSectionOrder: order.id) } } label: {
                        Image(systemName: "minus.circle")
                    }.help("Remove from this order").accessibilityLabel("Remove \(index + 1)")
                }
                .buttonStyle(.borderless)
                .accessibilityElement(children: .contain)
            }
            .onMove { source, destination in
                guard let from = source.first, entries.indices.contains(from) else { return }
                let to = destination > from ? destination - 1 : destination
                guard to != from else { return }
                let target: SectionEntry? = destination < entries.count ? entries[destination] : nil
                Task { await workspace.moveSection(entries[from], before: target, inSectionOrder: order.id) }
            }
        }
        .frame(minHeight: 150)
        .accessibilityLabel("Sections in \(order.name)")
    }

    private func commitName(_ order: Arrangement) {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != order.name else { return }
        Task {
            await workspace.renameSectionOrder(id: order.id, to: trimmed)
            nameText = selected?.name ?? ""
        }
    }

    // MARK: Playlist item

    @ViewBuilder private var itemPicker: some View {
        if let itemID = workspace.selectedPlaylistItemID, let item = workspace.playlistItems.first(where: { $0.id == itemID }) {
            Divider()
            HStack {
                Text("In the playlist, \"\(item.title)\" plays").font(.wfSubheadline)
                Picker("Plays", selection: Binding(get: { item.arrangementID },
                                                    set: { id in Task { await workspace.setArrangement(id, forPlaylistItem: itemID) } })) {
                    Text("Natural order").tag(UUID?.none)
                    ForEach(workspace.arrangements) { Text($0.name).tag(UUID?.some($0.id)) }
                }.labelsHidden().frame(maxWidth: 260)
                Spacer()
            }
        } else {
            Text("Open a song from the playlist to choose which order it plays.").font(.wfSmall).foregroundStyle(.secondary)
        }
    }
}

/// Buttons that wrap onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
