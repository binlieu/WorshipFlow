// HWTEST-001: deterministic frames for testing an SDI path, and decoders that read them back from a captured frame.
// All frames are BGRA, premultiplied, like everything else in `SDIEngine`. Pure functions: no device, no clock.
import Foundation

public struct PixelPosition: Equatable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// A rectangle of pixels inside a pattern, so a measurement knows where to look.
public struct PatternRegion: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var centerX: Int { x + width / 2 }
    public var centerY: Int { y + height / 2 }
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
}

/// How two frames differ. Only B, G and R are compared unless alpha was asked for.
public struct FrameComparison: Equatable, Sendable {
    public var sizesMatch: Bool
    public var maxChannelError: Int
    public var meanChannelError: Double
    /// The first pixel (row by row) with a channel error above the tolerance, or nil.
    public var firstDifference: PixelPosition?
    public var pixelsOverTolerance: Int
}

public enum TestPattern {
    // MARK: colour bars

    /// Eight vertical bars at 75 %: white, yellow, cyan, green, magenta, red, blue, black. Opaque.
    public static func colorBars(width: Int, height: Int) -> SDIFrame {
        guard width > 0, height > 0 else { return SDIFrame(width: max(0, width), height: max(0, height), bgra: []) }
        // R, G, B per bar
        let bars: [(UInt8, UInt8, UInt8)] = [(191, 191, 191), (191, 191, 0), (0, 191, 191), (0, 191, 0), (191, 0, 191), (191, 0, 0), (0, 0, 191), (0, 0, 0)]
        var row = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            let bar = bars[min(7, x * 8 / width)]
            row[x * 4] = bar.2; row[x * 4 + 1] = bar.1; row[x * 4 + 2] = bar.0
        }
        return SDIFrame(width: width, height: height, bgra: repeatRow(row, height: height))
    }

    // MARK: frame counter

    /// 32 data bits (most significant first) and 8 check bits, one cell each along a strip at the bottom of the frame.
    public static let counterCells = 40

    /// The strip is 1/12 of the frame height, at least 8 pixels.
    public static func counterStripHeight(forHeight height: Int) -> Int { max(8, height / 12) }

    /// Mid-grey frame with the counter strip. The index wraps at 2^32 (more than two years at 60 fps).
    public static func frameCounter(index: Int64, width: Int, height: Int) -> SDIFrame {
        var frame = solid(width: width, height: height, blue: 64, green: 64, red: 64, alpha: 255)
        stampCounter(index: index, into: &frame)
        return frame
    }

    /// Colour bars with the counter strip over their bottom edge.
    public static func colorBarsWithCounter(index: Int64, width: Int, height: Int) -> SDIFrame {
        CounterFrameSource(width: width, height: height).frame(index: index)
    }

    static func stampCounter(index: Int64, into frame: inout SDIFrame) {
        let w = frame.width, h = frame.height
        let cell = w / counterCells
        guard cell >= 1, h >= 8, frame.bgra.count >= w * h * 4 else { return }
        let strip = counterStripHeight(forHeight: h)
        let bits = counterBits(UInt32(truncatingIfNeeded: index))
        var mask: UInt64 = 0
        for (i, bit) in bits.enumerated() where bit { mask |= 1 << UInt64(i) }
        frame.bgra.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            stampLoop(base, w, h, strip, cell, mask)
        }
    }

    // The loops run over every pixel of the strip of every frame, so they are optimised even in a Debug build (a closure
    // inside an optimised function is not, which is why they live in their own functions on raw pointers).
    @_optimize(speed)
    private static func stampLoop(_ base: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int, _ strip: Int, _ cell: Int, _ mask: UInt64) {
        var c = 0
        while c < counterCells {
            let v: UInt8 = mask >> UInt64(c) & 1 == 1 ? 255 : 0
            var y = h - strip
            while y < h {
                var p = base + (y * w + c * cell) * 4
                var x = 0
                while x < cell { p[0] = v; p[1] = v; p[2] = v; p[3] = 255; p += 4; x += 1 }
                y += 1
            }
            c += 1
        }
        let used = cell * counterCells
        if used < w {
            var y = h - strip
            while y < h {
                var x = used
                while x < w { let p = base + (y * w + x) * 4; p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 255; x += 1 }
                y += 1
            }
        }
    }

    private static func counterBits(_ value: UInt32) -> [Bool] {
        let check = crc8([UInt8(value >> 24 & 255), UInt8(value >> 16 & 255), UInt8(value >> 8 & 255), UInt8(value & 255)]) ^ 0xA5
        var bits: [Bool] = []
        for i in stride(from: 31, through: 0, by: -1) { bits.append(value >> UInt32(i) & 1 == 1) }
        for i in stride(from: 7, through: 0, by: -1) { bits.append(check >> UInt8(i) & 1 == 1) }
        return bits
    }

    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for b in bytes {
            crc ^= b
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc
    }

    @_optimize(speed)
    private static func cellSum(_ base: UnsafePointer<UInt8>, _ w: Int, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> (Int, Int) {
        var sum = 0, n = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let p = base + (y * w + x) * 4
                sum += Int(p[0]) + Int(p[1]) + Int(p[2])
                n += 3
                x += 1
            }
            y += 1
        }
        return (sum, n)
    }

    /// Reads the frame index back from a captured frame, or nil when there is no valid counter in it: a cell that is
    /// neither clearly dark nor clearly light, a failed check, or a frame too small to hold the strip.
    /// Each cell is judged by the average of its middle half, so a one-pixel shift, a level shift of 40 or the
    /// rounding of a YUV conversion does not change the answer.
    public static func decodeFrameIndex(from frame: SDIFrame) -> Int64? {
        let w = frame.width, h = frame.height
        let cell = w / counterCells
        let strip = counterStripHeight(forHeight: h)
        guard cell >= 4, h >= 8, strip >= 4, frame.bgra.count >= w * h * 4 else { return nil }
        var bits: [Bool] = []
        bits.reserveCapacity(counterCells)
        return frame.bgra.withUnsafeBufferPointer { buf -> Int64? in
            guard let base = buf.baseAddress else { return nil }
            for c in 0..<counterCells {
                let x0 = c * cell + cell / 4, x1 = c * cell + cell - cell / 4
                let y0 = h - strip + strip / 4, y1 = h - strip / 4
                let (sum, n) = cellSum(base, w, x0, x1, y0, y1)
                guard n > 0 else { return nil }
                let mean = sum / n
                if mean > 80 && mean < 175 { return nil }
                bits.append(mean >= 128)
            }
            var value: UInt32 = 0
            for i in 0..<32 { value = value << 1 | (bits[i] ? 1 : 0) }
            var check: UInt8 = 0
            for i in 32..<40 { check = check << 1 | (bits[i] ? 1 : 0) }
            let expected = crc8([UInt8(value >> 24 & 255), UInt8(value >> 16 & 255), UInt8(value >> 8 & 255), UInt8(value & 255)]) ^ 0xA5
            return check == expected ? Int64(value) : nil
        }
    }

    // MARK: alpha patterns

    /// Where the two boxes of `alphaWindow` are: an opaque one on the left, a 50 % one on the right.
    public static func alphaWindowRegions(width: Int, height: Int) -> (opaque: PatternRegion, half: PatternRegion) {
        let y = height * 20 / 100, h = height * 60 / 100
        return (PatternRegion(x: width * 10 / 100, y: y, width: width * 30 / 100, height: h),
                PatternRegion(x: width * 55 / 100, y: y, width: width * 30 / 100, height: h))
    }

    /// A transparent surround, an opaque orange box and a 50 % white box. Premultiplied: the half box is (128, 128, 128, 128).
    public static func alphaWindow(width: Int, height: Int) -> SDIFrame {
        var frame = solid(width: width, height: height, blue: 0, green: 0, red: 0, alpha: 0)
        let r = alphaWindowRegions(width: width, height: height)
        fill(&frame, r.opaque, blue: 0, green: 128, red: 255, alpha: 255)
        fill(&frame, r.half, blue: 128, green: 128, red: 128, alpha: 128)
        return frame
    }

    /// White whose alpha rises from 0 at the left edge to 255 at the right, premultiplied. Constant down each column.
    public static func alphaRamp(width: Int, height: Int) -> SDIFrame {
        guard width > 0, height > 0 else { return SDIFrame(width: max(0, width), height: max(0, height), bgra: []) }
        var row = [UInt8](repeating: 0, count: width * 4)
        for x in 0..<width {
            let a = UInt8(width > 1 ? (x * 255 + (width - 1) / 2) / (width - 1) : 255)
            row[x * 4] = a; row[x * 4 + 1] = a; row[x * 4 + 2] = a; row[x * 4 + 3] = a
        }
        return SDIFrame(width: width, height: height, bgra: repeatRow(row, height: height))
    }

    /// The alpha of the ramp at a column, as an integer 0...255.
    public static func alphaRampValue(x: Int, width: Int) -> Int { width > 1 ? (x * 255 + (width - 1) / 2) / (width - 1) : 255 }

    // MARK: grid

    /// White lines one pixel wide every `spacing` pixels (both directions, starting at 0) on opaque black.
    public static func grid(width: Int, height: Int, spacing: Int = 64) -> SDIFrame {
        guard width > 0, height > 0 else { return SDIFrame(width: max(0, width), height: max(0, height), bgra: []) }
        let step = max(2, spacing)
        var frame = solid(width: width, height: height, blue: 0, green: 0, red: 0, alpha: 255)
        frame.bgra.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for y in 0..<height {
                for x in 0..<width where x % step == 0 || y % step == 0 {
                    let p = base + (y * width + x) * 4
                    p[0] = 255; p[1] = 255; p[2] = 255
                }
            }
        }
        return frame
    }

    // MARK: comparison

    /// Compares two frames of the same size. `tolerance` is the largest channel error that still counts as equal.
    public static func compare(_ a: SDIFrame, _ b: SDIFrame, tolerance: Int = 0, includeAlpha: Bool = false) -> FrameComparison {
        guard a.width == b.width, a.height == b.height, a.bgra.count == b.bgra.count, a.bgra.count >= a.width * a.height * 4 else {
            return FrameComparison(sizesMatch: false, maxChannelError: 0, meanChannelError: 0, firstDifference: nil, pixelsOverTolerance: 0)
        }
        let pixels = a.width * a.height
        let channels = includeAlpha ? 4 : 3
        var maxError = 0, total = 0, over = 0, firstIndex = -1
        a.bgra.withUnsafeBufferPointer { pa in
            b.bgra.withUnsafeBufferPointer { pb in
                guard let x = pa.baseAddress, let y = pb.baseAddress else { return }
                (maxError, total, over, firstIndex) = compareLoop(x, y, pixels, channels, tolerance)
            }
        }
        let mean = pixels > 0 ? Double(total) / Double(pixels * channels) : 0
        let first = firstIndex >= 0 ? PixelPosition(x: firstIndex % a.width, y: firstIndex / a.width) : nil
        return FrameComparison(sizesMatch: true, maxChannelError: maxError, meanChannelError: mean, firstDifference: first, pixelsOverTolerance: over)
    }

    @_optimize(speed)
    private static func compareLoop(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>, _ pixels: Int, _ channels: Int,
                                    _ tolerance: Int) -> (Int, Int, Int, Int) {
        var maxError = 0, total = 0, over = 0, first = -1
        var p = 0
        while p < pixels {
            let i = p * 4
            var worst = 0
            var c = 0
            while c < channels {
                let d = abs(Int(a[i + c]) - Int(b[i + c]))
                total += d
                if d > worst { worst = d }
                c += 1
            }
            if worst > maxError { maxError = worst }
            if worst > tolerance {
                over += 1
                if first < 0 { first = p }
            }
            p += 1
        }
        return (maxError, total, over, first)
    }

    // MARK: building blocks

    private static func solid(width: Int, height: Int, blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) -> SDIFrame {
        let w = max(0, width), h = max(0, height)
        var row = [UInt8](repeating: 0, count: w * 4)
        for x in 0..<w { row[x * 4] = blue; row[x * 4 + 1] = green; row[x * 4 + 2] = red; row[x * 4 + 3] = alpha }
        return SDIFrame(width: w, height: h, bgra: repeatRow(row, height: h))
    }

    private static func fill(_ frame: inout SDIFrame, _ r: PatternRegion, blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) {
        let w = frame.width, h = frame.height
        let x0 = max(0, r.x), x1 = min(w, r.x + r.width), y0 = max(0, r.y), y1 = min(h, r.y + r.height)
        guard x0 < x1, y0 < y1, frame.bgra.count >= w * h * 4 else { return }
        frame.bgra.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress { fillLoop(base, w, x0, x1, y0, y1, blue, green, red, alpha) }
        }
    }

    @_optimize(speed)
    private static func fillLoop(_ base: UnsafeMutablePointer<UInt8>, _ w: Int, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int,
                                 _ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8) {
        var y = y0
        while y < y1 {
            var p = base + (y * w + x0) * 4
            var x = x0
            while x < x1 { p[0] = b; p[1] = g; p[2] = r; p[3] = a; p += 4; x += 1 }
            y += 1
        }
    }

    private static func repeatRow(_ row: [UInt8], height: Int) -> [UInt8] {
        let n = row.count
        guard n > 0, height > 0 else { return [] }
        return [UInt8](unsafeUninitializedCapacity: n * height) { out, count in
            row.withUnsafeBufferPointer { src in
                guard let s = src.baseAddress, let o = out.baseAddress else { count = 0; return }
                for y in 0..<height { memcpy(o + y * n, s, n) }
            }
            count = n * height
        }
    }
}

/// Makes colour bars with a frame counter quickly: the bars are built once and each frame is a copy with the counter
/// stamped on it. Sendable because it only holds an immutable frame.
public struct CounterFrameSource: Sendable {
    public let width: Int
    public let height: Int
    private let base: SDIFrame

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.base = TestPattern.colorBars(width: width, height: height)
    }

    public func frame(index: Int64) -> SDIFrame {
        var f = base
        TestPattern.stampCounter(index: index, into: &f)
        return f
    }
}
