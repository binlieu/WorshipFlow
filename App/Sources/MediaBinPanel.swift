// MEDIA-001 (MEDIA-01): the media bin. A grid of thumbnails with a kind filter, an Add button, drop of files onto the
// panel and a context menu per item. The decisions live in `MediaModel`; this view only shows and forwards.
import SwiftUI
import UniformTypeIdentifiers
import Domain
import OperatorCore

struct MediaBinPanel: View {
    let app: AppModel
    @Bindable var media: MediaModel
    @State private var renaming: MediaAsset?
    @State private var renameText = ""
    @State private var targeted = false
    /// FIX-G: a removal that would leave slides without their own background waits for the operator's answer.
    @State private var pendingRemoval: (asset: MediaAsset, message: String)?
    private var selected: UUID? { app.ui.binSelection }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MediaBinCategories.title(for: media.kindFilter)).font(.system(size: 20, weight: .bold))
                Spacer()
                // UI-003: the same choice as the Show dock. It decides what a double-click on a tile does.
                HStack(spacing: 0) {
                    ForEach(MediaLayerChoice.allCases) { choice in
                        let on = app.ui.dockLayer == choice
                        Button { app.ui.dockLayer = choice } label: {
                            Text(choice.title).font(.system(size: 12, weight: on ? .semibold : .regular)).fixedSize()
                                .padding(.horizontal, 9).frame(height: 22).foregroundStyle(on ? Tok.text : Tok.muted)
                                .background(on ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                        }.buttonStyle(.plain).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(2).background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.border, lineWidth: 1))
                .help("Double-click a tile to send it live: behind the words, or over them. A single click only selects it and shows it in the player.")
                Button { app.chooseMedia() } label: { Label("Import…", systemImage: "plus") }
                    .buttonStyle(HeaderButtonStyle())
                    .help("Add pictures and videos to the bin (or drop files here)")
            }
            if let folder = currentFolder { folderHeader(folder) }
            if shownAssets.isEmpty {
                Text(media.assets.isEmpty
                     ? "The bin is empty. Add pictures and videos with the button above, or drop files here. The bin keeps a reference to each file; your files are never moved or deleted."
                     : "Nothing of this kind in the bin.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(shownAssets) { asset in
                        MediaTile(asset: asset, isBackground: media.layers.background?.selection.assetID == asset.id,
                                  isForeground: media.layers.foreground?.selection.assetID == asset.id)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(live(asset) ? Tok.liveFill : (selected == asset.id ? Tok.blue : .clear), lineWidth: 2))
                            .contentShape(Rectangle())
                            .contextMenu { menu(for: asset) }
                            // MEDIA-010: a single click selects and shows it in the sidebar player; a double click also sends it live.
                            .onTapGesture(count: 2) {
                                let tap = MediaBinInteraction.tap(count: 2, asset: asset, layer: app.ui.dockLayer)
                                app.selectBinItem(tap.select)
                                if let action = tap.sendLive { app.performDockAction(action) }
                            }
                            .onTapGesture { app.selectBinItem(MediaBinInteraction.tap(count: 1, asset: asset, layer: app.ui.dockLayer).select) }
                            .draggable(SlideBackgroundDrop.dragText(for: asset.id))
                            .accessibilityAddTraits(selected == asset.id ? [.isSelected, .isButton] : .isButton)
                            .accessibilityAction { app.selectBinItem(asset.id) }
                            .accessibilityAction(named: "Set as background") { media.setBackground(asset.id) }
                            .accessibilityAction(named: "Play in foreground") { media.playForeground(asset.id) }
                    }
                }
                if let chosen = selected.flatMap({ media.asset($0) }) {
                    HStack(spacing: 6) {
                        Text(chosen.name).font(.caption.bold()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Live background") { media.setBackground(chosen.id) }
                            .disabled(chosen.kind == .audio).controlSize(.small)
                        Button("Live foreground") { media.playForeground(chosen.id) }
                            .disabled(chosen.kind == .audio || !media.showIsLive).controlSize(.small)
                            .help(media.showIsLive ? "Play over the slides" : "Take a slide live first")
                    }
                }
            }
            if media.hasLiveBackgroundOverride {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary)
                    Text("Live background from the bin: \(media.layers.background.flatMap { media.asset($0.selection.assetID)?.name } ?? "")")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Button("Use the slide's own background") { media.dropBackgroundOverride() }.controlSize(.small)
                        .help("Drop the live override: each slide's own background (or the theme's) shows again")
                }
            }
            Text("A single click selects an item and shows it in the player. A double click sends it live, as the layer choice above says. Drag a tile onto a slide to give that slide its own background. Right-click for more.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            app.addMedia(files)
            return true
        } isTargeted: { targeted = $0 }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                if let asset = renaming { Task { await media.rename(asset.id, to: renameText) } }
            }
        }
        .alert("Remove from the media bin?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { if let asset = pendingRemoval?.asset { Task { await media.remove(asset.id) } } }
        } message: { Text(pendingRemoval?.message ?? "") }
    }

    /// FIX-G: tells which slides use the item as their own background before removing it; with none it removes at once.
    private func requestRemoval(_ asset: MediaAsset) async {
        let impact = await media.removalImpact(asset.id)
        if let message = impact.message { pendingRemoval = (asset, message) } else { await media.remove(asset.id) }
    }

    /// MEDIA-010: the hot folder the sidebar chose, if any; the grid then shows its items instead of the bin's.
    private var currentFolder: HotFolderState? { app.ui.binFolderID.flatMap { app.hotFolders?.state(of: $0) } }

    private var shownAssets: [MediaAsset] {
        guard let folder = currentFolder else { return media.visibleAssets }
        guard let kind = media.kindFilter else { return folder.items }
        return folder.items.filter { $0.kind == kind }
    }

    private func folderHeader(_ state: HotFolderState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.status == .ok ? "folder" : "exclamationmark.triangle")
                    .foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                Text(state.folder.path).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(Tok.muted)
                Spacer()
                if state.status == .missing {
                    Button("Point to the folder again…") { app.repointHotFolder(state.id) }.controlSize(.small)
                } else {
                    Menu("Play folder") {
                        Button("On the live background") { media.playFolder(state.id, on: .background) }
                        Button("Over the words") { media.playFolder(state.id, on: .foreground) }.disabled(!media.showIsLive)
                    }
                    .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                    .help("Play this folder's videos one after another in name order, and again from the first")
                }
                if media.playingFolderID == state.id { Button("Stop folder") { media.stopFolder() }.controlSize(.small) }
                Button("Stop following") { Task { await app.hotFolders?.remove(state.id); app.ui.binFolderID = nil } }.controlSize(.small)
                    .help("The bin forgets this folder. Its files are not touched.")
            }
            if state.status == .missing {
                Text("This folder cannot be found (moved, renamed or its drive is not connected). The show is not affected.")
                    .font(.caption).foregroundStyle(Tok.warning)
            } else if state.status == .unreachable {
                // FIX-G: the last list stays; the folder could not be read this time.
                Text("This folder is not answering right now (a drive or network share that is slow or disconnected). The last list is kept and the show is not affected.")
                    .font(.caption).foregroundStyle(Tok.warning)
            }
            if state.status != .missing, !state.heldBack.isEmpty {
                Text("\(state.heldBack.count) file\(state.heldBack.count == 1 ? "" : "s") still being copied: \(state.heldBack.prefix(3).joined(separator: ", ")). Shown when complete.")
                    .font(.caption).foregroundStyle(Tok.muted)
            }
            if !state.unreadable.isEmpty {
                Text("\(state.unreadable.count) file\(state.unreadable.count == 1 ? "" : "s") could not be read and \(state.unreadable.count == 1 ? "is" : "are") tried again now and then: \(state.unreadable.prefix(3).joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(Tok.muted)
            }
            if let notice = state.notice { Text(notice).font(.caption).foregroundStyle(Tok.warning) }
        }
    }

    /// Red only while it is on screen now: the background of a live show, or a playing clip.
    private func live(_ asset: MediaAsset) -> Bool {
        media.showIsLive && (media.layers.background?.selection.assetID == asset.id || media.layers.foreground?.selection.assetID == asset.id)
    }

    @ViewBuilder
    private func menu(for asset: MediaAsset) -> some View {
        if asset.kind != .audio {
            Button("Set as background") { media.setBackground(asset.id) }
            Button("Play in foreground") { media.playForeground(asset.id) }
                .disabled(!media.showIsLive)
        }
        if media.layers.background?.selection.assetID == asset.id {
            Button("Use the slide's own background") { media.dropBackgroundOverride() }
        }
        Divider()
        Button("Rename…") { renameText = asset.name; renaming = asset }
        Button("Remove from bin") { Task { await requestRemoval(asset) } }.disabled(media.assets.contains { $0.id == asset.id } == false)
    }
}

