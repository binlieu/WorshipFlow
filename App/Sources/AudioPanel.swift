// MEDIA-005 / MEDIA-006: the Audio section of the right-hand column. The sound files of the media bin with their
// length, play or pause, a scrubber for the cue that sounds, a loop switch and an overlap switch per file, volume
// and mute, a two-channel level meter, and the programme audio device. The decisions live in `AudioModel`; this view
// only shows and forwards.
import SwiftUI
import Domain
import OperatorCore

struct AudioPanel: View {
    @Bindable var audio: AudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Audio")
                Spacer()
                if !audio.activeCues.isEmpty {
                    Button { audio.stopAll() } label: { Label("Stop sound", systemImage: "stop.fill") }
                        .buttonStyle(HeaderButtonStyle()).help("Stop every sound that is playing")
                }
            }
            DevicePicker(audio: audio)
            HStack(spacing: 8) {
                Button { audio.setMuted(!audio.isMuted) } label: {
                    Label(audio.isMuted ? "Unmute" : "Mute", systemImage: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(HeaderButtonStyle(compact: true))
                .help(audio.isMuted ? "Unmute the sound" : "Mute the sound")
                WFSlider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), range: 0...1, fill: Tok.blue)
                    .disabled(audio.isMuted).accessibilityLabel("Sound volume")
                Text("\(Int((audio.volume * 100).rounded()))%").font(.wfMono(11)).foregroundStyle(Tok.muted).frame(width: 36, alignment: .trailing)
            }
            LevelMeter(audio: audio)
            if audio.assets.isEmpty {
                Text("No sound files yet. Add them to the media bin above with Add… (or drop them there): they appear here.")
                    .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(audio.assets) { asset in AudioRow(audio: audio, asset: asset) }
                }
            }
            Text("Loop repeats a sound. Overlap lets a sound play together with others, such as a quiet bed under a spoken part. Stopping the show ends all sound; Clear and Clear all do not.")
                .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
    }
}

/// Where the sound goes: the system default or one of the output devices, by name, with the default marked.
private struct DevicePicker: View {
    @Bindable var audio: AudioModel

