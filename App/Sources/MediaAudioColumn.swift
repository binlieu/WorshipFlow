// UI-005d: the Media mode's right column (design 05, 340 pt): the Audio cue card, the output (the design's Routing section holds the
// matrix, which needs per-bus routing in the audio model and is left out with its room kept; its Device row and note are here) and
// the Levels. The owner's sound-file list (play, loop, overlap per file) follows below. The Show inspector's Audio tab keeps `AudioPanel`.
import SwiftUI
import Domain
import OperatorCore

/// The printed scale of the Levels meters (0, -12, -24, -48 at evenly spaced marks): a level in decibels as a share of the meter's
/// height, so the fill agrees with the numbers beside it. Above 0 it is full; below -48 it runs down to nothing at -60.
enum MediaLevelScale {
    /// Marks as the design draws them: the label centres sit at these shares of the 130 pt meter, from the bottom.
    private static let stops: [(db: Double, share: Double)] = [(-60, 0), (-48, 0.048), (-24, 0.345), (-12, 0.642), (0, 0.938)]

    static func share(amplitude: Float) -> Double {
        guard amplitude > 0.000_001 else { return 0 }
        return share(db: 20 * log10(Double(amplitude)))
    }

    static func share(db: Double) -> Double {
        if db >= 0 { return min(1, 0.938 + (db / 6) * 0.062) }
        if db <= -60 { return 0 }
        for i in 1..<stops.count where db <= stops[i].db {
            let a = stops[i - 1], b = stops[i]
            return a.share + (db - a.db) / (b.db - a.db) * (b.share - a.share)
        }
        return 0
    }

    /// "-6 dB" for a linear gain; the design's minus sign.
    static func decibelText(gain: Double, muted: Bool) -> String {
        if muted || gain <= 0.000_01 { return "Muted" }
        return String(format: "%.0f dB", 20 * log10(gain)).replacingOccurrences(of: "-", with: "\u{2212}")
    }
}

