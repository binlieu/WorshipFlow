// MEDIA-01: poster frames and downsized stills for the media bin. Runs off the main thread.
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import Domain

public enum MediaThumbnailer {
    /// Fractions of the clip tried in turn. The first is the poster; the rest are only used when it is black.
    static let posterFractions: [Double] = [0.10, 0.25, 0.50, 0.75, 0.02]

    /// A poster for a video (about ten per cent in, avoiding a black frame when another is available) or a
    /// downsized copy of a still. `maxPixelSize` is the longest side. Audio has no thumbnail.
    public static func thumbnail(url: URL, kind: MediaKind, maxPixelSize: Int = 320) async throws -> CGImage {
        let limit = max(16, maxPixelSize)
        switch kind {
        case .image: return try stillThumbnail(url, limit: limit)
        case .video: return try await videoPoster(url, limit: limit)
        case .audio: throw MediaProbeError.unsupported(url.path)
        }
    }

    static func stillThumbnail(_ url: URL, limit: Int) throws -> CGImage {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw MediaProbeError.fileNotFound(url.path) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw MediaProbeError.unsupported(url.path) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw MediaProbeError.unsupported(url.path)
        }
        return image
    }

    static func videoPoster(_ url: URL, limit: Int) async throws -> CGImage {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw MediaProbeError.fileNotFound(url.path) }
        let asset = AVURLAsset(url: url)
        let length: Double
        do { length = try await asset.load(.duration).seconds } catch { throw MediaProbeError.unsupported(url.path) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: limit, height: limit)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var first: CGImage?
        for fraction in posterFractions {
            let t = length.isFinite && length > 0 ? length * fraction : 0
            guard let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { continue }
            if first == nil { first = result.image }
            if !isNearlyBlack(result.image) { return result.image }
            if !(length.isFinite && length > 0) { break }
        }
        if let first { return first }
        throw MediaProbeError.unsupported(url.path)
    }

    /// True when the picture is, to the eye, black: mean brightness under about 3% on a tiny copy.
    static func isNearlyBlack(_ image: CGImage) -> Bool {
        let side = 16
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        var sum = 0
        for i in stride(from: 0, to: pixels.count, by: 4) { sum += Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) }
        return Double(sum) / Double(side * side * 3) < 8
    }
}
