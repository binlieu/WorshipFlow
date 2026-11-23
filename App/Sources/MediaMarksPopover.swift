// UI-007d (MEDIA): the clip's in and out marks and its markers, as the player strip's popover shows them. Mark in, Mark out and Add marker in the strip
// set a mark or a marker at the preview's playhead; here a time can be typed, a mark cleared, and each marker renamed, moved, deleted or jumped to.
// A mark and a marker belong to the bin item: they are stored with it, and live playback honours them (a clip that is on air keeps the marks it
// started with). The preview player here never runs a marker's actions; only a clip playing on the screens does.
import SwiftUI
import Domain
import OperatorCore

/// The strip's three buttons (the design's "Mark in", "Mark out" and "Add marker") and the button that opens the list.
struct MediaMarkButtons: View {
    let media: MediaModel
    let markers: MediaMarkerModel
    let preview: MediaPreviewModel
    let asset: MediaAsset
    @State private var listShown = false

    var body: some View {
        let inBin = media.assets.contains { $0.id == asset.id }
        HStack(spacing: 8) {
            Button { Task { await media.setMarkIn(preview.position, for: asset.id) } } label: { Text("Mark in").wfLine().fixedSize() }
                .buttonStyle(HeaderButtonStyle(selected: asset.markIn != nil)).wfRect("media.strip.markin", size: 12, weight: 500, radius: Radius.md)
                .help(markHelp("in", asset.markIn, "Play from the playhead"))
                .accessibilityLabel("Mark in").accessibilityValue(asset.markIn.map(MediaTimeText.format) ?? "not set")
                .contextMenu { Button("Clear mark in") { Task { await media.setMarkIn(nil, for: asset.id) } }.disabled(asset.markIn == nil) }
            Button { Task { await media.setMarkOut(preview.position, for: asset.id) } } label: { Text("Mark out").wfLine().fixedSize() }
                .buttonStyle(HeaderButtonStyle(selected: asset.markOut != nil)).wfRect("media.strip.markout", size: 12, weight: 500, radius: Radius.md)
                .help(markHelp("out", asset.markOut, "Stop (or loop) at the playhead"))
                .accessibilityLabel("Mark out").accessibilityValue(asset.markOut.map(MediaTimeText.format) ?? "not set")
                .contextMenu { Button("Clear mark out") { Task { await media.setMarkOut(nil, for: asset.id) } }.disabled(asset.markOut == nil) }
            Button { Task { await markers.add(to: asset.id, at: preview.position) } } label: {
                HStack(spacing: 6) { Image(systemName: "bolt").font(.wf(11)).frame(width: 12, height: 12); Text("Add marker").wfLine().fixedSize() }
            }
            .buttonStyle(HeaderButtonStyle()).wfRect("media.strip.addmarker", size: 12, weight: 500, radius: Radius.md)
            .help("Add a marker at the playhead. Give it actions in the Cues mode; they run when this clip is playing live and passes it.")
            .accessibilityLabel("Add marker at the playhead")
            Button { listShown.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(.wf(11)).frame(width: 12, height: 12)
                    let count = markers.markers(for: asset.id).count
                    if count > 0 { Text("\(count)").font(.wf(11, .semibold).monospacedDigit()).wfLine() }
                }
            }
            .buttonStyle(HeaderButtonStyle(kind: .ghost)).wfRect("media.extra.marklist")
            .help("In and out marks and markers: type a time, rename, move or delete")
            .accessibilityLabel("Marks and markers").accessibilityHint("Opens the list of this clip's marks and markers")
            .popover(isPresented: $listShown, arrowEdge: .top) {
                MediaMarksPopover(media: media, markers: markers, preview: preview, assetID: asset.id)
            }
        }
        .disabled(!inBin)
        .help(inBin ? "" : "Marks and markers are kept for items in the media bin. Add this item to the bin first.")
    }

    private func markHelp(_ which: String, _ time: Double?, _ action: String) -> String {
        let now = MediaTimeText.format(preview.position)
        let current = time.map { " Now \(MediaTimeText.format($0))." } ?? ""
        return "\(action) (\(now)).\(current) Right-click to clear."
    }
}

struct MediaMarksPopover: View {
    let media: MediaModel
    let markers: MediaMarkerModel
    let preview: MediaPreviewModel
    let assetID: UUID

