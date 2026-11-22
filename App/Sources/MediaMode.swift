// UI-005d: the Media mode drawn to docs/UI/mockups/05-media-audio.html: a 220 pt bin list, the centre (header bar, 5-column grid,
// clip strip) and a 340 pt audio column. Moved out of ModeViews.swift; the decisions stay in `MediaModel`, `AudioModel` and
// `AppModel`. What the design draws and the app cannot do yet (named collections, live inputs, the offline callout, in and out
// points and markers, the routing matrix, the cue meters) is left out with its room kept, so the rest lines up.
import SwiftUI
import Domain
import OperatorCore

struct MediaModeView: View {
    let app: AppModel
    /// The grid / list switch of the header bar (local to the view: it is a way of looking, not a setting of the library).
    @State private var listMode = false

    var body: some View {
        if let media = app.media {
            HStack(alignment: .top, spacing: 0) {
                MediaSidebar(app: app, media: media)
                MediaCentre(app: app, media: media, listMode: $listMode)
                    .frame(maxWidth: .infinity)
                if let audio = app.audio { MediaAudioColumn(app: app, audio: audio) }
            }
        } else {
            Text("The media bin is not available.").foregroundStyle(Tok.muted).padding(Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Left list

/// One row of the design's `.li`: 26 high, padding 0 x 8, an icon, the name and a count at the right.
struct MediaSidebarRow: View {
    let symbol: String
    let title: String
    let count: String
    let selected: Bool
    var tint: Color? = nil
    let rectID: String
    var accessibility = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.wf(13)).frame(width: 15, height: 15).foregroundStyle(tint ?? Tok.text)
                Text(title).font(.wf(13)).lineLimit(1).wfLine().foregroundStyle(Tok.text)
                Spacer(minLength: 0)
                Text(count).font(.wf(11)).wfLine().foregroundStyle(tint ?? Tok.muted).wfRect(rectID + ".n", size: 11, weight: 400)
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
            .wfRect(rectID, size: 13, weight: 400, radius: Radius.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility.isEmpty ? "\(title), \(count)" : accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MediaSidebar: View {
    let app: AppModel
    @Bindable var media: MediaModel

    var body: some View {
        let entries = MediaBinCategories.entries(kinds: media.assets.map(\.kind))
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // The design's first group is 172 high with five rows; two of them (Announcement loop, Live inputs) do not exist, their room stays.
                VStack(alignment: .leading, spacing: 0) {
                    header("Media bin", rectID: "media.sb.h.0").padding(.bottom, 6)
                    ForEach(Array(entries.filter { !$0.isAudio }.enumerated()), id: \.element.title) { index, entry in row(entry, id: "media.sb.row.\(index)") }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(height: 172, alignment: .topLeading)
                Rectangle().fill(Tok.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    header("Audio", rectID: "media.sb.h.1").padding(.bottom, 6)
                    ForEach(Array(entries.filter(\.isAudio).enumerated()), id: \.element.title) { index, entry in row(entry, id: "media.sb.audio.\(index)") }
                    folders.padding(.top, 34)      // below the room of the Sound cues row the design draws
                }
                .padding(.horizontal, 12).padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(width: 219)
            .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(Tok.border).frame(width: 1)
        }
        .frame(width: 220)
        .background(Tok.surface)
        .wfRect("media.sb")
    }

    private func header(_ text: String, rectID: String) -> some View {
        SectionLabel(text).frame(maxWidth: .infinity, alignment: .leading).wfRect(rectID, size: 11, weight: 600)
    }

    private func row(_ entry: MediaBinCategories.Entry, id: String) -> some View {
        MediaSidebarRow(symbol: Self.symbol(entry.kind), title: entry.title, count: "\(entry.count)",
                        selected: media.kindFilter == entry.kind && app.ui.binFolderID == nil, rectID: id) {
            media.kindFilter = entry.kind; app.ui.binFolderID = nil
        }
    }

    /// MEDIA-010: the hot folders the bin follows, each a source of its own: a group of the list.
    @ViewBuilder private var folders: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                SectionLabel("Folders")
                Spacer()
                Button { app.addHotFolder() } label: { Image(systemName: "plus").font(.wf(12)).frame(width: 16, height: 16) }.buttonStyle(.plain).foregroundStyle(Tok.muted)
                    .help("Point the bin at a folder: its videos, pictures and sound appear here and follow the folder")
                    .accessibilityLabel("Add a folder")
            }
            .padding(.bottom, 6)
            if let hot = app.hotFolders, !hot.folders.isEmpty {
                ForEach(hot.folders) { state in
                    let word = state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering" : "\(state.items.count)")
                    MediaSidebarRow(symbol: state.status == .ok ? "folder" : "exclamationmark.triangle", title: state.folder.name, count: word,
                                    selected: app.ui.binFolderID == state.id, tint: state.status == .ok ? nil : Tok.warning, rectID: "media.extra.folder",
                                    accessibility: "Folder \(state.folder.name), \(state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering, last list kept" : "\(state.items.count) items"))") {
                        app.ui.binFolderID = state.id
                    }
                }
            } else {
                Text("No folders. Add one with +.").font(.wfSmall).foregroundStyle(Tok.muted).padding(.horizontal, 8)
            }
        }
    }

