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

    private let headerHeight: CGFloat = 40

    var body: some View {
        let state = app.mediaDock
        let height = MediaDock.clampedHeight(dragHeight ?? state.height, available: available)
        VStack(spacing: 0) {
            if !state.isCollapsed { resizeHandle(current: state.height) }
            Rectangle().fill(Tok.border).frame(height: 1)
            header(collapsed: state.isCollapsed)
            if !state.isCollapsed {
                strip(height: height - headerHeight)
                    .frame(height: height - headerHeight)
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
        HStack(spacing: Space.s3) {
            SectionLabel("Media bin").fixedSize()
            HStack(spacing: Space.s2) {
                ForEach(MediaDockTab.allCases) { tab in tabButton(tab) }
            }
            Spacer(minLength: 4)
            if MediaDock.showsLayerChoice(on: app.ui.dockTab) {
                HStack(spacing: 0) {
                    ForEach(MediaLayerChoice.allCases) { choice in layerButton(choice) }
                }
                .padding(2)
                .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.border, fill: Tok.surface2)
                .help("What a click on a picture or video does: put it behind the words, or play it over them")
            }
            Button { app.chooseMedia() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help("Add pictures, videos and sound to the media bin (or drop files here)")
                .accessibilityLabel("Add media files")
            Button { app.setMediaDock(collapsed: !collapsed) } label: { Image(systemName: collapsed ? "chevron.up" : "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help(collapsed ? "Show the media bin" : "Fold the media bin away")
                .accessibilityLabel(collapsed ? "Show the media bin" : "Fold the media bin away")
        }
        .padding(.horizontal, Space.s5)
        .frame(height: headerHeight)
    }

    private func tabButton(_ tab: MediaDockTab) -> some View {
        let selected = app.ui.dockTab == tab
        return Button { app.ui.dockTab = tab; if app.mediaDock.isCollapsed { app.setMediaDock(collapsed: false) } } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.symbol(tab)).font(.system(size: 11))
                Text(tab.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).fixedSize()
            }
            .padding(.horizontal, 6).frame(height: 26)
            .foregroundStyle(selected ? Tok.text : Tok.muted)
            .overlay(alignment: .bottom) { Rectangle().fill(selected ? Tok.cyan : .clear).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func layerButton(_ choice: MediaLayerChoice) -> some View {
        let selected = app.ui.dockLayer == choice
        return Button { app.ui.dockLayer = choice } label: {
            Text(choice.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).fixedSize()
                .padding(.horizontal, 9).frame(height: 22)
                .foregroundStyle(selected ? Tok.text : Tok.muted)
                .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private static func symbol(_ tab: MediaDockTab) -> String {
        switch tab { case .backgrounds: "film.stack"; case .videos: "film"; case .images: "photo"; case .audio: "music.note" }
    }

    @ViewBuilder private func strip(height: CGFloat) -> some View {
        let items = MediaDock.assets(media.assets, tab: app.ui.dockTab)
        let tileWidth = max(88, min(220, (height - 60) * 16.0 / 9.0))
        if items.isEmpty {
            Text(media.assets.isEmpty
                 ? "The bin is empty. Add pictures, videos and sound with +, or drop files here. Your files are never moved or deleted."
                 : "Nothing of this kind in the bin.")
                .font(.system(size: 12)).foregroundStyle(Tok.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, Space.s5)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: Space.s3) {
                    ForEach(items) { asset in tile(asset, width: tileWidth) }
                }
                .padding(.horizontal, Space.s5).padding(.vertical, 6)
            }
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

/// A thumbnail with the same rings as a slide: blue for chosen, red only while it is on screen now.
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
                        .font(.title2).foregroundStyle(Tok.muted)
                case nil:
                    if asset.kind == .audio { Image(systemName: "waveform").font(.title2).foregroundStyle(Tok.muted) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: width, height: width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            .overlay(alignment: .bottomTrailing) {
                if let d = asset.duration, asset.kind != .image {
                    Text(MediaTile.clock(d)).font(.wfMonoData).padding(.horizontal, 4)
                        .background(.black.opacity(0.65)).foregroundStyle(.white).padding(3)
                }
            }
            .overlay(alignment: .topLeading) { tag.padding(4) }
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(mark == .preview ? Tok.blue : .clear, lineWidth: 2))
            .padding(mark == .live ? 4 : 0)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(mark == .live ? Tok.liveFill : .clear, lineWidth: 3))
            Text(asset.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(Tok.text).frame(width: width, alignment: .leading).padding(.leading, 3)
        }
        .contentShape(Rectangle())
        .task(id: asset.path) { result = await MediaThumbnails.shared.thumbnail(for: asset) }
    }

    @ViewBuilder private var tag: some View {
        switch mark {
        case .live: Badge(text: "LIVE", style: .live)
        case .preview: Badge(text: "PREVIEW", style: .preview)
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

    private func row(_ f: Face) -> some View {
        HStack(spacing: Space.s3) {
            Button(action: f.restart) { Image(systemName: "backward.end.fill") }
                .buttonStyle(ControllerButtonStyle()).help("Back to the start").accessibilityLabel("Restart \(f.name)")
            Button(action: f.togglePlay) { Image(systemName: f.isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(ControllerButtonStyle(selected: f.isPlaying))
                .help(f.isPlaying ? "Pause" : "Play").accessibilityLabel(f.isPlaying ? "Pause \(f.name)" : "Play \(f.name)")
            Button(action: f.stop) { Image(systemName: "stop.fill") }
                .buttonStyle(ControllerButtonStyle())
                .help(f.kind == "Background" ? "Remove the background" : "Stop and bring the words back")
                .accessibilityLabel("Stop \(f.name)")
            VStack(alignment: .leading, spacing: 0) {
                Text(f.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(f.kind).font(.wfCaption).foregroundStyle(Tok.muted)
            }
            .frame(minWidth: 60, maxWidth: 150, alignment: .leading)
            Text(MediaTile.clock(dragging ? dragPosition : f.position)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Tok.muted)
            Slider(value: Binding(get: { dragging ? dragPosition : f.position }, set: { dragPosition = $0 }),
                   in: 0...max(f.duration, 0.1)) { editing in
                if editing { dragPosition = f.position; dragging = true } else { f.seek(dragPosition); dragging = false }
            }
            .tint(Tok.cyan).disabled(!f.canSeek).accessibilityLabel("Position in \(f.name)")
            Text("-" + MediaTile.clock(dragging ? max(0, f.duration - dragPosition) : f.remaining))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Tok.muted)
            loopControl(f)
            soundControl(f)
            ForEach(f.chips, id: \.self) { chip in
                PillTag(text: chip, color: Tok.blue, maxWidth: 110)
            }
        }
        .padding(.horizontal, Space.s5).frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(Tok.border).frame(height: 1) }
        .background(Tok.surface)
    }

    @ViewBuilder private func loopControl(_ f: Face) -> some View {
        switch f.loops {
        case .toggle(let on, let set):
            Button { set(!on) } label: { Image(systemName: "repeat") }
                .buttonStyle(ControllerButtonStyle(selected: on))
                .help(on ? "Looping: it starts again when it ends" : "Play once")
                .accessibilityLabel("Loop \(f.name)").accessibilityValue(on ? "on" : "off")
        case .always:
            Text("Loops").font(.system(size: 12)).foregroundStyle(Tok.muted)
                .help("A background always loops").accessibilityLabel("A background always loops")
        }
    }

    @ViewBuilder private func soundControl(_ f: Face) -> some View {
        switch f.sound {
        case .clip:
            Button { media.setMuted(!media.isMuted) } label: { Image(systemName: media.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help(media.isMuted ? "Unmute the clip's sound" : "Mute the clip's sound").accessibilityLabel(media.isMuted ? "Unmute" : "Mute")
            Slider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), in: 0...1)
                .tint(Tok.cyan).frame(width: 80).disabled(media.isMuted).accessibilityLabel("Clip volume")
        case .cue:
            if let audio {
                Button { audio.setMuted(!audio.isMuted) } label: { Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(.plain).foregroundStyle(Tok.muted)
                    .help(audio.isMuted ? "Unmute the sound" : "Mute the sound").accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1)
                    .tint(Tok.cyan).frame(width: 80).disabled(audio.isMuted).accessibilityLabel("Sound volume")
            }
        case .background:
            // MEDIA-010: muted when it starts, and the operator can unmute it. The state shown is the state the player was given.
            let heard = media.backgroundHeardMuted
            Button { media.setBackgroundMuted(!media.isBackgroundMuted) } label: { Image(systemName: heard ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                .buttonStyle(.plain).foregroundStyle(heard ? Tok.muted : Tok.text)
                .help(media.isBackgroundMuted ? "The background video is muted. Click to unmute it." : (heard ? "Silent while Blackout is on" : "Mute the background video"))
                .accessibilityLabel(media.isBackgroundMuted ? "Unmute background" : "Mute background")
                .accessibilityValue(heard ? "muted" : "sound on")
            Slider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), in: 0...1)
                .tint(Tok.cyan).frame(width: 80).disabled(heard).accessibilityLabel("Background volume")
        }
    }
}

private struct ControllerButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 28)
            .foregroundStyle(Tok.text)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: selected ? Tok.cyan : Tok.borderStrong,
                       fill: selected ? Tok.surface3 : Tok.surface2, lineWidth: selected ? 1.5 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
