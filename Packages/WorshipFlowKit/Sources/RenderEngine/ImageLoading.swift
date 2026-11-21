// OUT-003: decoding of image files for the compositor. ImageIO only; no Metal here.
// Decoded pixels are premultiplied BGRA in sRGB, so they can be uploaded to a `.bgra8Unorm` texture and blended
// with the same premultiplied "over" as text.
import Foundation
import CoreGraphics
import ImageIO

struct DecodedImage: Sendable {
    let width: Int
    let height: Int
    /// Premultiplied BGRA, top row first, tightly packed.
    let pixels: [UInt8]
}

enum ImageDecoder {
    /// Longest side kept after decoding. Larger images are scaled down by ImageIO, which bounds memory per image.
    static let maxDimension = 4096

    static func modificationDate(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func decode(path: String) -> DecodedImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var longest = maxDimension
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 {
            longest = min(maxDimension, max(w, h))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))   // converts to sRGB, premultiplies
            return true
        }
        return drawn ? DecodedImage(width: width, height: height, pixels: pixels) : nil
    }
}

/// Result of one decode attempt. `modified` is read before decoding, so a change during the decode is noticed later.
struct ImageLoadOutcome: Sendable {
    let path: String
    let modified: Date?
    let image: DecodedImage?
}

/// Thread-safe hand-off between background decodes and the render thread, plus the counters the tests and the
/// operator window read.
// @unchecked Sendable: every stored property is guarded by `lock`.
final class ImageLoadCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: [ImageLoadOutcome] = []
    private var pending: Set<String> = []
    private var decodes = 0
    private var unavailable: Set<String> = []

    var decodeCount: Int { lock.lock(); defer { lock.unlock() }; return decodes }
    var unavailablePaths: Set<String> { lock.lock(); defer { lock.unlock() }; return unavailable }

    /// Decodes on the calling thread. Used by offscreen rendering; the live path uses `requestInBackground`.
    func decodeNow(_ path: String) -> ImageLoadOutcome {
        let modified = ImageDecoder.modificationDate(of: path)
        let image = ImageDecoder.decode(path: path)
        lock.lock()
        decodes += 1
        if image == nil { unavailable.insert(path) } else { unavailable.remove(path) }
        lock.unlock()
        return ImageLoadOutcome(path: path, modified: modified, image: image)
    }

    func requestInBackground(_ path: String) {
        lock.lock()
        guard pending.insert(path).inserted else { lock.unlock(); return }
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            let outcome = decodeNow(path)
            lock.lock()
            pending.remove(path)
            finished.append(outcome)
            lock.unlock()
        }
    }

    func takeFinished() -> [ImageLoadOutcome] {
        lock.lock(); defer { lock.unlock() }
        guard !finished.isEmpty else { return [] }
        let out = finished
        finished = []
        return out
    }
}