    private static let systemDefault = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Output").font(.wf(12))
                WFPopup(title: currentDeviceTitle, accessibilityName: "Sound output device") {
                    Button("System default" + defaultSuffix) { audio.chooseDevice(nil) }
                    ForEach(audio.devices) { device in Button(label(for: device)) { audio.chooseDevice(device.uid) } }
                    if let missing = missingChoice { Button("\(missing) (not connected)") { audio.chooseDevice(missing) } }
                }
                Button { audio.refreshDevices() } label: { Label("Refresh devices", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }
                    .help("Look for sound devices again").buttonStyle(HeaderButtonStyle(compact: true))
            }
            if let notice = audio.deviceNotice {
                Text(notice).font(.wf(11)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sound files and video sound both go to this output, once. Microphones and instruments stay on the mixer.")
                    .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentDeviceTitle: String {
        guard let uid = audio.programmeDeviceUID else { return "System default" + defaultSuffix }
        if let device = audio.devices.first(where: { $0.uid == uid }) { return label(for: device) }
        return "\(uid) (not connected)"
    }

    private var defaultSuffix: String {
        audio.devices.first(where: \.isDefault).map { " (\($0.name))" } ?? ""
    }

    private func label(for device: AudioOutputDevice) -> String {
        "\(device.name) · \(device.channelCount) ch" + (device.isDefault ? " · default" : "")
    }

    private var missingChoice: String? {
        guard let uid = audio.programmeDeviceUID, !audio.devices.contains(where: { $0.uid == uid }) else { return nil }
        return uid
    }
}

/// One sound file: play or pause, name, length, the switches, and the scrubber while it sounds.
struct AudioRow: View {
    @Bindable var audio: AudioModel
    let asset: MediaAsset
    @State private var dragging = false
    @State private var dragPosition = 0.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let readout = audio.readout(for: asset.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button { toggle(readout) } label: {
                        Label(readout?.isPlaying == true ? "Pause" : "Play", systemImage: readout?.isPlaying == true ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(HeaderButtonStyle(compact: true))
                    .help(readout?.isPlaying == true ? "Pause \(asset.name)" : "Play \(asset.name)")
                    .accessibilityLabel(readout?.isPlaying == true ? "Pause \(asset.name)" : "Play \(asset.name)")
                    Text(asset.name).font(.wf(13)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(asset.duration.map(MediaTile.clock) ?? "—").font(.wfMono(11)).foregroundStyle(Tok.muted)
                    Toggle(isOn: Binding(get: { audio.loopIDs.contains(asset.id) }, set: { audio.setLoops($0, for: asset.id) })) {
                        Text("Loop").font(.wf(11))
                    }
                    .toggleStyle(.wfCheckbox).help("Repeat this sound").accessibilityLabel("Loop \(asset.name)")
                    Toggle(isOn: Binding(get: { audio.overlapIDs.contains(asset.id) }, set: { audio.setOverlap($0, for: asset.id) })) {
                        Text("Overlap").font(.wf(11))
                    }
                    .toggleStyle(.wfCheckbox).help("Let this sound play together with others").accessibilityLabel("Overlap \(asset.name)")
                }
                if let r = readout {
                    HStack(spacing: 6) {
                        Text(MediaTile.clock(dragging ? dragPosition : r.position)).font(.wfMono(11)).frame(width: 44, alignment: .trailing)
                        WFSlider(value: Binding(get: { dragging ? dragPosition : r.position }, set: { dragPosition = $0 }),
                                 range: 0...max(r.duration, 0.1), accessibilityName: "Position") { editing in
                            if editing { dragPosition = r.position; dragging = true }
                            else { audio.seek(asset.id, to: dragPosition); dragging = false }
                        }
                        .disabled(!r.canSeek).accessibilityLabel("Position in \(asset.name)")
                        Button { audio.stop(asset.id) } label: { Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly) }
                            .help("Stop \(asset.name)").buttonStyle(HeaderButtonStyle(compact: true))
                    }
                }
            }
            .padding(.vertical, 3).padding(.horizontal, 4)
            .background(readout == nil ? Color.clear : Tok.surface3, in: RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func toggle(_ readout: AudioReadout?) {
        guard let readout else { audio.play(asset.id); return }
        if readout.isPlaying { audio.pause(asset.id) } else { audio.resume(asset.id) }
    }
}

/// Two bars (left, right): the filled part is the RMS level, the tick the peak, on a decibel scale from -60 to 0.
private struct LevelMeter: View {
    let audio: AudioModel

    var body: some View {
        let levels = audio.levels
        VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { channel in
                Bar(rms: channel < levels.rms.count ? levels.rms[channel] : 0,
                    peak: channel < levels.peak.count ? levels.peak[channel] : 0)
                    .frame(height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Sound level")
        .accessibilityValue(String(format: "left %d percent, right %d percent",
                                   Int(((levels.peak.first ?? 0) * 100).rounded()), Int(((levels.peak.dropFirst().first ?? levels.peak.first ?? 0) * 100).rounded())))
    }

    private struct Bar: View {
        let rms: Float
        let peak: Float

        static func position(_ amplitude: Float) -> CGFloat {
            guard amplitude > 0.000_001 else { return 0 }
            let db = 20 * log10(Double(amplitude))
            return CGFloat(min(1, max(0, (db + 60) / 60)))
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(stops: [.init(color: Tok.cyan, location: 0), .init(color: Tok.cyan, location: 0.7),
                                                     .init(color: Tok.warning, location: 0.85), .init(color: Tok.warning, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width)
                        .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * Self.position(rms)) }
                    Rectangle().fill(Color.primary.opacity(peak > 0 ? 0.85 : 0)).frame(width: 2)
                        .offset(x: max(0, geo.size.width * Self.position(peak) - 2))
                }
            }
        }
    }
}
