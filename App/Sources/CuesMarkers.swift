// UI-007d (CU-33): the Cues mode's "Playback markers" section, at the place the design draws it (below a macro's actions): a clip's timeline with its
// markers, and the actions each marker runs when live playback crosses it. Markers are made in the Media mode (Add marker at the playhead); here
// their actions are edited, with the same list editor as a macro. A marker's actions go through the one command path (source "marker", shown in
// Activity) and only while the clip plays on the screens: the Media mode's preview player never runs them. Like a slide's actions, they cannot move
// the show.
import SwiftUI
import Domain
import CueEngine
import OperatorCore

struct CuesPlaybackMarkers: View {
    let app: AppModel
    let cue: CueModel
    @State private var chosenClip: UUID?
    @State private var chosenMarker: UUID?
    @State private var problem: String?

    var body: some View {
        if let media = app.media, let markers = app.markers {
            let videos = media.assets.filter { $0.kind == .video }
            let clip = effectiveClip(videos, markers: markers)
            VStack(alignment: .leading, spacing: 0) {
                header(videos, clip: clip, markers: markers).wfRect("mk.h")      // UI-008: tagged for the rectangle comparison
                if let clip {
                    let list = markers.markers(for: clip.id)
                    timeline(clip, list)
                        .padding(.top, 12)
                    if list.isEmpty {
                        Text("This clip has no markers. Open it in the Media mode, move the player to a moment and press Add marker.")
                            .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                    } else {
                        markerList(clip, list, markers: markers).padding(.top, 14)
                        if let marker = list.first(where: { $0.id == chosenMarker }) ?? list.first {
                            actions(of: marker, markers: markers).padding(.top, 12)
                        }
                    }
                } else {
                    Text("There are no videos in the media bin. Markers belong to the clips in the bin.").font(.wf(12)).foregroundStyle(Tok.muted)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)      // with the 22 pt above: the design's 142 pt
            .padding(.top, 22)
        } else {
            Color.clear.frame(height: 142)
        }
    }

    /// The chosen clip if it is still in the bin, else the first clip that has markers, else the first video.
    private func effectiveClip(_ videos: [MediaAsset], markers: MediaMarkerModel) -> MediaAsset? {
        if let chosenClip, let found = videos.first(where: { $0.id == chosenClip }) { return found }
        return videos.first { !markers.markers(for: $0.id).isEmpty } ?? videos.first
    }

    private func header(_ videos: [MediaAsset], clip: MediaAsset?, markers: MediaMarkerModel) -> some View {
        HStack(spacing: 8) {
            Text("Playback markers").font(.wf(13, .bold)).accessibilityAddTraits(.isHeader)
            if let clip { Text("\u{2014} \(clip.name)").font(.wf(13, .bold)).foregroundStyle(Tok.muted).lineLimit(1).truncationMode(.middle) }
            Spacer(minLength: 8)
            if videos.count > 1, let clip {
                Menu {
                    ForEach(videos) { video in
                        let count = markers.markers(for: video.id).count
                        Button { chosenClip = video.id; chosenMarker = nil; problem = nil } label: {
                            Text(count == 0 ? video.name : "\(video.name) (\(count))")
                        }
                    }
                } label: {
                    HStack(spacing: 6) { Text("Choose clip").font(.wf(12, .medium)).wfLine(); Image(systemName: "chevron.down").font(.wf(9, .semibold)) }
                        .foregroundStyle(Tok.text).padding(.horizontal, 10).frame(height: 24)
                        .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.surface2)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Choose the clip whose markers are shown").accessibilityValue(clip.name)
            }
        }
    }

    // MARK: Timeline (the design's `.tl`: a track the length of the clip, the part that plays, and a warning-coloured line per marker)

    private func timeline(_ clip: MediaAsset, _ list: [MediaMarker]) -> some View {
        let length = max(clip.duration ?? list.map(\.time).max() ?? 1, 0.1)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3).fill(Tok.surface3).frame(width: width, height: 6).offset(y: 14)
                    // The part of the clip that plays (its in and out marks): the rest is dimmer.
                    let lo = CGFloat((clip.markIn ?? 0) / length), hi = CGFloat((clip.markOut ?? length) / length)
                    RoundedRectangle(cornerRadius: 3).fill(Tok.cyan.opacity(0.55)).frame(width: max(2, width * (hi - lo)), height: 6).offset(x: width * lo, y: 14)
                    ForEach(list) { marker in
                        let x = width * CGFloat(min(1, max(0, marker.time / length)))
                        let selected = marker.id == (chosenMarker ?? list.first?.id)
                        Rectangle().fill(selected ? Tok.text : Tok.warning).frame(width: 2, height: 34).offset(x: min(max(0, x - 1), width - 2), y: 0)
                    }
                }
                .frame(height: 34)
            }
            .frame(height: 34).wfRect("mk.tl")
            HStack {
                Text(MediaTimeText.format(0)); Spacer(); Text(MediaTimeText.format(length / 2)); Spacer(); Text(MediaTimeText.format(length))
            }
            .font(.wfMono(11)).foregroundStyle(Tok.muted).wfRect("mk.axis")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline of \(clip.name), \(list.count) marker\(list.count == 1 ? "" : "s")")
    }

    // MARK: The list (time order; choose one to edit its actions)

    private func markerList(_ clip: MediaAsset, _ list: [MediaMarker], markers: MediaMarkerModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(list) { marker in
                let selected = marker.id == (chosenMarker ?? list.first?.id)
                let count = markers.actions(of: marker.id).count
                Button { chosenMarker = marker.id; problem = nil } label: {
                    HStack(spacing: 10) {
                        Text(MediaTimeText.format(marker.time)).font(.wfMono(12)).frame(width: 64, alignment: .leading)
                        Text(marker.name ?? "Marker").font(.wf(12, .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        if markers.actionsAreUnreadable(marker.id) {
                            Label("actions cannot be read", systemImage: "exclamationmark.triangle.fill").font(.wf(11)).foregroundStyle(Tok.warning)
                        } else {
                            Text(count == 0 ? "no actions" : "\(count) action\(count == 1 ? "" : "s")").font(.wf(11)).foregroundStyle(Tok.muted)
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 26).frame(maxWidth: .infinity)
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Marker \(marker.name ?? "") at \(MediaTimeText.format(marker.time)), \(count) action\(count == 1 ? "" : "s")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func actions(of marker: MediaMarker, markers: MediaMarkerModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runs when \(marker.name.map { "\"\($0)\"" } ?? "this marker") is reached at \(MediaTimeText.format(marker.time))")
                .font(.wf(12, .semibold))
            Text("Only while this clip plays on the screens: not in the Media mode's preview, and not when the operator jumps over it. They cannot move the show.")
                .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if markers.actionsAreUnreadable(marker.id) {
                Text("This marker's actions were written by a newer version or are damaged, so it runs nothing. Saving new actions replaces them.")
                    .font(.wf(12)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
            }
            ActionListEditor(app: app, context: .marker, editingMacro: nil, actions: markers.actions(of: marker.id), rectPrefix: "mk.") { new in
                Task { @MainActor in problem = await markers.setActions(new, for: marker.id, macros: cue.library) }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.wf(12)).foregroundStyle(Tok.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(marker.id)
    }
}
