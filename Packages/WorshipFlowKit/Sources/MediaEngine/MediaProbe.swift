// MEDIA-01: what is in a media file. Reads headers only; nothing is decoded for playback.
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Domain

public struct MediaInfo: Sendable, Equatable {
    public var kind: MediaKind
    /// Seconds. Nil for images, and for a movie whose length cannot be read.
    public var duration: Double?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var hasAudio: Bool

    public init(kind: MediaKind, duration: Double?, pixelWidth: Int?, pixelHeight: Int?, hasAudio: Bool) {
        self.kind = kind
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAudio = hasAudio
    }
}

public enum MediaProbeError: Error, Sendable, Equatable, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "The file is missing: \(path)"
        case .unreadable(let path): return "The file could not be opened: \(path)"
        case .unsupported(let path): return "This kind of file cannot be used as media: \(path)"
        }
    }
}

public enum MediaProbe {
    /// Describes a video, image or audio file. Runs off the calling actor.
    public static func probe(url: URL) async throws -> MediaInfo {
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw MediaProbeError.fileNotFound(path)
        }
        guard FileManager.default.isReadableFile(atPath: path) else { throw MediaProbeError.unreadable(path) }

        if let image = probeImage(url) { return image }

        let asset = AVURLAsset(url: url)
        let playable: Bool, tracks: [AVAssetTrack], duration: CMTime
        do {
            (playable, tracks, duration) = try await asset.load(.isPlayable, .tracks, .duration)
        } catch {
            throw MediaProbeError.unsupported(path)
        }
        guard playable else { throw MediaProbeError.unsupported(path) }
        let seconds = duration.seconds
        let length: Double? = seconds.isFinite && seconds > 0 ? seconds : nil

        var video: AVAssetTrack?
        var hasAudio = false
        for track in tracks {
            if track.mediaType == .video, video == nil { video = track }
            if track.mediaType == .audio { hasAudio = true }
        }
        if let video {
            var width: Int?, height: Int?
            if let (size, transform) = try? await video.load(.naturalSize, .preferredTransform) {
                let r = CGRect(origin: .zero, size: size).applying(transform)
                width = Int(saturating: abs(r.width).rounded())
                height = Int(saturating: abs(r.height).rounded())
            }
            return MediaInfo(kind: .video, duration: length, pixelWidth: width, pixelHeight: height, hasAudio: hasAudio)
        }
        guard hasAudio else { throw MediaProbeError.unsupported(path) }
        return MediaInfo(kind: .audio, duration: length, pixelWidth: nil, pixelHeight: nil, hasAudio: true)
    }

    private static func probeImage(_ url: URL) -> MediaInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) > 0,
              let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String), type.conforms(to: .image),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return MediaInfo(kind: .image, duration: nil, pixelWidth: w, pixelHeight: h, hasAudio: false)
    }
}
