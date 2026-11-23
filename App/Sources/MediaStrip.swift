// UI-005d: the Media mode's clip strip (design 05, bottom of the centre column) and the scrub bar its mockup draws. MEDIA-010's bin
// player lives here now: the strip plays the item chosen in the bin on this Mac only (never a screen), shows what it is for the
// live show, and sends it live. The picture of the old player is the tile in the grid. UI-007d: for a video the room at the right of the
// second row holds the design's Mark in, Mark out and Add marker (and the list of marks and markers); the ways to send it live are a menu in
// the first row then. A picture or a sound keeps its send buttons there.
import SwiftUI
import Domain
import OperatorCore

/// The mockup's `.scrub` of the Media screen: a 6 pt track (`surface-3`), a fill and a 14 pt white knob that overhangs the track.
/// Behaves like `WFSlider` (drag, arrows, VoiceOver), only the geometry differs: the layout height is the track's 6 pt.
struct MediaScrub: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var fill: Color = Tok.cyan
    var accessibilityName = ""
    var rectID = ""
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = CGFloat((value - range.lowerBound) / span).clamped01
            ZStack(alignment: .leading) {
                Capsule().fill(Tok.surface3).frame(height: 6).wfRect(rectID, radius: 3)
                Capsule().fill(fill).frame(width: width * fraction, height: 6).wfRect(rectID.isEmpty ? "" : "\(rectID).fill", radius: 3)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .wfRect(rectID.isEmpty ? "" : "\(rectID).thumb")
                    .offset(x: width * fraction - 7)
            }
            .frame(height: 6)
            .opacity(ControlEnabledStyle.opacity(isEnabled: isEnabled))
            .contentShape(Rectangle().inset(by: -8))
            .wfFocusReport(.slider)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = range.lowerBound + Double((drag.location.x / width).clamped01) * span
                }
                .onEnded { _ in dragging = false; onEditingChanged(false) }, including: isEnabled ? .all : .none)
        }
        .frame(height: 6)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .downArrow, .rightArrow, .upArrow, .pageUp, .pageDown, .home, .end]) { press in
            guard isEnabled else { return .ignored }
            let move: SliderStepping.Move
            switch press.key {
            case .leftArrow, .downArrow: move = .smaller
            case .rightArrow, .upArrow: move = .larger
            case .pageDown: move = .smallerPage
            case .pageUp: move = .largerPage
            case .home: move = .minimum
            default: move = .maximum
            }
            onEditingChanged(true)
            value = SliderStepping.value(from: value, range: range, move: move)
            onEditingChanged(false)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .accessibilityLabel(accessibilityName)
        }
    }
}

struct MediaStrip: View {
    let app: AppModel
    @Bindable var media: MediaModel
    let preview: MediaPreviewModel?
    @State private var dragging = false
    @State private var dragPosition = 0.0

