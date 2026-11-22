// UI-001 / ADR-0007: the Edit, Media, Stage, Cues and Screens modes. Each re-homes panels that already worked; none
// of them carries new logic.
import SwiftUI
import Domain
import OperatorCore

// MARK: Edit

// UI-005c: EditModeView moved to EditMode.swift.

// MARK: Media

struct MediaModeView: View {
    let app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let media = app.media { sidebar(media).frame(width: 220) ; Divider() }
            ScrollView {
                if let media = app.media {
                    MediaBinPanel(app: app, media: media).padding(Space.s5)
                } else {
                    Text("The media bin is not available.").foregroundStyle(Tok.muted).padding(Space.s5)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MEDIA-010: the player for the item selected in the bin, then the audio list.
                    if let preview = app.binPreview { BinPlayerPanel(app: app, preview: preview) ; Divider() }
                    if let audio = app.audio { AudioPanel(audio: audio).padding(Space.s5) }
                }
            }
            .frame(width: 380)
            .background(Tok.surface)
        }
    }

    /// The design's "Media bin" and "Audio" lists. Each row is the kind filter the bin always had, with its count.
    private func sidebar(_ media: MediaModel) -> some View {
        let entries = MediaBinCategories.entries(kinds: media.assets.map(\.kind))
        return VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("Media bin").padding(.bottom, Space.s2)
            ForEach(entries.filter { !$0.isAudio }, id: \.title) { row($0, media) }
            SectionLabel("Audio").padding(.top, Space.s5).padding(.bottom, Space.s2)
            ForEach(entries.filter(\.isAudio), id: \.title) { row($0, media) }
            folders
            Spacer()
        }
        .padding(Space.s4)
        .background(Tok.surface)
    }

    private func row(_ entry: MediaBinCategories.Entry, _ media: MediaModel) -> some View {
        let selected = media.kindFilter == entry.kind && app.ui.binFolderID == nil
        return Button { media.kindFilter = entry.kind; app.ui.binFolderID = nil } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: Self.symbol(entry.kind)).frame(width: 18).foregroundStyle(Tok.muted)
                Text(entry.title).font(.wf(14))
                Spacer()
                Text("\(entry.count)").font(.wf(12)).foregroundStyle(Tok.muted)
            }
            .padding(.horizontal, Space.s3).frame(height: 30)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(entry.count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// MEDIA-010: the hot folders the bin follows, each a source of its own.
    @ViewBuilder private var folders: some View {
        HStack {
            SectionLabel("Folders")
            Spacer()
            Button { app.addHotFolder() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help("Point the bin at a folder: its videos, pictures and sound appear here and follow the folder")
                .accessibilityLabel("Add a folder")
        }
        .padding(.top, Space.s5).padding(.bottom, Space.s2)
        if let hot = app.hotFolders, !hot.folders.isEmpty {
            ForEach(hot.folders) { state in
                let selected = app.ui.binFolderID == state.id
                Button { app.ui.binFolderID = state.id } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: state.status == .ok ? "folder" : "exclamationmark.triangle")
                            .frame(width: 18).foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                        Text(state.folder.name).font(.wf(14)).lineLimit(1)
                        Spacer()
                        Text(state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering" : "\(state.items.count)")).font(.wf(12))
                            .foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                    }
                    .padding(.horizontal, Space.s3).frame(height: 30)
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Folder \(state.folder.name), \(state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering, last list kept" : "\(state.items.count) items"))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        } else {
            Text("No folders. Add one with +.").font(.wfSmall).foregroundStyle(Tok.muted)
        }
    }

    private static func symbol(_ kind: MediaKind?) -> String {
        switch kind { case nil: "square.grid.2x2"; case .video?: "film"; case .image?: "photo"; case .audio?: "music.note" }
    }
}

// MARK: Stage

struct StageModeView: View {
    let app: AppModel

    var body: some View {
        if let stage = app.stage {
            StageEditorView(app: app, stage: stage)
        } else {
            Text("Stage layouts are not available.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
