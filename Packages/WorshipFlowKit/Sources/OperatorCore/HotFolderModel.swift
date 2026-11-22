// MEDIA-010 item 5: hot folders. The operator points the media bin at a folder; its videos, pictures and sound appear as a
// source and stay in step with the folder as files are added, renamed or removed. The folder is only ever listed: nothing
// here moves, copies, renames or deletes a file. A file that is still being copied (its size changed since the last look)
// is held back until it is stable. A folder that is gone shows as missing; it never throws at the operator and never blocks
// the show. Foundation, Observation, Domain and Persistence only: the file system and the watcher sit behind two doors.
import Foundation
import Observation
import CryptoKit
import Domain
import Persistence

public struct FolderFile: Sendable, Equatable {
    public var name: String
    public var size: Int64
    public init(name: String, size: Int64) { self.name = name; self.size = size }
}

public enum FolderListingError: Error, Sendable, Equatable {
    /// The folder is not there (moved, deleted, drive gone).
    case missing
    /// FIX-G: the folder is there, or may be, but cannot be listed now (a volume that is not answering, no permission, an I/O
    /// error). The last items are kept and the folder shows as unreachable.
    case unreachable
}

/// FIX-G: where a folder's bookmark leads now, and a fresh bookmark when the old one was stale (the folder moved or was renamed).
public struct FolderResolution: Sendable, Equatable {
    public var path: String
    public var refreshedBookmark: Data?
    public init(path: String, refreshedBookmark: Data? = nil) { self.path = path; self.refreshedBookmark = refreshedBookmark }
}

/// FIX-G: the door to a folder's security-scoped bookmark. It is only ever called off the main actor, because resolving a bookmark
/// to a volume that is gone can wait for a long time (the implementation must not show UI or mount anything).
public protocol FolderAccessing: Sendable {
    /// Opens access to the folder through its bookmark and says where it leads. Nil: the bookmark cannot be resolved.
    func resolve(_ folder: HotFolder) -> FolderResolution?
    /// Gives access up (the folder is no longer followed).
    func forget(_ id: UUID)
}

/// Lists the regular files directly inside a folder (not sub-folders). Throws `.missing` when it cannot be read.
public protocol FolderListing: Sendable {
    func list(folder path: String) throws -> [FolderFile]
}

public protocol FolderWatch: AnyObject { func cancel() }

/// Tells the model when a folder's contents changed. The callback runs on the main actor.
@MainActor
public protocol FolderWatching: AnyObject {
    func watch(path: String, onChange: @escaping @MainActor () -> Void) -> any FolderWatch
}

public enum HotFolderStatus: Sendable, Equatable {
    case ok, missing
    /// FIX-G: could not be listed this time; the last known items are still shown.
    case unreachable
}

public struct HotFolderState: Equatable, Identifiable, Sendable {
    public var folder: HotFolder
    public var status: HotFolderStatus
    /// Complete files, in name order.
    public var items: [MediaAsset]
    /// File names seen but held back because they are still changing.
    public var heldBack: [String]
    /// FIX-G: files that could not be read (probed). Retried with a growing delay, not every scan.
    public var unreadable: [String] = []
    /// FIX-G: a line to show under the folder, such as the 2,000-item cap.
    public var notice: String?
    public var id: UUID { folder.id }
}

