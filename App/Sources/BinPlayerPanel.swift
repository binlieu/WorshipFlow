// MEDIA-010 item 4: the player in the Media mode's right sidebar for the item selected in the bin: a video with play, pause,
// scrub, time, loop and mute; sound the same without the picture; a picture as a picture. A local preview on this Mac only:
// it never reaches an output (the media registry is not involved) and its sound follows --silent-audio. From here the item
// goes live: Send to live background, Send to live foreground, and for sound Play live.
import SwiftUI
import AVKit
import Domain
import OperatorCore

/// The video picture without AVKit's own controls (the panel draws its own).
private struct PlayerPicture: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

struct BinPlayerPanel: View {
    let app: AppModel
    @Bindable var preview: MediaPreviewModel
    @State private var dragging = false
    @State private var dragPosition = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Player")
            if let asset = preview.asset, let controls = preview.controls {
                Text(asset.name).font(.wf(14, .semibold)).lineLimit(1).truncationMode(.middle)
                picture(asset, controls)
                if controls.showsTransport { transport(controls) }
                sendButtons(asset)
                Text("This player is a preview on this Mac only. It never goes to a screen.")
                    .font(.wfCaption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Select a picture, video or sound in the bin to look at it here.")
                    .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player")
    }

    @ViewBuilder private func picture(_ asset: MediaAsset, _ controls: PreviewControls) -> some View {
        ZStack {
            Color(white: 0.12)
            if !controls.showsPicture {
                Image(systemName: "waveform").font(.wf(34)).foregroundStyle(Tok.muted)
            } else if asset.kind == .video {
                PlayerPicture(player: app.binPreviewPlayer.player)
            } else if let image = NSImage(contentsOfFile: asset.path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Tok.warning)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.border, lineWidth: 1))
    }

    private func transport(_ controls: PreviewControls) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let position = dragging ? dragPosition : preview.position
            VStack(spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    Button { preview.togglePlay() } label: { Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill") }
                        .buttonStyle(HeaderButtonStyle()).help(preview.isPlaying ? "Pause" : "Play")
                        .accessibilityLabel(preview.isPlaying ? "Pause preview" : "Play preview")
                    Text(MediaTile.clock(position)).font(.wfMono(12)).foregroundStyle(Tok.muted)
                    Slider(value: Binding(get: { position }, set: { dragPosition = $0 }), in: 0...max(preview.duration, 0.1)) { editing in
                        if editing { dragPosition = preview.position; dragging = true } else { preview.seek(to: dragPosition); dragging = false }
                    }
                    .tint(Tok.cyan).disabled(preview.duration <= 0).accessibilityLabel("Position in the preview")
                    Text("-" + MediaTile.clock(dragging ? max(0, preview.duration - dragPosition) : preview.remaining))
                        .font(.wfMono(12)).foregroundStyle(Tok.muted)
                }
                HStack(spacing: Space.s3) {
                    Toggle(isOn: Binding(get: { preview.loops }, set: { preview.setLoops($0) })) { Label("Loop", systemImage: "repeat") }
                        .toggleStyle(.button).controlSize(.small).accessibilityValue(preview.loops ? "on" : "off")
                    // FIX-G: a clear speaker button; the line under the controls says where the sound would be heard.
                    Button { preview.setMuted(!preview.isMuted) } label: {
                        Label(preview.isMuted ? "Muted" : "Sound on", systemImage: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .controlSize(.small).disabled(!preview.canUnmute)
                    .help(preview.canUnmute ? (preview.isMuted ? "Turn this preview's sound on" : "Mute this preview") : "Started with --silent-audio: the preview stays silent")
                    .accessibilityLabel(preview.isMuted ? "Turn preview sound on" : "Mute preview sound")
                    Spacer()
                }
                Text(preview.heardLine(outputName: defaultOutputName))
                    .font(.wfCaption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The name of this Mac's default sound output, if the audio model knows it.
    private var defaultOutputName: String? { app.audio?.devices.first(where: { $0.isDefault })?.name }

    private func sendButtons(_ asset: MediaAsset) -> some View {
        let live = app.media?.showIsLive ?? false
        let offered = PreviewSendActions.available(for: asset.kind, showIsLive: live)
        return VStack(alignment: .leading, spacing: Space.s2) {
            if asset.kind == .audio {
                Button("Play live") { app.performDockAction(.playAudio(asset.id)) }.buttonStyle(HeaderButtonStyle())
                    .help("Play this sound on the audio output now")
            } else {
                HStack(spacing: Space.s3) {
                    Button("Send to live background") { app.performDockAction(.setBackground(asset.id)) }
                        .buttonStyle(HeaderButtonStyle()).disabled(!offered.background)
                        .help("Put this behind the words on the live screens. The presentation is not changed.")
                    Button("Send to live foreground") { app.performDockAction(.playForeground(asset.id)) }
                        .buttonStyle(HeaderButtonStyle()).disabled(!offered.foreground)
                        .help(live ? "Play this over the words" : "Take a slide live first")
                }
            }
        }
    }
}
