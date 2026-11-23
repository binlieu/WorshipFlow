// UI-007c (SLIDE): the app's side of video objects on a slide. Three jobs:
//  1. Posters: a still frame of each clip, written once to the caches folder and drawn in the place of the clip wherever a slide is only looked at
//     (the Edit canvas and every thumbnail). A poster is made on a background task, never on the main thread; until it exists the place stays empty.
//  2. Playing: after every publish the clips that the screens' scenes name are opened for playback (looped and muted unless the object says
//     otherwise) through the media registry, and closed when the slide is no longer on a screen.
//  3. Adding: the Video button's clip list, the bin's video clips.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Domain
import MediaEngine
import OperatorCore

// MARK: Posters

/// One poster file per clip, named by the clip's id, in the caches folder. The model is observable so a view that asked for a poster that did not
/// exist yet draws it as soon as it is written.
@MainActor
@Observable
final class VideoPosters {
    static let shared = VideoPosters()

    /// Changes when a poster has been written, so views that read `path(for:)` draw again.
    private(set) var revision = 0
    @ObservationIgnored private var making: Set<UUID> = []
    @ObservationIgnored private var failed: Set<UUID> = []
    @ObservationIgnored private var known: [UUID: String] = [:]
    @ObservationIgnored private let folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WorshipFlow", isDirectory: true).appendingPathComponent("VideoPosters", isDirectory: true)
    }

    /// The poster file of a clip, or nil while there is none (it is then being made). A clip that could not be read is not tried again this session.
    func path(for asset: MediaAsset) -> String? {
        _ = revision                                                   // read, so the caller's view follows the poster arriving
        if let hit = known[asset.id] { return hit }
        let file = folder.appendingPathComponent("\(asset.id.uuidString).jpg")
        if FileManager.default.fileExists(atPath: file.path) { known[asset.id] = file.path; return file.path }
        guard asset.kind == .video, !making.contains(asset.id), !failed.contains(asset.id) else { return nil }
        making.insert(asset.id)
        let destination = file
        let folder = self.folder
        Task.detached(priority: .utility) { [weak self] in
            let access = MediaAccess.open(asset)
            defer { access.stop() }
            var ok = false
            if let image = try? await MediaThumbnailer.thumbnail(url: access.url, kind: .video, maxPixelSize: 960) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                ok = Self.writeJPEG(image, to: destination)
            }
            await MainActor.run { [weak self] in self?.made(asset.id, at: ok ? destination.path : nil) }
        }
        return nil
    }

    private func made(_ id: UUID, at path: String?) {
        making.remove(id)
        if let path { known[id] = path } else { failed.insert(id) }
        revision &+= 1
    }

    nonisolated private static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        guard let target = CGImageDestinationCreateWithURL(temp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { try? FileManager.default.removeItem(at: temp); return false }
        do { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp); return true } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }
}

extension AppModel {
    /// A scene for looking at (the editor, a thumbnail): each video object is its poster, still. A clip that has no poster yet or that left the bin
    /// draws nothing there.
    func stillScene(_ scene: SceneDescription) -> SceneDescription {
        scene.replacingVideoObjects { id in media?.asset(id).flatMap { VideoPosters.shared.path(for: $0) } }
    }

    // MARK: Adding

    /// The video clips in the bin, for the Video button.
    var binVideos: [MediaAsset] { (media?.allAssets ?? []).filter { $0.kind == .video } }

    /// Places a clip on the selected slide as a video object (looped, muted), in Edit.
    func insertVideoObject(_ asset: MediaAsset) {
        guard slideEditor?.slide != nil, asset.kind == .video else { return }
        _ = VideoPosters.shared.path(for: asset)                       // start making its poster now
        slideEditor?.addVideo(mediaID: asset.id)
    }

    /// The clip's name in the bin, or nil when the clip is not in the bin (the object then draws nothing, and the inspector says so).
    func videoTitle(_ mediaID: UUID) -> String? { media?.asset(mediaID).flatMap { $0.kind == .video ? $0.name : nil } }

    // MARK: Playing

    /// After a publish: opens for playback the clips the screens' scenes name and closes the ones they no longer name. Cheap when nothing changed.
    /// Opening a file is control-side work, here and now; the render threads only look frames up.
    func syncObjectVideos(_ snapshot: PublishedScenes) {
        var requests: [ObjectVideoRequest] = []
        var seen: Set<UUID> = []
        for profile in profiles where profile.role != .stage {
            for clip in snapshot.scene(forScreen: profile.id).videoObjectLayers where seen.insert(clip.mediaID).inserted {
                guard let asset = media?.asset(clip.mediaID), asset.kind == .video else { continue }
                requests.append(ObjectVideoRequest(assetID: asset.id, url: ObjectVideoAccess.shared.url(for: asset), loops: clip.loops, muted: clip.muted,
                                                   duration: asset.duration))
            }
        }
        mediaRegistry.objectVideos.apply(requests)
        ObjectVideoAccess.shared.keepOnly(Set(requests.map(\.assetID)))
    }
}

/// The security-scoped access to the files of the clips that are open, started when a clip is first asked for and stopped when it is not wanted.
@MainActor
final class ObjectVideoAccess {
    static let shared = ObjectVideoAccess()
    private var open: [UUID: MediaAccess] = [:]

    func url(for asset: MediaAsset) -> URL {
        if let held = open[asset.id] { return held.url }
        let access = MediaAccess.open(asset)
        open[asset.id] = access
        return access.url
    }

    func keepOnly(_ ids: Set<UUID>) {
        for id in open.keys where !ids.contains(id) { open.removeValue(forKey: id)?.stop() }
    }
}