struct MediaAudioColumn: View {
    let app: AppModel
    @Bindable var audio: AudioModel
    @State private var dragging = false
    @State private var dragPosition = 0.0

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Tok.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cueCard
                    divider
                    output
                    divider
                    levels
                    divider
                    soundFiles
                }
                .frame(width: 339, alignment: .topLeading)
            }
            .frame(width: 339)
        }
        .frame(width: 340)
        .background(Tok.surface)
        .wfRect("media.col")
    }

    private var divider: some View { Rectangle().fill(Tok.border).frame(height: 1) }

    private func header(_ text: String, rectID: String) -> some View {
        SectionLabel(text).frame(maxWidth: .infinity, alignment: .leading).wfRect(rectID, size: 11, weight: 600)
    }

    // MARK: Audio cue

    private var cueCard: some View {
        // FIX-Q: the clock runs only while a sound is playing (see `TickingWhile`); a ten-per-second timeline with nothing playing updated the whole window.
        TickingWhile(active: audio.currentID != nil, every: 0.1) {
            let readout = audio.currentID.flatMap { audio.readout(for: $0) }
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Audio cue").wfRect("media.cue.h", size: 11, weight: 600).padding(.bottom, 8)
                HStack(spacing: 8) {
                    Button { if let r = readout { r.isPlaying ? audio.pause(r.assetID) : audio.resume(r.assetID) } } label: {
                        Image(systemName: readout?.isPlaying == true ? "pause.fill" : "play.fill").font(.wf(11)).frame(width: 12, height: 12)
                    }
                    .buttonStyle(HeaderButtonStyle()).disabled(readout == nil).wfRect("media.cue.play", radius: Radius.md)
                    .help(readout?.isPlaying == true ? "Pause the sound" : "Resume the sound")
                    .accessibilityLabel(readout?.isPlaying == true ? "Pause sound" : "Play sound")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(readout?.name ?? "No sound playing").font(.wf(13, .bold)).lineLimit(1).truncationMode(.middle).wfLine()
                            .frame(maxWidth: .infinity, alignment: .leading).wfRect("media.cue.name", size: 13, weight: 700)
                        Text(readout.map { "\(Self.clock(dragging ? dragPosition : $0.position)) / \(Self.clock($0.duration))" } ?? "\u{2014}")
                            .font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine()
                            .frame(maxWidth: .infinity, alignment: .leading).wfRect("media.cue.time", size: 11, weight: 400)
                    }
                }
                MediaScrub(value: Binding(get: { dragging ? dragPosition : (readout?.position ?? 0) }, set: { dragPosition = $0 }),
                           range: 0...max(readout?.duration ?? 1, 0.1), accessibilityName: "Position in the sound", rectID: "media.cue.scrub") { editing in
                    guard let r = readout else { return }
                    if editing { dragPosition = r.position; dragging = true } else { audio.seek(r.assetID, to: dragPosition); dragging = false }
                }
                .disabled(readout?.canSeek != true).padding(.top, 10)
                HStack(spacing: 8) {
                    Button { audio.setMuted(!audio.isMuted) } label: {
                        Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.wf(13)).frame(width: 15, height: 15)
                    }
                    .buttonStyle(.plain).foregroundStyle(Tok.text)
                    .help(audio.isMuted ? "Unmute the sound" : "Mute the sound").accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")
                    MediaScrub(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), fill: Tok.blue,
                               accessibilityName: "Sound volume", rectID: "media.cue.vol")
                    Text(MediaLevelScale.decibelText(gain: audio.volume, muted: audio.isMuted)).font(.wfMono(11)).wfLine()
                        .frame(width: 34, alignment: .trailing).wfRect("media.cue.vol.value", size: 11, weight: 400)
                }
                .frame(height: 16).padding(.top, 12)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(width: 339, height: 120, alignment: .topLeading)
            .wfRect("media.cue")
        }
    }

    private static func clock(_ seconds: Double) -> String {
        MediaClock.cue(seconds)   // FIX-T: total
    }

    // MARK: Output (the design's Routing section: the matrix is left out, its room kept)

    private var output: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Output", rectID: "media.out.h")
                .overlay(alignment: .trailing) {
                    Button { audio.refreshDevices() } label: { Image(systemName: "arrow.clockwise").font(.wf(11)).frame(width: 16, height: 16) }
                        .buttonStyle(.plain).foregroundStyle(Tok.muted).help("Look for sound devices again").accessibilityLabel("Refresh devices")
                }
            .padding(.bottom, 8)
            Color.clear.frame(height: 136)      // the routing matrix's room
            HStack(spacing: 8) {
                Text("Device").font(.wf(12)).foregroundStyle(Tok.muted).wfLine().fixedSize().wfRect("media.out.label", size: 12, weight: 400)
                WFPopup(title: deviceTitle, accessibilityName: "Sound output device", rectID: "media.out.device") {
                    Button("System default" + defaultSuffix) { audio.chooseDevice(nil) }
                    ForEach(audio.devices) { device in Button(label(for: device)) { audio.chooseDevice(device.uid) } }
                    if let missing = missingChoice { Button("\(missing) (not connected)") { audio.chooseDevice(missing) } }
                }
            }
            .padding(.top, 10)
            Group {
                if let notice = audio.deviceNotice {
                    Text(notice).foregroundStyle(Tok.warning)
                } else {
                    Text("Sound files and video sound both go to this output, once. Microphones and instruments stay on the mixer.").foregroundStyle(Tok.muted)
                }
            }
            .font(.wf(11)).lineSpacing(1.7).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading).wfRect("media.out.hint", size: 11, weight: 400)
            .padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 339, alignment: .topLeading)
        .wfRect("media.out")
    }

    private var deviceTitle: String {
        guard let uid = audio.programmeDeviceUID else { return "System default" + defaultSuffix }
        if let device = audio.devices.first(where: { $0.uid == uid }) { return label(for: device) }
        return "\(uid) (not connected)"
    }
    private var defaultSuffix: String { audio.devices.first(where: \.isDefault).map { " (\($0.name))" } ?? "" }
    private func label(for device: AudioOutputDevice) -> String { "\(device.name) · \(device.channelCount) ch" + (device.isDefault ? " · default" : "") }
    private var missingChoice: String? {
        guard let uid = audio.programmeDeviceUID, !audio.devices.contains(where: { $0.uid == uid }) else { return nil }
        return uid
    }

    // MARK: Levels

    private var levels: some View {
        let levels = audio.levels
        return VStack(alignment: .leading, spacing: 0) {
            header("Levels", rectID: "media.lev.h").padding(.bottom, 8)
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<2, id: \.self) { channel in
                    let amplitude = channel < levels.rms.count ? levels.rms[channel] : 0
                    VStack(spacing: 4) {
                        meter(share: MediaLevelScale.share(amplitude: amplitude), id: "media.lev.meter.\(channel)")
                        Text(channel == 0 ? "L" : "R").font(.wf(10)).foregroundStyle(Tok.muted).wfLine().wfRect("media.lev.label.\(channel)", size: 10, weight: 400)
                    }
                    .frame(width: 14)
                }
                Color.clear.frame(width: 27.8, height: 1)      // Cue L and Cue R need a cue bus: their room is kept
                Color.clear.frame(width: 28.6, height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(["0", "\u{2212}12", "\u{2212}24", "\u{2212}48"].enumerated()), id: \.offset) { index, text in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(text).font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine().fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading).wfRect("media.lev.scale.\(index)", size: 11, weight: 400)
                    }
                }
                .frame(height: 132).padding(.bottom, 18).fixedSize(horizontal: true, vertical: false)
                .wfRect("media.lev.scale")
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
            .wfRect("media.lev.row")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sound level")
            .accessibilityValue(String(format: "left %d percent, right %d percent",
                                       Int(saturating: Double((levels.peak.first ?? 0) * 100).rounded()), Int(saturating: Double((levels.peak.dropFirst().first ?? levels.peak.first ?? 0) * 100).rounded())))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 339, alignment: .topLeading)
    }

    /// 14 x 130: the track (`surface-3`, radius 2) and a fill from the bottom, cyan up to the warning colour. Red is for on air: not here.
    private func meter(share: Double, id: String) -> some View {
        RoundedRectangle(cornerRadius: Radius.xs - 1).fill(Tok.surface3)
            .frame(width: 14, height: 130)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LinearGradient(stops: [.init(color: Tok.cyan, location: 0), .init(color: Tok.cyan, location: 0.7),
                                                 .init(color: Tok.warning, location: 1)], startPoint: .bottom, endPoint: .top))
                    .frame(width: 14, height: 130 * share)
                    .wfRect(id + ".fill")
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .wfRect(id, radius: 2)
    }

    // MARK: The owner's sound-file list

    private var soundFiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Sound files")
                Spacer()
                if !audio.activeCues.isEmpty {
                    Button { audio.stopAll() } label: { Label("Stop sound", systemImage: "stop.fill") }
                        .buttonStyle(HeaderButtonStyle()).help("Stop every sound that is playing")
                }
            }
            if audio.assets.isEmpty {
                Text("No sound files yet. Add them to the media bin with Import… (or drop them there): they appear here.")
                    .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) { ForEach(audio.assets) { asset in AudioRow(audio: audio, asset: asset) } }
            }
            Text("Loop repeats a sound. Overlap lets a sound play together with others, such as a quiet bed under a spoken part. Stopping the show ends all sound; Clear and Clear all do not.")
                .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 339, alignment: .topLeading)
    }
}
