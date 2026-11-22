// UI-006d: which bin files cannot be read now, and finding one again (Locate...). The check reads the file system off the main thread and
// runs only when asked: when the bin changes, when a disk is mounted or the app comes forward (the app asks), after Locate. No timer.
import Foundation
import Domain

public struct MediaLocateOutcome: Equatable, Sendable {
    public var moved: [UUID] = []
    /// One sentence per file that could not be pointed at the new place, each saying why.
    public var problems: [String] = []
}

extension MediaModel {
    /// Starts a check in the background. A newer request replaces one still waiting.
    func scheduleOfflineCheck() {
        offlineTask?.cancel()
        let list = assets, available = isAvailable
        offlineTask = Task { [weak self] in
            let (missing, summary) = await Task.detached(priority: .utility) { () -> (Set<UUID>, MediaOffline.Summary?) in
                let offline = list.filter { !available($0) }
                return (Set(offline.map(\.id)), MediaOffline.summary(offline: offline, directoryExists: { FileManager.default.fileExists(atPath: $0) }))
            }.value
            guard !Task.isCancelled, let self else { return }
            if self.offlineIDs != missing { self.offlineIDs = missing }
            if self.offlineSummary != summary { self.offlineSummary = summary }
        }
    }

    /// Checks now and returns when the answer is in.
    public func refreshOffline() async {
        scheduleOfflineCheck()
        await offlineTask?.value
    }

    /// Tests and callers that need the answer of the check already started.
    public func finishOfflineCheck() async { await offlineTask?.value }

    /// The offline bin items, in bin order.
    public var offlineAssets: [MediaAsset] { assets.filter { offlineIDs.contains($0.id) } }

    /// Points bin items at the files the operator found. Each file is read first and must be the same kind of file as the item; the item keeps
    /// its id, so slides that use it as their own background recover. A move that cannot be made is reported and changes nothing.
    @discardableResult
    public func locate(_ moves: [MediaOffline.Move], bookmarks: [String: Data]) async -> MediaLocateOutcome {
        var outcome = MediaLocateOutcome()
        for move in moves {
            guard let asset = assets.first(where: { $0.id == move.assetID }) else { continue }
            let url = URL(fileURLWithPath: move.newPath)
            let info: MediaProbeResult
            do { info = try await prober.probe(url: url) } catch {
                outcome.problems.append("\"\(asset.name)\" was not changed: \(url.lastPathComponent) could not be read. \(error.localizedDescription)")
                continue
            }
            guard info.kind == asset.kind else {
                outcome.problems.append("\"\(asset.name)\" was not changed: \(url.lastPathComponent) is not the same kind of file (a \(asset.kind.rawValue) was expected).")
                continue
            }
            do {
                try await store.relocateMediaAsset(id: asset.id, path: move.newPath, bookmark: bookmarks[move.newPath],
                                                  duration: info.duration, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight)
                outcome.moved.append(asset.id)
            } catch {
                outcome.problems.append("\"\(asset.name)\" was not changed: \(WorkspaceModel.message(for: error, doing: "point the media item at the file"))")
            }
        }
        if !outcome.moved.isEmpty { await reload() }
        if !outcome.problems.isEmpty { lastError = outcome.problems.joined(separator: "\n") }
        await finishOfflineCheck()
        return outcome
    }
}
