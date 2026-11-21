// MEDIA-010 item 5: the app's side of hot folders: listing a folder, watching it for changes, and holding access to it
// through its security-scoped bookmark. Files are only ever listed here; nothing is moved, copied, renamed or deleted.
import Foundation
import Domain
import OperatorCore

/// Lists the regular files directly inside a folder. Runs off the main actor (the model calls it from a detached task).
struct FileSystemFolderListing: FolderListing {
    func list(folder path: String) throws -> [FolderFile] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FolderListingError.missing
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let entries: [URL]
        // FIX-G: a folder that is there but cannot be listed now is unreachable (the model keeps the last items), not missing.
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch { throw FolderListingError.unreachable }
        return entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return FolderFile(name: entry.lastPathComponent, size: Int64(values.fileSize ?? 0))
        }
    }
}

/// Watches a folder with a file-system event source: files added, renamed or removed call back on the main actor.
/// FIX-G: `open()` of a folder on a volume that is not answering can wait for a long time, so it is done on a utility queue; the
/// watch object is handed back at once and the event source is attached when the folder opens.
@MainActor
final class DispatchFolderWatching: FolderWatching {
    private final class Watch: FolderWatch, @unchecked Sendable {
        private let lock = NSLock()
        private var source: DispatchSourceFileSystemObject?
        private var cancelled = false
        func attach(_ new: DispatchSourceFileSystemObject) {
            lock.lock()
            if cancelled { lock.unlock(); new.cancel(); return }
            source = new
            lock.unlock()
        }
        func cancel() {
            lock.lock()
            cancelled = true
            let old = source
            source = nil
            lock.unlock()
            old?.cancel()
        }
    }

    func watch(path: String, onChange: @escaping @MainActor () -> Void) -> any FolderWatch {
        let watch = Watch()
        DispatchQueue.global(qos: .utility).async {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return }          // missing: shown as missing, retried by the periodic look
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .link],
                                                                   queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { onChange() } }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watch.attach(source)
        }
        return watch
    }
}

/// Holds access to each hot folder through its bookmark while it is followed, and gives it up when it is not.
/// FIX-G: used only off the main actor (the model calls `resolve` from a utility task). A bookmark is resolved without UI and
/// without mounting a volume, so a drive that is gone fails quickly instead of waiting or asking; a stale bookmark is refreshed.
final class HotFolderAccess: FolderAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var open: [UUID: URL] = [:]

    func resolve(_ folder: HotFolder) -> FolderResolution? {
        guard let data = folder.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        lock.lock()
        let held = open[folder.id]
        if held?.path != url.path {
            held?.stopAccessingSecurityScopedResource()
            open[folder.id] = url.startAccessingSecurityScopedResource() ? url : nil
        }
        lock.unlock()
        var fresh: Data?
        if stale { fresh = Self.bookmark(for: url) }
        return FolderResolution(path: url.path, refreshedBookmark: fresh)
    }

    func forget(_ id: UUID) {
        lock.lock()
        let held = open.removeValue(forKey: id)
        lock.unlock()
        held?.stopAccessingSecurityScopedResource()
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
