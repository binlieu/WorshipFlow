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
    /// Starts a check in the background. FIX-V item 6 (L8): only one check reads the file system at a time; a request that comes while one runs makes
    /// it run once more when it ends. FIX-Y (L16): the files are read volume by volume, each volume by one read at a time on a plain thread (not the
    /// cooperative pool). A volume that does not answer within `offlineCheckLimit` is given up on for this round: its files keep the marks they had,
    /// the other volumes are marked as usual, and the round does not count as a finished check, so the next activation looks again. A volume whose
    /// earlier read has still not returned is not read again, so a hung disk holds one thread however often the check is asked for; when that read
    /// finally ends, one more check is made.
    func scheduleOfflineCheck() {
        if offlineRunning { offlineAgain = true; return }
        offlineRunning = true
        offlineTask = Task { [weak self] in
            repeat {
                guard let self else { return }
                self.offlineAgain = false
                let list = self.assets, available = self.isAvailable, limit = self.offlineCheckLimit
                let signature = MediaOffline.Signature(paths: list.map(\.path), volumes: self.mountedVolumes())
                var probes: [(volume: String, items: [MediaAsset])] = []
                var unread: Set<UUID> = []
                for (volume, items) in Dictionary(grouping: list, by: { MediaOffline.volume(of: $0.path) }) {
                    if self.offlineBusyVolumes.contains(volume) { unread.formUnion(items.map(\.id)) } else { probes.append((volume, items)); self.offlineBusyVolumes.insert(volume) }
                }
                let answers = await withTaskGroup(of: (items: [MediaAsset], missing: Set<UUID>?).self) { group in
                    for probe in probes {
                        group.addTask { [weak self] in
                            let missing = await OfflineRead.run(limit: limit, work: { Set(probe.items.filter { !available($0) }.map(\.id)) }, finished: { late in
                                Task { @MainActor in self?.offlineReadEnded(probe.volume, afterGivingUp: late) }
                            })
                            return (probe.items, missing)
                        }
                    }
                    var all: [(items: [MediaAsset], missing: Set<UUID>?)] = []
                    for await answer in group { all.append(answer) }
                    return all
                }
                var missing: Set<UUID> = self.offlineIDs.intersection(unread)          // a volume not read keeps the marks it had
                for answer in answers {
                    if let found = answer.missing { missing.formUnion(found) } else {
                        unread.formUnion(answer.items.map(\.id))
                        missing.formUnion(self.offlineIDs.intersection(answer.items.map(\.id)))
                    }
                }
                let offline = list.filter { missing.contains($0.id) }
                let summary = await OfflineRead.run(limit: limit, work: { MediaOffline.summary(offline: offline, directoryExists: { FileManager.default.fileExists(atPath: $0) }) }, finished: { _ in })
                if self.offlineIDs != missing { self.offlineIDs = missing }
                if let summary, self.offlineSummary != summary { self.offlineSummary = summary }
                // A round that left a volume unread is not a finished check: the next activation asks again.
                self.lastOfflineCheck = unread.isEmpty && summary != nil ? MediaOffline.LastCheck(signature: signature, at: self.offlineClock()) : nil
            } while self?.offlineAgain == true
            self?.offlineRunning = false
        }
    }

    /// A volume's read returned (in time, or after it was given up on). The volume may be read again; after a late return the files are looked at once more.
    func offlineReadEnded(_ volume: String, afterGivingUp late: Bool) {
        offlineBusyVolumes.remove(volume)
        if late { scheduleOfflineCheck() }
    }

    /// The app came forward: checks only if the bin or the connected disks changed since the last check, or that check is old.
    public func refreshOfflineOnActivation() async {
        let signature = MediaOffline.Signature(paths: assets.map(\.path), volumes: mountedVolumes())
        guard MediaOffline.shouldCheckOnActivation(last: lastOfflineCheck, now: offlineClock(), signature: signature) else { return }
        await refreshOffline()
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

/// FIX-Y (REVIEW-5 L16): one blocking file system read on a plain dispatch thread, abandoned (nil) when it has not returned within `limit` seconds. The
/// thread itself cannot be stopped; it ends when the read does, and `finished` is then called, with true when the caller had already given up.
enum OfflineRead {
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?
        private var done = false
        private(set) var gaveUp = false
        init(_ c: CheckedContinuation<T?, Never>) { continuation = c }
        func resume(_ value: T?, givingUp: Bool = false) {
            lock.lock()
            guard !done else { lock.unlock(); return }
            done = true
            gaveUp = givingUp
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
        var abandoned: Bool { lock.lock(); defer { lock.unlock() }; return gaveUp }
    }

    static func run<T: Sendable>(limit: TimeInterval, work: @escaping @Sendable () -> T, finished: @escaping @Sendable (Bool) -> Void) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = Once<T>(continuation)
            DispatchQueue.global(qos: .utility).async {
                let value = work()
                once.resume(value)
                finished(once.abandoned)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) { once.resume(nil, givingUp: true) }
        }
    }
}
