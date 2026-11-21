// MEDIA-005: the arithmetic behind the level meter, kept free of AVFoundation so it can be tested with plain arrays.
// The audio engine's tap feeds buffers in, off the main thread; the main actor takes the result about 20 times a second.
import Foundation
import os
import Domain

/// Peak and RMS per channel over everything added since the last `takeLevels()`.
public struct LevelAccumulator: Sendable {
    private var peaks: [Float]
    private var sums: [Double]
    private var counts: [Int]

    /// A meter with no channels still reports two: the least the interface draws.
    public init(channels: Int) {
        let n = channels <= 0 ? 2 : channels
        peaks = [Float](repeating: 0, count: n)
        sums = [Double](repeating: 0, count: n)
        counts = [Int](repeating: 0, count: n)
    }

    public var channelCount: Int { peaks.count }

    /// True when some sample has been added since the last take.
    public var hasSamples: Bool { counts.contains { $0 > 0 } }

    /// Adds samples for one channel. A channel the meter does not have is ignored; a sample that is not finite counts
    /// as silence. Does not allocate.
    public mutating func add(_ samples: UnsafeBufferPointer<Float>, channel: Int) {
        guard channel >= 0, channel < peaks.count else { return }
        var peak = peaks[channel]
        var sum = sums[channel]
        for s in samples {
            let v = s.isFinite ? s : 0
            let a = abs(v)
            if a > peak { peak = a }
            sum += Double(v) * Double(v)
        }
        peaks[channel] = peak
        sums[channel] = sum
        counts[channel] += samples.count
    }

    public mutating func add(_ samples: [Float], channel: Int) {
        samples.withUnsafeBufferPointer { add($0, channel: channel) }
    }

    /// The levels since the last take, and starts again from silence.
    public mutating func takeLevels() -> AudioLevels {
        let rms = (0..<peaks.count).map { counts[$0] > 0 ? Float((sums[$0] / Double(counts[$0])).squareRoot()) : 0 }
        let result = AudioLevels(peak: peaks, rms: rms)
        for i in 0..<peaks.count { peaks[i] = 0; sums[i] = 0; counts[i] = 0 }
        return result
    }
}

/// Where the audio tap leaves its measurements for the main actor to pick up. The tap never touches an actor: it only
/// takes this lock for the few instructions it needs to add one buffer's worth of numbers.
final class LevelBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: LevelAccumulator(channels: 2))

    func add(_ samples: UnsafeBufferPointer<Float>, channel: Int) {
        // The buffer is only read inside this call, so handing it to the lock's closure is safe.
        state.withLockUnchecked { $0.add(samples, channel: channel) }
    }

    /// The levels since the last take, or nil when the tap delivered nothing in between (so the meter can hold its value
    /// instead of flickering to zero between buffers).
    func take() -> AudioLevels? { state.withLock { $0.hasSamples ? $0.takeLevels() : nil } }
}
