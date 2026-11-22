// MEDIA-002: tiny movies, pictures and sounds written at test time, so the tests depend on no files in the repository.
import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

enum TestMedia {
    static func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A silent H.264 movie, 10 frames a second. Each segment is a flat colour: (seconds, BGRA).
    /// FIX-L: the hardware H.264 encoder is shared with every other suite's writer and with the machine, and now and then refuses a session
    /// ("The file couldn't be saved", seen once in a full run, in a test that only needed a clip). A refused write is tried again, up to three times,
    /// from a clean file; the movie that comes out is the same.
    static func writeMovie(to url: URL, width: Int = 64, height: Int = 48,
                           segments: [(seconds: Double, bgra: (UInt8, UInt8, UInt8, UInt8))]) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 { try? FileManager.default.removeItem(at: url); try? await Task.sleep(nanoseconds: 200_000_000) }
            do { try await writeMovieOnce(to: url, width: width, height: height, segments: segments); return } catch { lastError = error }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    /// One line about a movie on disk: its duration and size, for a failure message.
    static func describeMovie(_ url: URL) async -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        let duration = try? await AVURLAsset(url: url).load(.duration).seconds
        return "\(size.map(String.init) ?? "?") bytes, \(duration.map { String(format: "%.2f s", $0) } ?? "duration unknown")"
    }

    private static func writeMovieOnce(to url: URL, width: Int, height: Int,
                                       segments: [(seconds: Double, bgra: (UInt8, UInt8, UInt8, UInt8))]) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let fps = 10
        var frame = 0
        for segment in segments {
            for _ in 0..<Int(segment.seconds * Double(fps)) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                    throw CocoaError(.fileWriteUnknown)
                }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    let stride = CVPixelBufferGetBytesPerRow(buffer)
                    for y in 0..<height {
                        let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
                        for x in 0..<width {
                            row[x * 4] = segment.bgra.0; row[x * 4 + 1] = segment.bgra.1
                            row[x * 4 + 2] = segment.bgra.2; row[x * 4 + 3] = segment.bgra.3
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))) else {
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
                frame += 1
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    static let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
    static let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
    static let black: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)
    static let green: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)

    /// A PNG of one flat colour.
    static func writePNG(to url: URL, width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) throws {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) { pixels[i * 4] = red; pixels[i * 4 + 1] = green; pixels[i * 4 + 2] = blue }
        let image: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Silence, mono, 44.1 kHz.
    static func writeSound(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    /// The centre pixel of a BGRA buffer as (red, green, blue).
    static func centre(of buffer: CVPixelBuffer) -> (r: Int, g: Int, b: Int)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = base.advanced(by: (h / 2) * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
        return (Int(row[(w / 2) * 4 + 2]), Int(row[(w / 2) * 4 + 1]), Int(row[(w / 2) * 4]))
    }

    /// Polls until `condition` holds or `seconds` pass. Every caller waits for something AVFoundation reports in its own
    /// time. The limit is a guard against a hang, not a performance threshold (KI-060: 8 s was shorter than a loaded Mac
    /// sometimes takes to report a failed item), so a passing test returns as soon as the thing happens.
    /// FIX-S (KI-172, KI-194): 60 s was reachable. With the whole package running on a saturated Mac, `aBrokenForegroundClipIsReportedPerAssetId`
    /// took 20 to 52 s to be told about a broken file (0.09 s alone, 30 of 30 runs), so a slower run would have failed it with nothing wrong in the
    /// code. 180 s keeps the guard a hang guard.
    static func wait(upTo seconds: Double = 180, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
