// MEDIA-001: the app's side of the media bin: the registry as the outputs' frame source, probing through
// AVFoundation, security-scoped access to bin files, and thumbnails made off the main thread.
import Foundation
import AppKit
import MediaEngine
import OutputEngine
import Domain
import OperatorCore

// The same adoption pattern as `LoopingVideoSource: VideoSourceFactory` in VideoSupport.swift (MEDIA-002's report).
extension MediaRegistry: @retroactive MediaFrameSource {}

/// Reads media headers with `MediaProbe`. Its error descriptions already say what is wrong with the file.
struct AppMediaProber: MediaProber {
    func probe(url: URL) async throws -> MediaProbeResult {
        let info = try await MediaProbe.probe(url: url)
        return MediaProbeResult(kind: info.kind, duration: info.duration, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight)
    }
}

/// A file URL for a bin asset, with access held while it is in use. A sandboxed or bookmarked file is opened through
/// its security-scoped bookmark; a plain path is used as it is. `stop()` balances the access and is safe to call once.
struct MediaAccess: Sendable {
    let url: URL
    private let scoped: Bool

    static func open(_ asset: MediaAsset) -> MediaAccess {
        if let data = asset.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                return MediaAccess(url: url, scoped: true)
            }
        }
        return MediaAccess(url: URL(fileURLWithPath: asset.path), scoped: false)
    }

    func stop() { if scoped { url.stopAccessingSecurityScopedResource() } }

    /// A bookmark for a file the operator just chose or dropped. Nil when the system will not make one.
    nonisolated static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// FIX-M: bookmarks for dropped or chosen files, made on a background thread (making one reads the file's attributes, and a file on a slow
    /// volume would stall the window). Access is started and stopped around each one, as the drop requires.
    nonisolated static func bookmarks(for urls: [URL]) -> [URL: Data] {
        var out: [URL: Data] = [:]
        for url in urls {
            let started = url.startAccessingSecurityScopedResource()
            if let data = bookmark(for: url) { out[url] = data }
            if started { url.stopAccessingSecurityScopedResource() }
        }
        return out
    }
}

/// Thumbnails for the bin: made on a background task, cached in memory by asset id, one attempt per asset.
@MainActor
final class MediaThumbnails {
    enum Result: Sendable { case image(PreviewImage), failed }

    static let shared = MediaThumbnails()
    private var cache: [UUID: Result] = [:]
    private var running: [UUID: Task<Result, Never>] = [:]

    func cached(_ id: UUID) -> Result? { cache[id] }

    func thumbnail(for asset: MediaAsset) async -> Result {
        if let hit = cache[asset.id] { return hit }
        if let task = running[asset.id] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> Result in
            guard asset.kind != .audio else { return .failed }
            let access = MediaAccess.open(asset)
            defer { access.stop() }
            do { return .image(PreviewImage(image: try await MediaThumbnailer.thumbnail(url: access.url, kind: asset.kind, maxPixelSize: 320))) }
            catch { return .failed }
        }
        running[asset.id] = task
        let result = await task.value
        running[asset.id] = nil
        cache[asset.id] = result
        return result
    }

    func forget(_ id: UUID) { cache[id] = nil }
}
