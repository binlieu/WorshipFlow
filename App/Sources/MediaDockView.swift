// UI-003 Part 1: the media dock under the slide grid in Show, and the media controller row under its thumbnails. The
// decisions (tabs, what a click does, the rings, which clip the controller drives) live in OperatorCore; this view only
// draws them and forwards clicks to `MediaModel` and `AudioModel`. Red appears only on a tile that is on screen now.
import SwiftUI
import UniformTypeIdentifiers
import Domain
import OperatorCore

/// The dock: a resizable, collapsible pane. Height and collapsed state are remembered in the library's settings.
struct MediaDockView: View {
    let app: AppModel
    @Bindable var media: MediaModel
    let audio: AudioModel?
    /// The height of the column the dock sits in, so the dock never takes more than half of it.
    let available: Double
    @State private var dragStart: Double?
    @State private var dragHeight: Double?
    @State private var selected: UUID?
    @State private var targeted = false
    @State private var stripWidth: CGFloat = 812

    private let headerHeight: CGFloat = 40

    var body: some View {
        let state = app.mediaDock
        let height = MediaDock.clampedHeight(dragHeight ?? state.height, available: available)
        VStack(spacing: 0) {
            if !state.isCollapsed { resizeHandle(current: state.height) }
            Rectangle().fill(Tok.border).frame(height: 1)
            header(collapsed: state.isCollapsed)
            if !state.isCollapsed {
                // The design's strip: seven tiles fill the width (padding 10 x 14 x 6, gap 10); its height follows from the tile width.
                strip(height: height - headerHeight)
            }
            // The controller stays even when the dock is folded away: a clip must always be stoppable from Show.
            MediaControllerRow(app: app, media: media, audio: audio)
        }
        .background(Tok.surface)
        .overlay(targeted ? RoundedRectangle(cornerRadius: 4).stroke(Tok.blue, lineWidth: 2) : nil)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            app.addMedia(files)
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media bin")
    }

    // MARK: Pieces