public enum HotFolderFiles {
    static let video: Set<String> = ["mov", "mp4", "m4v"]
    static let image: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "bmp"]
    static let audio: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "aac"]

    public static func kind(ofFileNamed name: String) -> MediaKind? {
        guard !name.hasPrefix(".") else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        if video.contains(ext) { return .video }
        if image.contains(ext) { return .image }
        if audio.contains(ext) { return .audio }
        return nil
    }

    /// The same file in the same folder always has the same id, so a play or a cue that named it keeps working across scans
    /// and relaunches. Different folders give different ids.
    public static func id(folder: UUID, fileName: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(folder.uuidString)/\(fileName)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

@MainActor
@Observable
public final class HotFolderModel {
    /// FIX-G: a folder lists at most this many media files.
    public static let maxItemsPerFolder = 2_000

    public private(set) var folders: [HotFolderState] = []
    public internal(set) var lastError: String?
    /// How many files are being held back across all folders. The app rescans soon while this is above zero. Unreadable files are
    /// not counted: they are retried on a longer schedule of their own.
    public var pendingCount: Int { folders.reduce(0) { $0 + $1.heldBack.count } }

    /// Called after the items of any folder changed, with every folder's items. Not called when a scan changed nothing.
    @ObservationIgnored public var onAssetsChange: (@MainActor ([UUID: [MediaAsset]]) -> Void)?

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let listing: any FolderListing
    @ObservationIgnored private let watching: any FolderWatching
    @ObservationIgnored private let prober: any MediaProber
    @ObservationIgnored private let access: (any FolderAccessing)?
    @ObservationIgnored private var watches: [UUID: any FolderWatch] = [:]
    /// The size each file had the last time it was seen, per folder: a file is complete when it is seen twice with the same size.
    @ObservationIgnored private var lastSizes: [UUID: [String: Int64]] = [:]
    /// FIX-G: files known to be complete, with the size they had then. They are not held back again when a scan starts afresh.
    @ObservationIgnored private var complete: [UUID: [String: Int64]] = [:]
    /// FIX-G: probe results per folder, keyed by `name|size`, pruned on every scan to files that still exist.
    @ObservationIgnored private var probed: [UUID: [String: MediaProbeResult]] = [:]
    private struct Unreadable { var size: Int64; var failures: Int; var nextScan: Int }
    @ObservationIgnored private var unreadableFiles: [UUID: [String: Unreadable]] = [:]
    @ObservationIgnored private var scanNumber: [UUID: Int] = [:]
    /// FIX-G: one scan at a time per folder. A request that arrives while one runs asks for exactly one more.
    @ObservationIgnored private var inFlight: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var again: Set<UUID> = []
    /// Called after the list of folders changed (loaded, added, pointed again) and before it is scanned.
    @ObservationIgnored public var onFoldersChange: (@MainActor ([HotFolder]) -> Void)?

    /// Number of probe results held, for tests.
    var probeCacheCount: Int { probed.values.reduce(0) { $0 + $1.count } }

    public init(store: LibraryStore, listing: any FolderListing, watching: any FolderWatching, prober: any MediaProber,
                access: (any FolderAccessing)? = nil) {
        self.store = store
        self.listing = listing
        self.watching = watching
        self.prober = prober
        self.access = access
    }

    public func state(of id: UUID) -> HotFolderState? { folders.first { $0.id == id } }

    // MARK: Folders

    /// Reads the saved folders and starts watching each. A folder that is not there shows as missing. With `waitForScans` false
    /// (the launch) it returns as soon as the folders are read: the scans, the bookmarks and the volumes behind them are never waited for.
    public func load(waitForScans: Bool = true) async {
        do {
            let saved = try await store.mediaFolders()
            for state in folders { watches[state.id]?.cancel(); watches[state.id] = nil }
            folders = saved.map { HotFolderState(folder: $0, status: .ok, items: [], heldBack: []) }
            onFoldersChange?(saved)
            for folder in saved { startWatching(folder) }
            if waitForScans { await rescan() } else { requestRescan() }
        } catch {
            lastError = WorkspaceModel.message(for: error, doing: "read the hot folders")
        }
    }

    /// Follows a folder. The same path returns the existing entry.
    @discardableResult
    public func add(path: String, bookmark: Data?) async -> HotFolder? {
        if let existing = folders.first(where: { $0.folder.path == path }) { return existing.folder }
        let name = (path as NSString).lastPathComponent
        let folder = HotFolder(name: name.isEmpty ? path : name, path: path, bookmark: bookmark)
        do { try await store.saveMediaFolder(folder) } catch {
            lastError = WorkspaceModel.message(for: error, doing: "add the folder \"\(name)\" to the media bin")
            return nil
        }
        folders.append(HotFolderState(folder: folder, status: .ok, items: [], heldBack: []))
        onFoldersChange?(folders.map(\.folder))
        startWatching(folder)
        await rescan(folder.id)
        return folder
    }

    /// Stops following a folder. The folder and its files are left exactly as they are.
    public func remove(_ id: UUID) async {
        guard state(of: id) != nil else { return }
        do { try await store.removeMediaFolder(id: id) } catch {
            lastError = WorkspaceModel.message(for: error, doing: "remove the folder from the media bin")
            return
        }
        watches[id]?.cancel(); watches[id] = nil
        forgetScanState(id)
        access?.forget(id)
        folders.removeAll { $0.id == id }
        publish()
    }

    /// Points a folder that went missing (moved, renamed, drive gone) at its new place. The folder keeps its identity, so a
    /// cue that names its files keeps working.
    public func relocate(_ id: UUID, to path: String, bookmark: Data?) async {
        guard let before = folders.firstIndex(where: { $0.id == id }) else { return }
        var folder = folders[before].folder
        folder.path = path
        folder.bookmark = bookmark
        folder.name = (path as NSString).lastPathComponent
        do { try await store.saveMediaFolder(folder) } catch {
            lastError = WorkspaceModel.message(for: error, doing: "point the folder at its new place")
            return
        }
        // FIX-T (M1 audit): the position was found before the save suspended. The list may have changed meanwhile (a folder removed): find it again.
        guard let i = folders.firstIndex(where: { $0.id == id }) else {
            // It was removed during the save, which stored it again. Take the stored row away again so it does not come back at the next launch.
            try? await store.removeMediaFolder(id: id)
            return
        }
        folders[i].folder = folder
        folders[i].status = .ok
        forgetScanState(id)
        onFoldersChange?(folders.map(\.folder))
        watches[id]?.cancel(); watches[id] = nil
        startWatching(folder)
        await rescan(id)
    }

    private func forgetScanState(_ id: UUID) {
        lastSizes[id] = nil
        complete[id] = nil
        probed[id] = nil
        unreadableFiles[id] = nil
        scanNumber[id] = nil
    }

    // MARK: Scanning

    /// Looks at one folder (or all) and waits for it. Cheap; safe to call as often as the app likes: a folder is only ever scanned
    /// by one scan at a time, and a call that finds one running asks for one more and waits for both.
    public func rescan(_ id: UUID? = nil) async {
        for state in folders where id == nil || state.id == id {
            if let running = inFlight[state.id] {
                again.insert(state.id)
                _ = await running.value
            } else {
                _ = await startScan(state.id).value
            }
        }
    }

    /// FIX-G: the same without waiting, for timers and the watcher. Folders that are being scanned are asked for one more scan.
    public func requestRescan(_ id: UUID? = nil) {
        for state in folders where id == nil || state.id == id {
            if inFlight[state.id] != nil { again.insert(state.id) } else { _ = startScan(state.id) }
        }
    }

    /// Resolves when every scan that is running or was requested has finished.
    public func waitForRescans() async {
        while let running = inFlight.values.first { _ = await running.value }
    }

    private func startScan(_ id: UUID) -> Task<Bool, Never> {
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            var changed = await self.scan(id)
            while self.again.remove(id) != nil { if await self.scan(id) { changed = true } }
            self.inFlight[id] = nil
            if changed { self.publish() }
            return changed
        }
        inFlight[id] = task
        return task
    }

    private func scan(_ id: UUID) async -> Bool {
        guard let start = folders.firstIndex(where: { $0.id == id }) else { return false }
        var folder = folders[start].folder
        // FIX-G: the bookmark leads to where the folder is now (it follows a move or a rename). Resolved off the main actor, without
        // UI and without mounting anything.
        if let access, folder.bookmark != nil {
            let asked = folder
            let resolved = await Task.detached(priority: .utility) { access.resolve(asked) }.value
            if let resolved, let i = folders.firstIndex(where: { $0.id == id }) {
                let pathChanged = resolved.path != folder.path
                let bookmarkChanged = resolved.refreshedBookmark != nil && resolved.refreshedBookmark != folder.bookmark
                if pathChanged || bookmarkChanged {
                    folder.path = resolved.path
                    if let fresh = resolved.refreshedBookmark { folder.bookmark = fresh }
                    folders[i].folder = folder
                    try? await store.saveMediaFolder(folder)
                    if pathChanged {
                        complete[id] = nil; lastSizes[id] = nil
                        watches[id]?.cancel(); watches[id] = nil
                        startWatching(folder)
                    }
                }
            }
        }
        let files: [FolderFile]
        // The file system is read off the main actor.
        let listing = self.listing, path = folder.path
        do { files = try await Task.detached(priority: .utility) { try listing.list(folder: path) }.value } catch {
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
            let was = folders[index]
            if (error as? FolderListingError) == .missing {
                folders[index].status = .missing
                folders[index].items = []
                folders[index].heldBack = []
                folders[index].unreadable = []
                folders[index].notice = nil
                lastSizes[id] = nil
                return was.status != .missing || !was.items.isEmpty
            }
            // Any other failure: the last items stay, the folder shows as unreachable.
            folders[index].status = .unreachable
            return was.status != .unreachable
        }
        scanNumber[id, default: 0] += 1
        let number = scanNumber[id] ?? 1
        let previous = lastSizes[id] ?? [:]
        let known = complete[id] ?? [:]
        var media: [(FolderFile, MediaKind)] = files.compactMap { file in HotFolderFiles.kind(ofFileNamed: file.name).map { (file, $0) } }
        media.sort { $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }
        var notice: String?
        if media.count > Self.maxItemsPerFolder {
            notice = "This folder has \(Self.grouped(media.count)) media files. Only the first \(Self.grouped(Self.maxItemsPerFolder)) are listed."
            media = Array(media.prefix(Self.maxItemsPerFolder))
        }
        var sizes: [String: Int64] = [:]
        var ready: [(FolderFile, MediaKind)] = []
        var held: [String] = []
        for (file, kind) in media {
            sizes[file.name] = file.size
            // Complete: seen twice with the same size, or already known as complete at this size (not held back again).
            if file.size > 0, previous[file.name] == file.size || known[file.name] == file.size { ready.append((file, kind)) } else { held.append(file.name) }
        }
        lastSizes[id] = sizes
        var cache = probed[id] ?? [:]
        var fresh: [String: MediaProbeResult] = [:]
        var unreadable = unreadableFiles[id] ?? [:]
        var unreadableNames: [String] = []
        var items: [MediaAsset] = []
        var completeNow: [String: Int64] = [:]
        for (file, kind) in ready {
            let path = (folder.path as NSString).appendingPathComponent(file.name)
            let key = "\(file.name)|\(file.size)"
            var info = cache[key]
            if info == nil {
                if let earlier = unreadable[file.name], earlier.size == file.size, number < earlier.nextScan {
                    unreadableNames.append(file.name)       // not yet time to try this one again
                    continue
                }
                if let found = try? await prober.probe(url: URL(fileURLWithPath: path)) {
                    info = found
                    unreadable[file.name] = nil
                } else {
                    // Remembered, and tried again after a delay that doubles each time (counted in scans), up to 64 scans.
                    let failures = (unreadable[file.name].flatMap { $0.size == file.size ? $0.failures : nil } ?? 0) + 1
                    unreadable[file.name] = Unreadable(size: file.size, failures: failures, nextScan: number + min(1 << min(failures, 6), 64))
                    unreadableNames.append(file.name)
                    continue
                }
            }
            guard let info else { continue }
            fresh[key] = info
            completeNow[file.name] = file.size
            items.append(MediaAsset(id: HotFolderFiles.id(folder: id, fileName: file.name),
                                    name: (file.name as NSString).deletingPathExtension, kind: kind, path: path,
                                    duration: info.duration, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight,
                                    addedAt: Date(timeIntervalSinceReferenceDate: 0)))
        }
        // Only files that still exist stay remembered.
        probed[id] = fresh
        let present = Set(sizes.keys)
        unreadableFiles[id] = unreadable.filter { present.contains($0.key) }
        complete[id] = completeNow
        guard let now = folders.firstIndex(where: { $0.id == id }) else { return false }
        let before = folders[now]
        folders[now].status = .ok
        folders[now].items = items
        folders[now].heldBack = held.sorted()
        folders[now].unreadable = unreadableNames.sorted()
        folders[now].notice = notice
        return before.status != .ok || before.items != items || before.heldBack != folders[now].heldBack
            || before.unreadable != folders[now].unreadable || before.notice != notice
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func publish() {
        onAssetsChange?(Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.items) }))
    }

    private func startWatching(_ folder: HotFolder) {
        watches[folder.id]?.cancel()
        let id = folder.id
        watches[id] = watching.watch(path: folder.path) { [weak self] in self?.requestRescan(id) }
    }
}