    private static func symbol(_ kind: MediaKind?) -> String {
        switch kind { case nil: "square.grid.2x2"; case .video?: "film"; case .image?: "photo"; case .audio?: "music.note" }
    }
}

// MARK: Centre

private struct MediaCentre: View {
    let app: AppModel
    @Bindable var media: MediaModel
    @Binding var listMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            MediaBinPanel(app: app, media: media, listMode: listMode)
            MediaStrip(app: app, media: media, preview: app.binPreview)
        }
    }

    /// The design's `.bar`: padding 8 x 14, the title (17 / 700), then Import, the layer choice and the grid / list switch at the right.
    private var bar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(MediaBinCategories.title(for: media.kindFilter)).font(.wf(17, .bold)).lineLimit(1).wfLine(22)
                    .wfRect("media.bar.title", size: 17, weight: 700)
                // The owner's request (2026-11-21): every clear as an icon button, after the title.
                Rectangle().fill(Tok.border).frame(width: 1, height: 16).padding(.horizontal, 4)
                MediaClearButtons(app: app)
                Spacer(minLength: 8)
                Button { app.chooseMedia() } label: {
                    HStack(spacing: 6) { Image(systemName: "plus").frame(width: 15, height: 15); Text("Import…").wfLine() }
                }
                .buttonStyle(HeaderButtonStyle())
                .wfRect("media.bar.import", size: 12, weight: 500, radius: Radius.md)
                .help("Add pictures, videos and sound to the bin (or drop files here)")
                // UI-003: the same choice as the Show dock. It decides what a double-click on a tile does.
                WFSegmented(items: MediaLayerChoice.allCases.map { .init(value: $0, title: $0 == .background ? "\($0.title) layer" : $0.title, label: "\($0.title) layer") },
                            selection: Binding(get: { app.ui.dockLayer }, set: { app.ui.dockLayer = $0 }),
                            accessibilityName: "Layer a double-click acts on", rectID: "media.bar.layer", outerPadding: 0)
                    .help("Double-click a tile to send it live: behind the words, or over them. A single click only selects it and shows it in the player. Drag a tile onto a slide to give that slide its own background. Right-click for more.")
                WFSegmented(items: [.init(value: false, symbol: "square.grid.2x2", label: "Grid"), .init(value: true, symbol: "list.bullet", label: "List")],
                            selection: $listMode, accessibilityName: "View", rectID: "media.bar.view", outerPadding: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Rectangle().fill(Tok.border).frame(height: 1)
        }
        .wfRect("media.bar")
    }
}
