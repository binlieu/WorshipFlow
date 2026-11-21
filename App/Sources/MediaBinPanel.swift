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
    @State private var selected: UUID?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Media bin").font(.headline)
                Spacer()
                Button { app.chooseMedia() } label: { Label("Add…", systemImage: "plus") }
                    .help("Add pictures and videos to the bin (or drop files here)")
            }
            Picker("Show", selection: $media.kindFilter) {
                Text("All").tag(MediaKind?.none)
                Text("Videos").tag(MediaKind?.some(.video))
                Text("Pictures").tag(MediaKind?.some(.image))
                Text("Sound").tag(MediaKind?.some(.audio))
            }
            .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Show kind")
            if media.visibleAssets.isEmpty {
                Text(media.assets.isEmpty
                     ? "The bin is empty. Add pictures and videos with the button above, or drop files here. The bin keeps a reference to each file; your files are never moved or deleted."
                     : "Nothing of this kind in the bin.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(media.visibleAssets) { asset in
                        MediaTile(asset: asset, isBackground: media.layers.background?.selection.assetID == asset.id,
                                  isForeground: media.layers.foreground?.selection.assetID == asset.id)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected == asset.id ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                            .contextMenu { menu(for: asset) }
                            .onTapGesture(count: 2) { selected = asset.id; if asset.kind != .audio { media.setBackground(asset.id) } }
                            .onTapGesture { selected = asset.id }
                            .accessibilityAddTraits(selected == asset.id ? [.isSelected, .isButton] : .isButton)
                            .accessibilityAction { selected = asset.id }
                            .accessibilityAction(named: "Set as background") { media.setBackground(asset.id) }
                            .accessibilityAction(named: "Play in foreground") { media.playForeground(asset.id) }
                    }
                }
                if let chosen = selected.flatMap({ media.asset($0) }) {
                    HStack(spacing: 6) {
                        Text(chosen.name).font(.caption.bold()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Set as background") { media.setBackground(chosen.id) }
                            .disabled(chosen.kind == .audio).controlSize(.small)
                        Button("Play in foreground") { media.playForeground(chosen.id) }
                            .disabled(chosen.kind == .audio || !media.showIsLive).controlSize(.small)
                            .help(media.showIsLive ? "Play over the slides" : "Take a slide live first")
                    }
                }
            }
            if media.layers.background != nil {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary)
                    Text("Background: \(media.layers.background.flatMap { media.asset($0.selection.assetID)?.name } ?? "")")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Button("Clear background") { media.clearBackground() }.controlSize(.small)
                }
            }
            Text("Double-click sets the background. Right-click for more. Backgrounds show on screens whose theme uses a motion background.")
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
    }

    @ViewBuilder
    private func menu(for asset: MediaAsset) -> some View {
        if asset.kind != .audio {
            Button("Set as background") { media.setBackground(asset.id) }
            Button("Play in foreground") { media.playForeground(asset.id) }
                .disabled(!media.showIsLive)
        }
        if media.layers.background?.selection.assetID == asset.id {
            Button("Clear background") { media.clearBackground() }
        }
        Divider()
        Button("Rename…") { renameText = asset.name; renaming = asset }
        Button("Remove from bin") { Task { await media.remove(asset.id) } }
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
                    Text(Self.clock(d)).font(.caption2.monospacedDigit()).padding(.horizontal, 4)
                        .background(.black.opacity(0.6)).foregroundStyle(.white).padding(3)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if isBackground { badge("BACKGROUND", .blue) }
                    if isForeground { badge("PLAYING", .red) }
                }.padding(3)
            }
            Text(asset.name).font(.caption).lineLimit(1).truncationMode(.middle)
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
