// MEDIA-001 (MEDIA-03): the foreground clip's controls. It appears above the transport bar while a clip is loaded:
// play or pause, a scrubber, elapsed and remaining time, volume and mute, and Stop. Position comes from the model's
// clock-based readout, redrawn ten times a second.
import SwiftUI
import OperatorCore

struct MediaTransportStrip: View {
    @Bindable var media: MediaModel
    @State private var dragging = false
    @State private var dragPosition = 0.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            if let r = media.foregroundReadout() {
                HStack(spacing: 10) {
                    Image(systemName: "film").foregroundStyle(Tok.muted).accessibilityHidden(true)
                    Text(r.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                    Button { r.isPlaying ? media.pause() : media.resume() } label: {
                        Label(r.isPlaying ? "Pause" : "Play", systemImage: r.isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(HeaderButtonStyle(compact: true))
                    .help(r.isPlaying ? "Pause the clip" : "Resume the clip")
                    .disabled(r.status == .ended)
                    Text(MediaTile.clock(dragging ? dragPosition : r.position)).font(.system(size: 12, design: .monospaced)).frame(width: 52, alignment: .trailing)
                    WFSlider(value: Binding(get: { dragging ? dragPosition : r.position }, set: { dragPosition = $0 }),
                             range: 0...max(r.duration, 0.1)) { editing in
                        if editing { dragPosition = r.position; dragging = true }
                        else { media.seek(to: dragPosition); dragging = false }
                    }
                    .disabled(!r.canSeek).accessibilityLabel("Clip position")
                    Text("-" + MediaTile.clock(dragging ? max(0, r.duration - dragPosition) : r.remaining))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Tok.muted).frame(width: 56, alignment: .leading)
                    Rectangle().fill(Tok.border).frame(width: 1, height: 18)
                    Button { media.setMuted(!media.isMuted) } label: {
                        Label(media.isMuted ? "Unmute" : "Mute", systemImage: media.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(HeaderButtonStyle(compact: true))
                    .help(media.isMuted ? "Unmute the clip's sound" : "Mute the clip's sound")
                    WFSlider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), range: 0...1, fill: Tok.blue)
                        .frame(width: 90).disabled(media.isMuted).accessibilityLabel("Clip volume")
                    Button { media.stopForeground() } label: { Label("Stop clip", systemImage: "stop.fill") }
                        .buttonStyle(HeaderButtonStyle())
                        .help("Stop the clip and bring the words back")
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Tok.surface2)      // UI-005b: no red here; red is for on air
            }
        }
    }
}