    var body: some View {
        if let asset = media.asset(assetID) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Marks and markers").font(.wf(14, .bold)).accessibilityAddTraits(.isHeader)
                Text("\(asset.name) · \(asset.duration.map(MediaTimeText.format) ?? "length not known")")
                    .font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Plays from and to")
                    MarkRow(title: "In", time: asset.markIn, none: "start of the clip", preview: preview,
                            set: { t in Task { await media.setMarkIn(t, for: asset.id) } })
                    MarkRow(title: "Out", time: asset.markOut, none: "end of the clip", preview: preview,
                            set: { t in Task { await media.setMarkOut(t, for: asset.id) } })
                    Text("The clip starts at In and stops, or loops, at Out. A clip that is on air now keeps the marks it started with.")
                        .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel("Markers")
                        Spacer()
                        Button { Task { await markers.add(to: asset.id, at: preview.position) } } label: {
                            Label("Add at playhead", systemImage: "plus").font(.wf(11, .medium))
                        }
                        .buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true)).accessibilityLabel("Add marker at the playhead")
                    }
                    let list = markers.markers(for: asset.id)
                    if list.isEmpty {
                        Text("No markers. A marker runs its actions when this clip, playing on the screens, passes its time.")
                            .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(list) { marker in
                        MarkerRow(marker: marker, markers: markers, preview: preview, actionCount: markers.actions(of: marker.id).count)
                            .id(marker.id)
                    }
                }
            }
            .padding(14).frame(width: 420, alignment: .leading)
        } else {
            Text("This item is no longer in the media bin.").font(.wf(12)).foregroundStyle(Tok.muted).padding(14)
        }
    }
}

/// In or Out: the time typed in a field (committed on Return or when the field is left), Set at playhead, Clear.
private struct MarkRow: View {
    let title: String
    let time: Double?
    let none: String
    let preview: MediaPreviewModel
    let set: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.wf(12, .semibold)).frame(width: 26, alignment: .leading)
            TextField(none, text: $text).textFieldStyle(.plain).wfField(height: 24).frame(width: 110)
                .font(.wfMono(12)).focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .accessibilityLabel("\(title) mark time").accessibilityHint("Type minutes and seconds, such as 1:05.5, then press Return")
            Button("Set at playhead") { set(preview.position) }.buttonStyle(HeaderButtonStyle(compact: true))
                .accessibilityLabel("Set \(title.lowercased()) mark at the playhead")
            Button("Clear") { set(nil) }.buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true)).disabled(time == nil)
                .accessibilityLabel("Clear \(title.lowercased()) mark")
            Spacer(minLength: 0)
        }
        .task(id: time) { text = time.map(MediaTimeText.format) ?? "" }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { if time != nil { set(nil) }; return }
        guard let value = MediaTimeText.parse(trimmed) else { text = time.map(MediaTimeText.format) ?? ""; return }
        if value != time { set(value) }
    }
}

/// One marker: its time (typed), its name, jump to it, delete. Its actions are edited in the Cues mode.
private struct MarkerRow: View {
    let marker: MediaMarker
    let markers: MediaMarkerModel
    let preview: MediaPreviewModel
    let actionCount: Int
    @State private var timeText = ""
    @State private var nameText = ""
    @FocusState private var timeFocused: Bool
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("00:00.0", text: $timeText).textFieldStyle(.plain).wfField(height: 24).frame(width: 84).font(.wfMono(12))
                .focused($timeFocused).onSubmit(commitTime).onChange(of: timeFocused) { _, now in if !now { commitTime() } }
                .accessibilityLabel("Marker time")
            TextField("Name", text: $nameText).textFieldStyle(.plain).wfField(height: 24).focused($nameFocused)
                .onSubmit(commitName).onChange(of: nameFocused) { _, now in if !now { commitName() } }
                .accessibilityLabel("Marker name")
            Text(actionCount == 0 ? "no actions" : "\(actionCount) action\(actionCount == 1 ? "" : "s")").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1)
                .fixedSize()
            Button { preview.seek(to: marker.time) } label: { Image(systemName: "arrow.right.to.line").font(.wf(11)).frame(width: 12, height: 12) }
                .buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true)).help("Move the preview playhead here").accessibilityLabel("Go to marker")
            Button(role: .destructive) { Task { await markers.delete(marker.id) } } label: { Image(systemName: "trash").font(.wf(11)).frame(width: 12, height: 12) }
                .buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true)).help("Delete this marker").accessibilityLabel("Delete marker")
        }
        .task(id: marker.time) { timeText = MediaTimeText.format(marker.time) }
        .task(id: marker.name) { nameText = marker.name ?? "" }
    }

    private func commitTime() {
        guard let value = MediaTimeText.parse(timeText) else { timeText = MediaTimeText.format(marker.time); return }
        if abs(value - marker.time) > 0.0005 { Task { await markers.move(marker.id, to: value) } }
    }

    private func commitName() {
        let clean = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != (marker.name ?? "") { Task { await markers.rename(marker.id, to: clean.isEmpty ? nil : clean) } }
    }
}
