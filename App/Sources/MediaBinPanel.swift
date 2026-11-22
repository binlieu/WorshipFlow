// MEDIA-001 (MEDIA-01), UI-005d: the media bin. The design's grid (5 equal columns, padding 14, gaps 12 and 14; each tile a 16:9
// picture, a kind chip, a duration and a caption) or a list, drop of files onto the panel and a context menu per item. The decisions
// live in `MediaModel`; this view only shows and forwards. The header bar (title, Import, layer choice) is drawn by `MediaModeView`.
import SwiftUI
import UniformTypeIdentifiers
import Domain
import OperatorCore

struct MediaBinPanel: View {
    let app: AppModel
    @Bindable var media: MediaModel
    var listMode = false
    @State private var renaming: MediaAsset?
    @State private var renameText = ""
    /// UI-006d: "New collection..." from a tile's menu: the tile waiting to go in, and the name being typed.
    @State private var newCollectionFor: MediaAsset?
    @State private var newCollectionName = ""
    /// FIX-G: a removal that would leave slides without their own background waits for the operator's answer.
    @State private var pendingRemoval: (asset: MediaAsset, message: String)?
    private var selected: UUID? { app.ui.binSelection }

    /// The design's grid: `repeat(5, 1fr)` with a 12 pt column gap, a 14 pt row gap and 14 pt around.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        let _ = BodyProbe.hit("MediaBinPanel")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let folder = currentFolder { folderHeader(folder) }
                if shownAssets.isEmpty {
                    Text(media.assets.isEmpty
                         ? "The bin is empty. Add pictures and videos with the button above, or drop files here. The bin keeps a reference to each file; your files are never moved or deleted."
                         : "Nothing of this kind in the bin.")
                        .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else if listMode {
                    LazyVStack(spacing: 2) {
                        ForEach(shownAssets) { asset in
                            MediaListRow(asset: asset, selected: selected == asset.id, live: live(asset), offline: media.offlineIDs.contains(asset.id))
                                .modifier(Interaction(panel: self, asset: asset))
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(Array(shownAssets.enumerated()), id: \.element.id) { index, asset in
                            MediaTile(index: index, asset: asset, isBackground: media.layerParts.background?.selection.assetID == asset.id,
                                      isForeground: media.layerParts.foreground?.selection.assetID == asset.id,
                                      isSelected: selected == asset.id, isLive: live(asset), isOffline: media.offlineIDs.contains(asset.id))
                                .modifier(Interaction(panel: self, asset: asset))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .wfRect("media.grid")
        }
        .frame(maxHeight: .infinity)
        .onAppear { app.ui.binColumns = 5 }      // FIX-I item 2: the grid always has five columns, for Up and Down
        .simultaneousGesture(TapGesture().onEnded { app.ui.keySectionEvent(.clickedMediaBin) })
        .fileDropTarget(color: .accentColor, radius: 6) { urls in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            app.addMedia(files)
            return true
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                if let asset = renaming { Task { await media.rename(asset.id, to: renameText) } }
            }
        }
        .alert("New collection", isPresented: Binding(get: { newCollectionFor != nil }, set: { if !$0 { newCollectionFor = nil } })) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let asset = newCollectionFor { media.createCollection(newCollectionName, adding: [asset.id]) }
            }
        } message: { Text("A collection is a list of items from the bin. The files are not moved or copied.") }
        .alert("Remove from the media bin?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { if let asset = pendingRemoval?.asset { Task { await media.remove(asset.id) } } }
        } message: { Text(pendingRemoval?.message ?? "") }
    }

    /// What a tile and a list row share: clicks, drag, context menu and the accessibility actions.
    private struct Interaction: ViewModifier {
        let panel: MediaBinPanel
        let asset: MediaAsset
        func body(content: Content) -> some View {
            let app = panel.app, media = panel.media
            content
                .contentShape(Rectangle())
                .contextMenu { panel.menu(for: asset) }
                // MEDIA-010: a single click selects and shows it in the strip's player; a double click also sends it live.
                .onTapGesture(count: 2) {
                    let tap = MediaBinInteraction.tap(count: 2, asset: asset, layer: app.ui.dockLayer)
                    app.selectBinItem(tap.select)
                    if let action = tap.sendLive { app.performDockAction(action) }
                }
                .onTapGesture { app.selectBinItem(MediaBinInteraction.tap(count: 1, asset: asset, layer: app.ui.dockLayer).select) }
                .draggable(SlideBackgroundDrop.dragText(for: asset.id)) { DragChip(text: asset.name, symbol: asset.dragSymbol) }
                .accessibilityAddTraits(panel.selected == asset.id ? [.isSelected, .isButton] : .isButton)
                .accessibilityAction { app.selectBinItem(asset.id) }
                .accessibilityAction(named: "Set as background") { media.setBackground(asset.id) }
                .accessibilityAction(named: "Play in foreground") { media.playForeground(asset.id) }
        }
    }

