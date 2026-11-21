// HWTEST-001: collecting what an input port delivers, and the arithmetic on it (missing, repeated and out-of-order
// frames, delay, pixel error). Kept apart from the steps so it can be read on its own.
import Foundation
import SDIEngine

/// Collects frames and signal changes from one input port. The port's callback thread calls `receive`; the step reads
/// totals from its own task. `@unchecked Sendable`: every stored property is only touched while holding `lock`.
final class CaptureCollector: @unchecked Sendable {
    struct Totals {
        var received = 0
        var unreadable = 0
        var missing = 0
        var repeated = 0
        var outOfOrder = 0
        var delays: [Int] = []
        var comparedFrames = 0
        var maxPixelError = 0
        var meanErrorSum = 0.0
        var firstDifference: PixelPosition?
        var detectedMode: SDIVideoMode?
        var signal: SDIInputSignal = .noSignal
        var signalChanges = 0
        var lastFrame: SDIFrame?
        var lastTimestamp: Int64?
        var timestampGaps = 0
    }

    private let lock = NSLock()
    private var totals = Totals()
    private var previousIndex: Int64?
    private var worstFrameError = -1
    private let source: CounterFrameSource?
    private let keepLastFrame: Bool
    private let processed: @Sendable () -> Int
    /// A pixel comparison is made for one frame in `sampleEvery`, starting with the fifth.
    static let sampleEvery = 60
    static let pixelTolerance = 24

    /// - Parameters:
    ///   - source: when set, each frame's counter is decoded and a sample of frames is compared with the pattern sent.
    ///   - processed: how many frames the output has finished with so far, read when a frame arrives (for the delay).
    init(source: CounterFrameSource?, keepLastFrame: Bool = false, processed: @escaping @Sendable () -> Int = { 0 }) {
        self.source = source
        self.keepLastFrame = keepLastFrame
        self.processed = processed
    }

    var snapshot: Totals { lock.withLock { totals } }

    func signalChanged(_ s: SDIInputSignal) {
        lock.withLock {
            totals.signal = s
            totals.signalChanges += 1
            if case .locked(let m) = s { totals.detectedMode = m }
        }
    }

    func receive(_ captured: SDICapturedFrame) {
        let count: Int = lock.withLock {
            totals.received += 1
            totals.detectedMode = captured.mode
            if case .noSignal = totals.signal { totals.signal = .locked(captured.mode) }
            if let t = captured.hardwareTimestamp {
                if let last = totals.lastTimestamp, t - last > captured.mode.frameDurationValue + captured.mode.frameDurationValue / 2 { totals.timestampGaps += 1 }
                totals.lastTimestamp = t
            }
            if keepLastFrame { totals.lastFrame = captured.frame }
            return totals.received
        }
        guard let source else { return }
        guard let index = TestPattern.decodeFrameIndex(from: captured.frame) else {
            lock.withLock { totals.unreadable += 1 }
            return
        }
        let finished = processed()
        lock.withLock {
            if let p = previousIndex {
                if index == p { totals.repeated += 1 } else if index < p { totals.outOfOrder += 1 } else if index > p + 1 { totals.missing += Int(index - p - 1) }
            }
            previousIndex = index          // judged against the frame before, so one stray frame is one fault, not hundreds
            totals.delays.append(finished - 1 - Int(index))
        }
        if count % Self.sampleEvery == 5 {
            let comparison = TestPattern.compare(captured.frame, source.frame(index: index), tolerance: Self.pixelTolerance)
            lock.withLock {
                totals.comparedFrames += 1
                totals.meanErrorSum += comparison.meanChannelError
                if comparison.maxChannelError > totals.maxPixelError { totals.maxPixelError = comparison.maxChannelError }
                if comparison.maxChannelError > worstFrameError, let first = comparison.firstDifference {
                    worstFrameError = comparison.maxChannelError
                    totals.firstDifference = first
                } else if totals.firstDifference == nil { totals.firstDifference = comparison.firstDifference }
            }
        }
    }
}

enum CaptureMath {
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// Mean B, G, R of a small block around a pixel.
    static func block(_ frame: SDIFrame, x: Int, y: Int, radius: Int = 2) -> (b: Int, g: Int, r: Int) {
        var b = 0, g = 0, r = 0, n = 0
        for yy in max(0, y - radius)...min(frame.height - 1, y + radius) {
            for xx in max(0, x - radius)...min(frame.width - 1, x + radius) {
                let i = (yy * frame.width + xx) * 4
                guard i + 2 < frame.bgra.count else { continue }
                b += Int(frame.bgra[i]); g += Int(frame.bgra[i + 1]); r += Int(frame.bgra[i + 2]); n += 1
            }
        }
        guard n > 0 else { return (0, 0, 0) }
        return (b / n, g / n, r / n)
    }
}
