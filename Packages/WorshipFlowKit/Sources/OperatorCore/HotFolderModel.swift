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

public enum FolderListingError: Error, Sendable, Equatable { case missing }

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

public enum HotFolderStatus: Sendable, Equatable { case ok, missing }

public struct HotFolderState: Equatable, Identifiable, Sendable {
    public var folder: HotFolder
    public var status: HotFolderStatus
    /// Complete files, in name order.
    public var items: [MediaAsset]
    /// File names seen but held back because they are still changing.
    public var heldBack: [String]
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
    public private(set) var folders: [HotFolderState] = []
    public internal(set) var lastError: String?
    /// How many files are being held back across all folders. The app rescans soon while this is above zero.
    public var pendingCount: Int { folders.reduce(0) { $0 + $1.heldBack.count } }

    /// Called after the items of any folder changed, with every folder's items. Not called when a scan changed nothing.
    @ObservationIgnored public var onAssetsChange: (@MainActor ([UUID: [MediaAsset]]) -> Void)?

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let listing: any FolderListing
    @ObservationIgnored private let watching: any FolderWatching
    @ObservationIgnored private let prober: any MediaProber
    @ObservationIgnored private var watches: [UUID: any FolderWatch] = [:]
    /// The size each file had the last time it was seen, per folder: a file is complete when it is seen twice with the same size.
    @ObservationIgnored private var lastSizes: [UUID: [String: Int64]] = [:]
    @ObservationIgnored private var probed: [String: MediaProbeResult] = [:]
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    /// Called after the list of folders changed (loaded, added, pointed again) and before it is scanned, so the app can open
    /// access to each folder through its bookmark first.
    @ObservationIgnored public var onFoldersChange: (@MainActor ([HotFolder]) -> Void)?

    public init(store: LibraryStore, listing: any FolderListing, watching: any FolderWatching, prober: any MediaProber) {
        self.store = store
        self.listing = listing
        self.watching = watching
        self.prober = prober
    }

    public func state(of id: UUID) -> HotFolderState? { folders.first { $0.id == id } }

    // MARK: Folders

    /// Reads the saved folders and starts watching each. A folder that is not there shows as missing.
    public func load() async {
        do {
            let saved = try await store.mediaFolders()
            for state in folders { watches[state.id]?.cancel(); watches[state.id] = nil }
            folders = saved.map { HotFolderState(folder: $0, status: .ok, items: [], heldBack: []) }
            onFoldersChange?(saved)
            for folder in saved { startWatching(folder) }
            await rescan()
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
        lastSizes[id] = nil
        folders.removeAll { $0.id == id }
        publish()
    }

    /// Points a folder that went missing (moved, renamed, drive gone) at its new place. The folder keeps its identity, so a
    /// cue that names its files keeps working.
    public func relocate(_ id: UUID, to path: String, bookmark: Data?) async {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        var folder = folders[i].folder
        folder.path = path
        folder.bookmark = bookmark
        folder.name = (path as NSString).lastPathComponent
        do { try await store.saveMediaFolder(folder) } catch {
            lastError = WorkspaceModel.message(for: error, doing: "point the folder at its new place")
            return
        }
        folders[i].folder = folder
        folders[i].status = .ok
        lastSizes[id] = nil
        onFoldersChange?(folders.map(\.folder))
        watches[id]?.cancel(); watches[id] = nil
        startWatching(folder)
        await rescan(id)
    }

    // MARK: Scanning

    /// Looks at one folder (or all). Cheap; safe to call as often as the app likes.
    public func rescan(_ id: UUID? = nil) async {
        var changed = false
        for state in folders where id == nil || state.id == id {
            if await scan(state.id) { changed = true }
        }
        if changed { publish() }
    }

    /// Resolves when the rescans started by the watcher have finished.
    public func waitForRescans() async { await rescanTask?.value }

    private func scan(_ id: UUID) async -> Bool {
        guard let start = folders.firstIndex(where: { $0.id == id }) else { return false }
        let folder = folders[start].folder
        let files: [FolderFile]
        // The file system is read off the main actor.
        let listing = self.listing, path = folder.path
        do { files = try await Task.detached(priority: .utility) { try listing.list(folder: path) }.value } catch {
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
            let was = folders[index]
            folders[index].status = .missing
            folders[index].items = []
            folders[index].heldBack = []
            lastSizes[id] = nil
            return was.status != .missing || !was.items.isEmpty
        }
        let previous = lastSizes[id] ?? [:]
        var sizes: [String: Int64] = [:]
        var ready: [(FolderFile, MediaKind)] = []
        var held: [String] = []
        for file in files {
            guard let kind = HotFolderFiles.kind(ofFileNamed: file.name) else { continue }
            sizes[file.name] = file.size
            if file.size > 0, previous[file.name] == file.size { ready.append((file, kind)) } else { held.append(file.name) }
        }
        lastSizes[id] = sizes
        var items: [MediaAsset] = []
        for (file, kind) in ready.sorted(by: { $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }) {
            let path = (folder.path as NSString).appendingPathComponent(file.name)
            let key = "\(path)|\(file.size)"
            if probed[key] == nil, let found = try? await prober.probe(url: URL(fileURLWithPath: path)) { probed[key] = found }
            guard let info = probed[key] else { held.append(file.name); continue }      // not readable yet: try again next time
            items.append(MediaAsset(id: HotFolderFiles.id(folder: id, fileName: file.name),
                                    name: (file.name as NSString).deletingPathExtension, kind: kind, path: path,
                                    duration: info.duration, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight,
                                    addedAt: Date(timeIntervalSinceReferenceDate: 0)))
        }
        guard let now = folders.firstIndex(where: { $0.id == id }) else { return false }
        let before = folders[now]
        folders[now].status = .ok
        folders[now].items = items
        folders[now].heldBack = held.sorted()
        return before.status != .ok || before.items != items || before.heldBack != folders[now].heldBack
    }

    private func publish() {
        onAssetsChange?(Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.items) }))
    }

    private func startWatching(_ folder: HotFolder) {
        watches[folder.id]?.cancel()
        let id = folder.id
        watches[id] = watching.watch(path: folder.path) { [weak self] in
            guard let self else { return }
            let earlier = self.rescanTask
            self.rescanTask = Task { @MainActor in
                await earlier?.value
                await self.rescan(id)
            }
        }
    }
}