    /// UI-006d: put the item in a collection (a list of items from the bin) or take it out of the one that is open. Files never move.
    @ViewBuilder
    private func collectionItems(for asset: MediaAsset) -> some View {
        Menu("Add to collection") {
            ForEach(media.collections.items) { collection in
                Button(collection.assetIDs.contains(asset.id) ? "\(collection.name) \u{2713}" : collection.name) { media.addToCollection([asset.id], collection: collection.id) }
                    .disabled(collection.assetIDs.contains(asset.id))
            }
            if !media.collections.items.isEmpty { Divider() }
            Button("New collection\u{2026}") { newCollectionName = ""; newCollectionFor = asset }
        }
        if let open = media.collectionFilter, let collection = media.collections.collection(open) {
            Button("Remove from \"\(collection.name)\"") { media.removeFromCollection([asset.id], collection: open) }
        }
    }

    /// FIX-G: tells which slides use the item as their own background before removing it; with none it removes at once.
    private func requestRemoval(_ asset: MediaAsset) async {
        let impact = await media.removalImpact(asset.id)
        if let message = impact.message { pendingRemoval = (asset, message) } else { await media.remove(asset.id) }
    }

    /// MEDIA-010: the hot folder the sidebar chose, if any; the grid then shows its items instead of the bin's.
    private var currentFolder: HotFolderState? { app.ui.binFolderID.flatMap { app.hotFolders?.state(of: $0) } }

    private var shownAssets: [MediaAsset] { app.visibleBinAssets }

    private func folderHeader(_ state: HotFolderState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.status == .ok ? "folder" : "exclamationmark.triangle")
                    .foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                Text(state.folder.path).font(.wfSmall).lineLimit(1).truncationMode(.middle).foregroundStyle(Tok.muted)
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
                    .font(.wfSmall).foregroundStyle(Tok.warning)
            } else if state.status == .unreachable {
                // FIX-G: the last list stays; the folder could not be read this time.
                Text("This folder is not answering right now (a drive or network share that is slow or disconnected). The last list is kept and the show is not affected.")
                    .font(.wfSmall).foregroundStyle(Tok.warning)
            }
            if state.status != .missing, !state.heldBack.isEmpty {
                Text("\(state.heldBack.count) file\(state.heldBack.count == 1 ? "" : "s") still being copied: \(state.heldBack.prefix(3).joined(separator: ", ")). Shown when complete.")
                    .font(.wfSmall).foregroundStyle(Tok.muted)
            }
            if !state.unreadable.isEmpty {
                Text("\(state.unreadable.count) file\(state.unreadable.count == 1 ? "" : "s") could not be read and \(state.unreadable.count == 1 ? "is" : "are") tried again now and then: \(state.unreadable.prefix(3).joined(separator: ", ")).")
                    .font(.wfSmall).foregroundStyle(Tok.muted)
            }
            if let notice = state.notice { Text(notice).font(.wfSmall).foregroundStyle(Tok.warning) }
        }
    }

    /// Red only while it is on screen now: the background of a live show, or a playing clip.
    private func live(_ asset: MediaAsset) -> Bool {
        media.showIsLive && (media.layerParts.background?.selection.assetID == asset.id || media.layerParts.foreground?.selection.assetID == asset.id)
    }

    @ViewBuilder
    fileprivate func menu(for asset: MediaAsset) -> some View {
        if asset.kind != .audio {
            Button("Set as background") { media.setBackground(asset.id) }
            Button("Play in foreground") { media.playForeground(asset.id) }
                .disabled(!media.showIsLive)
        }
        if media.layerParts.background?.selection.assetID == asset.id {
            Button("Use the slide's own background") { media.dropBackgroundOverride() }
        }
        Divider()
        collectionItems(for: asset)
        if media.offlineIDs.contains(asset.id) { Button("Locate\u{2026}") { app.locateOfflineMedia(asset) } }
        Divider()
        Button("Add to playlist") { Task { await app.workspace?.addMediaItem(MediaItemSpec(assetID: asset.id, name: asset.name, kind: asset.kind)) } }
        Button("Rename…") { renameText = asset.name; renaming = asset }
        Button("Remove from bin") { Task { await requestRemoval(asset) } }.disabled(media.assets.contains { $0.id == asset.id } == false)
    }
}

