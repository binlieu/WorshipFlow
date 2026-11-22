// UI-006d: "Locate..." for bin files that cannot be read now (design 05's offline callout), and the callout itself. The decisions
// (the words, which other files move with the chosen one, the kind check, the store write) are in OperatorCore (`MediaOffline`,
// `MediaModel.locate`); this file asks for the file and shows the result.
import SwiftUI
import AppKit
import Domain
import OperatorCore

extension AppModel {
    /// Asks for the file of an offline bin item (the first offline one when none is given) and points the item at it. Other offline items
    /// that were in the same folder move too when the chosen file's folder holds files of their names.
    func locateOfflineMedia(_ target: MediaAsset? = nil) {
        guard let media, let target = target ?? media.offlineAssets.first else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Find \"\(URL(fileURLWithPath: target.path).lastPathComponent)\" (the media bin keeps its place in every slide that uses it)"
        panel.prompt = "Use this file"
        var folder = URL(fileURLWithPath: target.path).deletingLastPathComponent()
        while folder.path != "/", !FileManager.default.fileExists(atPath: folder.path) { folder = folder.deletingLastPathComponent() }
        panel.directoryURL = folder.path == "/" ? URL(fileURLWithPath: "/Volumes") : folder
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.relocate(target, to: url) }
        }
    }

    private func relocate(_ target: MediaAsset, to url: URL) {
        guard let media else { return }
        Task { @MainActor in
            let plan = MediaOffline.relocationPlan(target: target, chosen: url.path, offline: media.offlineAssets,
                                                   fileExists: { FileManager.default.fileExists(atPath: $0) })
            let urls = plan.map { URL(fileURLWithPath: $0.newPath) }
            let made = await Task.detached(priority: .userInitiated) { MediaAccess.bookmarks(for: urls) }.value
            let bookmarks = Dictionary(uniqueKeysWithValues: made.map { ($0.key.path, $0.value) })
            let outcome = await media.locate(plan, bookmarks: bookmarks)
            for id in outcome.moved { MediaThumbnails.shared.forget(id) }
        }
    }
}

/// The design's callout at the foot of the left list: a warning, the file (or files) and the reason, and Locate...
struct MediaOfflineCallout: View {
    let app: AppModel
    @Bindable var media: MediaModel

    var body: some View {
        if let summary = media.offlineSummary {
            VStack(spacing: 0) {
                Rectangle().fill(Tok.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.wf(13)).frame(width: 15, height: 15).foregroundStyle(Tok.warning)
                            .wfRect("media.sb.offline.icon")
                        VStack(alignment: .leading, spacing: 0) {
                            Text(summary.headline).font(.wf(12, .bold)).foregroundStyle(Tok.warning).wfLine(16)
                            if let detail = summary.detail {
                                Text(detail).font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wfRect("media.sb.offline")
                    Button("Locate\u{2026}") { app.locateOfflineMedia() }
                        .buttonStyle(HeaderButtonStyle()).wfRect("media.sb.locate", radius: Radius.md)
                        .help("Find the file again. The item keeps its place in the bin and in every slide that uses it; other files from the same folder are found with it.")
                        .accessibilityLabel("Locate the offline file")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
        }
    }
}
