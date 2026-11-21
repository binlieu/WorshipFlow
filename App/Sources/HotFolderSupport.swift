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
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch { throw FolderListingError.missing }
        return entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return FolderFile(name: entry.lastPathComponent, size: Int64(values.fileSize ?? 0))
        }
    }
}

/// Watches a folder with a file-system event source: files added, renamed or removed call back on the main actor.
@MainActor
final class DispatchFolderWatching: FolderWatching {
    private final class Watch: FolderWatch {
        private var source: DispatchSourceFileSystemObject?
        init(source: DispatchSourceFileSystemObject?) { self.source = source }
        func cancel() { source?.cancel(); source = nil }
    }

    func watch(path: String, onChange: @escaping @MainActor () -> Void) -> any FolderWatch {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return Watch(source: nil) }          // missing: shown as missing, retried by the periodic look
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .link],
                                                               queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return Watch(source: source)
    }
}

/// Holds access to each hot folder through its bookmark while it is followed, and gives it up when it is not.
@MainActor
final class HotFolderAccess {
    private var open: [UUID: (url: URL, scoped: Bool)] = [:]

    func update(_ folders: [HotFolder]) {
        let ids = Set(folders.map(\.id))
        for (id, held) in open where !ids.contains(id) { if held.scoped { held.url.stopAccessingSecurityScopedResource() }; open[id] = nil }
        for folder in folders {
            if let held = open[folder.id] { if held.scoped { held.url.stopAccessingSecurityScopedResource() }; open[folder.id] = nil }
            guard let data = folder.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                open[folder.id] = (url, true)
            }
        }
    }

    /// The folder's current path through its bookmark (it follows a rename or a move), or nil.
    static func resolvedPath(of folder: HotFolder) -> String? {
        guard let data = folder.bookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))?.path
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