/// One tile of the design: a 16:9 picture (radius 4) with a kind chip top left and a duration bottom right, its caption under it
/// (11 / 600). The ring follows the slide thumbnails: blue 2 pt for the chosen one, red 3 pt only while it is on screen now.
struct MediaTile: View {
    var index = 0
    let asset: MediaAsset
    let isBackground: Bool
    let isForeground: Bool
    var isSelected = false
    var isLive = false
    /// UI-006d: the file cannot be read now (a disk not connected, a file moved). A warning mark; Locate... is in the menu and the callout.
    var isOffline = false
    @State private var result: MediaThumbnails.Result?

    var body: some View {
        let _ = BodyProbe.hit("MediaTile")
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { picture }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .wfRect("media.tile.\(index).thumb", radius: Radius.sm)
                .overlay(alignment: .topLeading) {
                    Image(systemName: asset.kind == .video ? "film" : (asset.kind == .audio ? "music.note" : "photo")).font(.wf(11)).foregroundStyle(.white)
                        .frame(width: 12, height: 12).padding(2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.sm))
                        .wfRect("media.tile.\(index).kind", radius: Radius.sm).padding(5)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let d = asset.duration, asset.kind != .image {
                        Text(Self.clock(d)).font(.wfMono(10, .semibold)).wfLine(14).padding(.horizontal, 4)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.xs)).foregroundStyle(.white)
                            .wfRect("media.tile.\(index).dur", size: 10, weight: 600, radius: Radius.xs).padding(5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isOffline {
                        Image(systemName: "exclamationmark.triangle.fill").font(.wf(11)).foregroundStyle(Tok.warning)
                            .frame(width: 12, height: 12).padding(2)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.sm)).padding(5)
                            .help("This file cannot be read now. Right-click for Locate\u{2026}")
                            .wfRect("media.extra.offline")
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // What the tile is used for now (the owner's extra: the design shows only the ring).
                    VStack(alignment: .leading, spacing: 2) {
                        if isBackground { ThumbTag(text: "BACKGROUND", kind: .preview).wfRect("media.extra.tag.bg") }
                        if isForeground { ThumbTag(text: "PLAYING", kind: .live).wfRect("media.extra.tag.fg") }
                    }.padding(5)
                }
                .wfThumbState(radius: Radius.sm, preview: isSelected, live: isLive)
            Text(asset.name).font(.wf(11, .semibold)).lineLimit(1).truncationMode(.middle).wfLine().foregroundStyle(Tok.text)
                .wfRect("media.tile.\(index).name", size: 11, weight: 600)
        }
        .wfRect("media.tile.\(index)")
        .task(id: asset.path) { result = await MediaThumbnails.shared.thumbnail(for: asset) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name), \(asset.kind.rawValue)\(isBackground ? ", background" : "")\(isForeground ? ", playing" : "")\(isOffline ? ", offline: the file cannot be read" : "")")
    }

    @ViewBuilder private var picture: some View {
        ZStack {
            Tok.surface3
            switch result {
            case .image(let picture)?:
                Image(decorative: picture.image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            case .failed?:
                Image(systemName: asset.kind == .audio ? "waveform" : "exclamationmark.triangle").font(.wfTitle2).foregroundStyle(Tok.muted)
            case nil:
                if asset.kind == .audio { Image(systemName: "waveform").font(.wfTitle2).foregroundStyle(Tok.muted) } else { ProgressView().controlSize(.small) }
            }
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The list view's row: kind icon, name, kind and length. No design draws it; it uses the list rows' look of the other modes.
struct MediaListRow: View {
    let asset: MediaAsset
    let selected: Bool
    let live: Bool
    var offline = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: asset.kind == .video ? "film" : (asset.kind == .audio ? "music.note" : "photo")).font(.wf(13)).frame(width: 15, height: 15)
            Text(asset.name).font(.wf(13)).lineLimit(1).truncationMode(.middle).wfLine()
            if offline { Image(systemName: "exclamationmark.triangle.fill").font(.wf(11)).foregroundStyle(Tok.warning).help("This file cannot be read now") }
            Spacer(minLength: 8)
            Text(asset.kind == .video ? "Video" : (asset.kind == .audio ? "Sound" : "Picture")).font(.wf(11)).foregroundStyle(Tok.muted).wfLine()
            Text(asset.duration.map(MediaTile.clock) ?? "").font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine().frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay { if live { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Tok.liveFill, lineWidth: 2) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name), \(asset.kind.rawValue)\(live ? ", on screen now" : "")\(offline ? ", offline: the file cannot be read" : "")")
    }
}