    /// "00:11.4": minutes, seconds and tenths, as the design draws the readout.
    static func tenths(_ seconds: Double) -> String {
        MediaClock.tenths(seconds)   // FIX-T: total
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Tok.border).frame(height: 1)
            Group {
                if let preview, let asset = preview.asset, let controls = preview.controls {
                    content(preview, asset, controls)
                } else {
                    Text("Select a picture, video or sound in the bin to look at it here. It plays on this Mac only and never reaches a screen.")
                        .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(height: 77)
        .background(Tok.surface)
        .wfRect("media.strip")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player, a preview on this Mac only")
    }

    private func content(_ preview: MediaPreviewModel, _ asset: MediaAsset, _ controls: PreviewControls) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row1(preview, asset, controls)
            row2(preview, asset, controls)
        }
    }

    // MARK: Row 1: name, what it is for the show, what is known about the file, Loop

    private func row1(_ preview: MediaPreviewModel, _ asset: MediaAsset, _ controls: PreviewControls) -> some View {
        HStack(spacing: 8) {
            Text(asset.name).font(.wf(13, .bold)).lineLimit(1).truncationMode(.middle).wfLine().fixedSize()
                .wfRect("media.strip.name", size: 13, weight: 700)
            roleBadge(asset)
            Text(meta(asset)).font(.wfMono(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine().fixedSize()
                .wfRect("media.strip.meta", size: 11, weight: 400)
            Spacer(minLength: 8)
            // The owner's extras, kept to the free room of this row.
            if media.hasLiveBackgroundOverride {
                Button("Use the slide's own background") { media.dropBackgroundOverride() }
                    .buttonStyle(HeaderButtonStyle(kind: .ghost)).wfRect("media.extra.drop")
                    .help("Drop the live override: each slide's own background (or the theme's) shows again")
            }
            if asset.kind == .video, app.markers != nil { sendMenu(asset) }      // UI-007d: its row-2 room is taken by the marks
            if controls.showsTransport {
                Button { preview.setMuted(!preview.isMuted) } label: {
                    Image(systemName: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.wf(12)).frame(width: 15, height: 15)
                }
                .buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true)).disabled(!preview.canUnmute).wfRect("media.extra.mute")
                .help(preview.canUnmute ? (preview.isMuted ? "Turn this preview's sound on" : "Mute this preview") + ". " + preview.heardLine(outputName: app.audio?.devices.first(where: { $0.isDefault })?.name)
                      : "Started with --silent-audio: the preview stays silent")
                .accessibilityLabel(preview.isMuted ? "Turn preview sound on" : "Mute preview sound")
                Button { preview.setLoops(!preview.loops) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat").font(.wf(11)).frame(width: 12, height: 12)
                        Text("Loop").font(.wf(11, .semibold)).wfLine()
                    }
                    .foregroundStyle(preview.loops ? Tok.cyan : Tok.muted).padding(.horizontal, 9).frame(height: 20)
                    .wfOutline(RoundedRectangle(cornerRadius: 10, style: .circular), stroke: Tok.borderStrong)
                    .wfRect("media.strip.loop", size: 11, weight: 600, radius: 10).contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help(preview.loops ? "Looping: it starts again when it ends" : "Play once")
                .accessibilityLabel("Loop preview").accessibilityValue(preview.loops ? "on" : "off").accessibilityAddTraits(.isToggle)
            }
        }
        .frame(height: 20)
    }

    @ViewBuilder private func roleBadge(_ asset: MediaAsset) -> some View {
        let isBackground = media.layerParts.background?.selection.assetID == asset.id
        let isForeground = media.layerParts.foreground?.selection.assetID == asset.id
        let sounding = app.audio?.isActive(asset.id) ?? false
        if media.showIsLive && isBackground { Badge(text: "LIVE · BACKGROUND", style: .live, rectID: "media.strip.badge") }
        else if media.showIsLive && isForeground { Badge(text: "LIVE · FOREGROUND", style: .live, rectID: "media.strip.badge") }
        else if isBackground { Badge(text: "BACKGROUND", style: .preview, rectID: "media.strip.badge") }
        else if isForeground { Badge(text: "FOREGROUND", style: .preview, rectID: "media.strip.badge") }
        else if sounding { Badge(text: "SOUND ON", style: .outline(Tok.cyan), rectID: "media.strip.badge") }
    }

    /// Only what the app knows about the file: the picture size and the length (frame rate and codec are not read).
    private func meta(_ asset: MediaAsset) -> String {
        var parts: [String] = []
        if let w = asset.pixelWidth, let h = asset.pixelHeight { parts.append("\(w)×\(h)") }
        if let d = asset.duration, asset.kind != .image { parts.append(MediaTile.clock(d)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Row 2: restart, play, stop, times and scrub; the room of the marker buttons holds the way to send it live

    private func row2(_ preview: MediaPreviewModel, _ asset: MediaAsset, _ controls: PreviewControls) -> some View {
        HStack(spacing: 8) {
            if controls.showsTransport {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let position = dragging ? dragPosition : preview.position
                    HStack(spacing: 8) {
                        Button { preview.seek(to: preview.startPosition) } label: { Image(systemName: "backward.end.fill").font(.wf(11)).frame(width: 12, height: 12) }
                            .buttonStyle(HeaderButtonStyle()).wfRect("media.strip.restart", radius: Radius.md)
                            .help(preview.startPosition > 0 ? "Back to the in mark" : "Back to the start").accessibilityLabel("Restart preview")
                        Button { preview.togglePlay() } label: { Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill").font(.wf(11)).frame(width: 12, height: 12) }
                            .buttonStyle(HeaderButtonStyle(selected: preview.isPlaying)).wfRect("media.strip.play", radius: Radius.md)
                            .help(preview.isPlaying ? "Pause" : "Play").accessibilityLabel(preview.isPlaying ? "Pause preview" : "Play preview")
                        Button { if preview.isPlaying { preview.togglePlay() }; preview.seek(to: preview.startPosition) } label: { Image(systemName: "stop.fill").font(.wf(11)).frame(width: 12, height: 12) }
                            .buttonStyle(HeaderButtonStyle()).wfRect("media.strip.stop", radius: Radius.md)
                            .help("Stop and go back to the start").accessibilityLabel("Stop preview")
                        Text(Self.tenths(position)).font(.wfMono(11)).wfLine().wfRect("media.strip.elapsed", size: 11, weight: 400)
                        MediaScrub(value: Binding(get: { position }, set: { dragPosition = $0 }), range: 0...max(preview.duration, 0.1),
                                   accessibilityName: "Position in the preview", rectID: "media.strip.scrub") { editing in
                            if editing { dragPosition = preview.position; dragging = true } else { preview.seek(to: dragPosition); dragging = false }
                        }
                        .disabled(preview.duration <= 0)
                        Text("\u{2212}" + Self.tenths(dragging ? max(0, preview.duration - dragPosition) : preview.remaining))
                            .font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine().wfRect("media.strip.remaining", size: 11, weight: 400)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
            Group {
                if asset.kind == .video, let markers = app.markers {
                    MediaMarkButtons(media: media, markers: markers, preview: preview, asset: asset)      // UI-007d
                } else {
                    sendButtons(asset)
                }
            }
            .fixedSize()      // the room of Mark in, Mark out and Add marker (and the list button): as wide as the buttons need
        }
        .frame(height: 26)
    }

    /// UI-007d: a video's two ways to send it live, as one menu in the first row (the second row's room holds Mark in, Mark out and Add marker).
    private func sendMenu(_ asset: MediaAsset) -> some View {
        let live = media.showIsLive
        let offered = PreviewSendActions.available(for: asset.kind, showIsLive: live)
        return Menu {
            Button("Live background") { app.performDockAction(.setBackground(asset.id)) }.disabled(!offered.background)
            Button("Live foreground") { app.performDockAction(.playForeground(asset.id)) }.disabled(!offered.foreground)
        } label: {
            HStack(spacing: 5) { Text("Send live").font(.wf(11, .semibold)).wfLine(); Image(systemName: "chevron.down").font(.wf(9, .semibold)) }
                .foregroundStyle(Tok.text).padding(.horizontal, 9).frame(height: 20)
                .wfOutline(RoundedRectangle(cornerRadius: 10, style: .circular), stroke: Tok.borderStrong)
                .wfRect("media.extra.sendmenu", size: 11, weight: 600, radius: 10).contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(live ? "Put this behind the words (the presentation is not changed) or play it over them" : "Put this behind the words on the live screens. To play it over them, take a slide live first.")
        .accessibilityLabel("Send live")
    }

    private func sendButtons(_ asset: MediaAsset) -> some View {
        let live = media.showIsLive
        let offered = PreviewSendActions.available(for: asset.kind, showIsLive: live)
        return HStack(spacing: 8) {
            if asset.kind == .audio {
                Button("Play live") { app.performDockAction(.playAudio(asset.id)) }.buttonStyle(HeaderButtonStyle()).wfRect("media.extra.sendsound")
                    .help("Play this sound on the audio output now")
            } else {
                Button("Live background") { app.performDockAction(.setBackground(asset.id)) }
                    .buttonStyle(HeaderButtonStyle()).disabled(!offered.background).wfRect("media.extra.sendbg")
                    .help("Put this behind the words on the live screens. The presentation is not changed.")
                Button("Live foreground") { app.performDockAction(.playForeground(asset.id)) }
                    .buttonStyle(HeaderButtonStyle()).disabled(!offered.foreground).wfRect("media.extra.sendfg")
                    .help(live ? "Play this over the words" : "Take a slide live first")
            }
        }
    }
}