/// One thumbnail with its name, duration and what it is currently used for.
struct MediaTile: View {
    let asset: MediaAsset
    let isBackground: Bool
    let isForeground: Bool
    @State private var result: MediaThumbnails.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                Color(white: 0.16)
                switch result {
                case .image(let picture)?:
                    Image(decorative: picture.image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                case .failed?:
                    Image(systemName: asset.kind == .audio ? "waveform" : "exclamationmark.triangle")
                        .font(.title2).foregroundStyle(.secondary)
                case nil:
                    ProgressView().controlSize(.small)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .bottomTrailing) {
                if let d = asset.duration, asset.kind != .image {
                    Text(Self.clock(d)).font(.wfMonoData).padding(.horizontal, 4)
                        .background(.black.opacity(0.6)).foregroundStyle(.white).padding(3)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if isBackground { badge("BACKGROUND", Tok.blue) }
                    if isForeground { badge("PLAYING", Tok.liveFill) }
                }.padding(3)
            }
            Text(asset.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .task(id: asset.path) { result = await MediaThumbnails.shared.thumbnail(for: asset) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name), \(asset.kind.rawValue)\(isBackground ? ", background" : "")\(isForeground ? ", playing" : "")")
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
            .background(color, in: Capsule()).foregroundStyle(.white)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