    private func resizeHandle(current: Double) -> some View {
        Color.clear.frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStart ?? current
                    dragStart = start
                    dragHeight = MediaDock.clampedHeight(start - value.translation.height, available: available)
                }
                .onEnded { _ in
                    if let h = dragHeight { app.setMediaDock(height: h) }
                    dragStart = nil
                    dragHeight = nil
                })
            .accessibilityLabel("Resize the media bin")
            .accessibilityAddTraits(.isButton)
    }

    private func header(collapsed: Bool) -> some View {
        HStack(spacing: 2) {
            SectionLabel("Media bin").fixedSize().padding(.trailing, 4)
            ForEach(MediaDockTab.allCases) { tab in
                WFTabButton(title: tab.title, symbol: Self.symbol(tab), on: app.ui.dockTab == tab) {
                    app.ui.dockTab = tab; if app.mediaDock.isCollapsed { app.setMediaDock(collapsed: false) }
                }
            }
            Spacer(minLength: 4)
            if MediaDock.showsLayerChoice(on: app.ui.dockTab) {
                WFSegmented(items: MediaLayerChoice.allCases.map { .init(value: $0, title: $0 == .background ? "\($0.title) layer" : $0.title, label: "\($0.title) layer") },
                            selection: Binding(get: { app.ui.dockLayer }, set: { app.ui.dockLayer = $0 }), accessibilityName: "Layer a click acts on")
                    .help("What a click on a picture or video does: put it behind the words, or play it over them")
                    .padding(.vertical, 4)
            }
            Button { app.chooseMedia() } label: { Image(systemName: "plus").font(.wf(12)).frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help("Add pictures, videos and sound to the media bin (or drop files here)")
                .accessibilityLabel("Add media files")
            Button { app.setMediaDock(collapsed: !collapsed) } label: { Image(systemName: collapsed ? "chevron.up" : "chevron.down").font(.wf(12)).frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help(collapsed ? "Show the media bin" : "Fold the media bin away")
                .accessibilityLabel(collapsed ? "Show the media bin" : "Fold the media bin away")
        }
        .padding(.horizontal, 10)
        .frame(height: headerHeight)
        .overlay(alignment: .bottom) { if !collapsed { Rectangle().fill(Tok.border).frame(height: 1) } }
    }

    private static func symbol(_ tab: MediaDockTab) -> String {
        switch tab { case .backgrounds: "film.stack"; case .videos: "film"; case .images: "photo"; case .audio: "music.note" }
    }

    @ViewBuilder private func strip(height: CGFloat) -> some View {
        let items = MediaDock.assets(media.assets, tab: app.ui.dockTab)
        if items.isEmpty {
            Text(media.assets.isEmpty
                 ? "The bin is empty. Add pictures, videos and sound with +, or drop files here. Your files are never moved or deleted."
                 : "Nothing of this kind in the bin.")
                .font(.wf(12)).foregroundStyle(Tok.muted)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                .padding(.horizontal, Space.s5)
        } else {
            let tileWidth = max(60, (stripWidth - 28 - 6 * 10) / 7)
            ScrollView(.horizontal, showsIndicators: items.count > 7) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(items) { asset in tile(asset, width: tileWidth) }
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            }
            .frame(height: 10 + tileWidth * 9 / 16 + 3 + 14 + 6)
            .background(GeometryReader { g in
                Color.clear.onAppear { stripWidth = g.size.width }.onChange(of: g.size.width) { _, w in stripWidth = w }
            })
        }
    }

    private func tile(_ asset: MediaAsset, width: CGFloat) -> some View {
        let mark = MediaTileMarks.mark(for: asset, layers: media.layers, showIsLive: media.showIsLive, selected: selected,
                                       soundIsPlaying: audio?.activeCues.contains { $0.assetID == asset.id } ?? false)
        return DockTile(asset: asset, mark: mark, width: width)
            .draggable(SlideBackgroundDrop.dragText(for: asset.id))       // MEDIA-010: drop it on a slide for that slide's own background
            .onTapGesture {
                selected = asset.id
                app.performDockAction(MediaDock.action(for: asset, layer: app.ui.dockLayer))
            }
            .contextMenu {
                Button("Add to playlist") { Task { await app.workspace?.addMediaItem(MediaItemSpec(assetID: asset.id, name: asset.name, kind: asset.kind)) } }
                Divider()
                if asset.kind != .audio {
                    Button("Set as background") { selected = asset.id; media.setBackground(asset.id) }
                    Button("Play in foreground") { selected = asset.id; media.playForeground(asset.id) }
                    if media.layers.background?.selection.assetID == asset.id { Button("Use the slide's own background") { media.dropBackgroundOverride() } }
                } else {
                    Button("Play sound") { selected = asset.id; audio?.play(asset.id) }
                    if audio?.isActive(asset.id) == true { Button("Stop sound") { audio?.stop(asset.id) } }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(asset.name), \(asset.kind.rawValue)")
            .accessibilityValue(Self.word(mark))
            .accessibilityAddTraits(.isButton)
            .help(asset.kind == .audio ? "Play \(asset.name)"
                  : (app.ui.dockLayer == .background ? "Put \(asset.name) behind the words" : "Play \(asset.name) over the words"))
    }

    private static func word(_ mark: MediaTileMark) -> String {
        switch mark { case .live: "on screen now"; case .preview: "chosen, not on screen"; case .playingSound: "sounding"; case .none: "" }
    }
}

/// A thumbnail with the same rings as a slide: idle 1 pt, blue for chosen, red only while it is on screen now (all at a 2 pt offset).
private struct DockTile: View {
    let asset: MediaAsset
    let mark: MediaTileMark
    let width: CGFloat
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
                        .font(.wfTitle2).foregroundStyle(Tok.muted)
                case nil:
                    if asset.kind == .audio { Image(systemName: "waveform").font(.wfTitle2).foregroundStyle(Tok.muted) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: width, height: width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(alignment: .bottomTrailing) {
                if let d = asset.duration, asset.kind != .image {
                    Text(MediaTile.clock(d)).font(.wfMono(9, .semibold)).padding(.horizontal, 3).frame(height: 13)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.xs)).foregroundStyle(.white).padding(4)
                }
            }
            .overlay(alignment: .topLeading) { tag.padding(5) }
            .wfThumbState(radius: 4, preview: mark == .preview, live: mark == .live)
            Text(asset.name).font(.wf(11, .medium)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(Tok.text).frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .task(id: asset.path) { result = await MediaThumbnails.shared.thumbnail(for: asset) }
    }

    @ViewBuilder private var tag: some View {
        switch mark {
        case .live: ThumbTag(text: "LIVE", kind: .live)
        case .preview: ThumbTag(text: "PREVIEW", kind: .preview)
        case .playingSound: Badge(text: "SOUND", style: .outline(Tok.cyan))
        case .none: EmptyView()
        }
    }
}

// MARK: Controller row

/// Restart, play or pause, stop, name, elapsed and remaining, scrubber, loop, mute and volume, and the screens the file
/// is on. It drives the clip over the slide, else the sound cue that started last, else the background video, and is not
/// shown when none is loaded.
struct MediaControllerRow: View {
    let app: AppModel
    @Bindable var media: MediaModel
    let audio: AudioModel?
    @State private var dragging = false
    @State private var dragPosition = 0.0

    private struct Face {
        var name: String
        var kind: String
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var remaining: Double
        var canSeek: Bool
        var restart: () -> Void
        var togglePlay: () -> Void
        var stop: () -> Void
        var seek: (Double) -> Void
        var loops: Loop
        var sound: Sound
        var chips: [String]
    }
    private enum Loop { case toggle(Bool, (Bool) -> Void), always }
    private enum Sound { case clip, cue, background }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            if let face = face() { row(face) }
        }
    }

    private func face() -> Face? {
        let source = MediaController.pick(foregroundLoaded: media.layers.foreground != nil, currentAudioCue: audio?.currentID,
                                          backgroundIsVideo: media.backgroundReadout() != nil)
        switch source {
        case .foregroundClip?:
            guard let r = media.foregroundReadout() else { return nil }
            return Face(name: r.name, kind: "Clip over the words", isPlaying: r.isPlaying, position: r.position, duration: r.duration,
                        remaining: r.remaining, canSeek: r.canSeek,
                        restart: { media.restartForeground() },
                        togglePlay: { r.isPlaying ? media.pause() : media.resume() },
                        stop: { media.stopForeground() }, seek: { media.seek(to: $0) },
                        loops: .toggle(media.foregroundLoops, { media.setForegroundLoops($0) }), sound: .clip,
                        chips: chips(LayerPresence.roles(showing: .slide, screens: app.layerInputs)))
        case .audioCue(let id)?:
            guard let audio, let r = audio.readout(for: id) else { return nil }
            return Face(name: r.name, kind: "Sound", isPlaying: r.isPlaying, position: r.position, duration: r.duration,
                        remaining: r.remaining, canSeek: r.canSeek,
                        restart: { audio.seek(id, to: 0); if !r.isPlaying { audio.resume(id) } },
                        togglePlay: { r.isPlaying ? audio.pause(id) : audio.resume(id) },
                        stop: { audio.stop(id) }, seek: { audio.seek(id, to: $0) },
                        loops: .toggle(audio.loopIDs.contains(id), { audio.setLoops($0, for: id) }), sound: .cue,
                        chips: [audio.devices.first { $0.uid == audio.effectiveDeviceUID }?.name ?? "Default out"])
        case .backgroundLoop?:
            guard let r = media.backgroundReadout() else { return nil }
            return Face(name: r.name, kind: "Background", isPlaying: r.isPlaying, position: r.position, duration: r.duration,
                        remaining: r.remaining, canSeek: r.canSeek,
                        restart: { media.restartBackground() },
                        togglePlay: { r.isPlaying ? media.pauseBackground() : media.resumeBackground() },
                        stop: { media.clearBackground() }, seek: { media.seekBackground(to: $0) },
                        loops: .always, sound: .background,
                        chips: chips(LayerPresence.backgroundMediaRoles(screens: app.layerInputs)))
        case nil:
            return nil
        }
    }

    private func chips(_ roles: [ScreenRole]) -> [String] { roles.map { $0 == .audience ? "AUD" : ($0 == .broadcast ? "BRD" : "STG") } }

    /// "00:11.4": minutes, seconds and tenths, as the design draws the readout.
    private static func tenths(_ seconds: Double) -> String {
        let t = max(0, seconds)
        let whole = Int(t)
        return String(format: "%02d:%02d.%d", whole / 60, whole % 60, Int((t - Double(whole)) * 10))
    }

    private func row(_ f: Face) -> some View {
        HStack(spacing: 8) {
            Button(action: f.restart) { Image(systemName: "backward.end.fill") }
                .buttonStyle(ControllerButtonStyle()).help("Back to the start").accessibilityLabel("Restart \(f.name)")
            Button(action: f.togglePlay) { Image(systemName: f.isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(ControllerButtonStyle(selected: f.isPlaying))
                .help(f.isPlaying ? "Pause" : "Play").accessibilityLabel(f.isPlaying ? "Pause \(f.name)" : "Play \(f.name)")
            Button(action: f.stop) { Image(systemName: "stop.fill") }
                .buttonStyle(ControllerButtonStyle())
                .help(f.kind == "Background" ? "Remove the background" : "Stop and bring the words back")
                .accessibilityLabel("Stop \(f.name)")
            Text(f.name).font(.wf(12, .bold)).lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 60, maxWidth: 170, alignment: .leading)
                .help(f.kind)
                .accessibilityLabel("\(f.name), \(f.kind)")
            Text(Self.tenths(dragging ? dragPosition : f.position)).font(.wfMono(11, .medium))
            WFSlider(value: Binding(get: { dragging ? dragPosition : f.position }, set: { dragPosition = $0 }),
                     range: 0...max(f.duration, 0.1), fill: Tok.cyan) { editing in
                if editing { dragPosition = f.position; dragging = true } else { f.seek(dragPosition); dragging = false }
            }
            .disabled(!f.canSeek).accessibilityLabel("Position in \(f.name)")
            Text("\u{2212}" + Self.tenths(dragging ? max(0, f.duration - dragPosition) : f.remaining))
                .font(.wfMono(11, .medium)).foregroundStyle(Tok.muted)
            loopControl(f)
            soundControl(f)
            ForEach(f.chips, id: \.self) { chip in
                PillTag(text: chip, color: Tok.blue, height: 18, maxWidth: 110)
            }
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)
    }

    @ViewBuilder private func loopControl(_ f: Face) -> some View {
        switch f.loops {
        case .toggle(let on, let set):
            Button { set(!on) } label: {
                HStack(spacing: 5) { Image(systemName: "repeat").font(.wf(11)); Text("Loop").font(.wf(11, .semibold)) }
                    .foregroundStyle(on ? Tok.cyan : Tok.muted).padding(.horizontal, 8).frame(height: 22)
                    .wfOutline(Capsule(style: .circular), stroke: Tok.borderStrong)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(on ? "Looping: it starts again when it ends" : "Play once")
            .accessibilityLabel("Loop \(f.name)").accessibilityValue(on ? "on" : "off")
            .accessibilityAddTraits(.isToggle)
        case .always:
            PillTag(text: "Loop", color: Tok.cyan, height: 22, lead: .symbol("repeat"))
                .help("A background always loops").accessibilityLabel("A background always loops")
        }
    }

    @ViewBuilder private func soundControl(_ f: Face) -> some View {
        switch f.sound {
        case .clip:
            Button { media.setMuted(!media.isMuted) } label: { Image(systemName: media.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                .buttonStyle(.plain).foregroundStyle(Tok.text)
                .help(media.isMuted ? "Unmute the clip's sound" : "Mute the clip's sound").accessibilityLabel(media.isMuted ? "Unmute" : "Mute")
            WFSlider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), range: 0...1, fill: Tok.blue)
                .frame(width: 70).disabled(media.isMuted).accessibilityLabel("Clip volume")
        case .cue:
            if let audio {
                Button { audio.setMuted(!audio.isMuted) } label: { Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(.plain).foregroundStyle(Tok.text)
                    .help(audio.isMuted ? "Unmute the sound" : "Mute the sound").accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")
                WFSlider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), range: 0...1, fill: Tok.blue)
                    .frame(width: 70).disabled(audio.isMuted).accessibilityLabel("Sound volume")
            }
        case .background:
            // MEDIA-010: muted when it starts, and the operator can unmute it. The state shown is the state the player was given.
            let heard = media.backgroundHeardMuted
            Button { media.setBackgroundMuted(!media.isBackgroundMuted) } label: { Image(systemName: heard ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                .buttonStyle(.plain).foregroundStyle(Tok.text)
                .help(media.isBackgroundMuted ? "The background video is muted. Click to unmute it." : (heard ? "Silent while Blackout is on" : "Mute the background video"))
                .accessibilityLabel(media.isBackgroundMuted ? "Unmute background" : "Mute background")
                .accessibilityValue(heard ? "muted" : "sound on")
            WFSlider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), range: 0...1, fill: Tok.blue)
                .frame(width: 70).disabled(heard).accessibilityLabel("Background volume")
        }
    }
}

private struct ControllerButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wf(12, .medium)).frame(width: 28, height: 24)
            .foregroundStyle(Tok.text)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: selected ? Tok.surface3 : Tok.surface2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
