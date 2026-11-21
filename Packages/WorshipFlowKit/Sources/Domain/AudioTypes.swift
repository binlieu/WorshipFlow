// MEDIA-005 / MEDIA-006: the two small values the audio slice passes between the engine, the operator model and the
// views. Foundation only.
import Foundation

/// A sound output device as the operating system lists it.
public struct AudioOutputDevice: Sendable, Equatable, Hashable, Identifiable {
    /// The stable identifier (Core Audio's device UID). It is what the operator's choice stores; names can repeat.
    public let uid: String
    public var name: String
    public var channelCount: Int
    /// True for the device the system currently uses by default.
    public var isDefault: Bool
    public var id: String { uid }

    public init(uid: String, name: String, channelCount: Int, isDefault: Bool) {
        self.uid = uid
        self.name = name
        self.channelCount = channelCount
        self.isDefault = isDefault
    }
}

/// Peak and RMS per channel, 0...1 (a signal can exceed 1 before clipping; callers clamp for display).
public struct AudioLevels: Sendable, Equatable {
    public var peak: [Float]
    public var rms: [Float]

    public init(peak: [Float], rms: [Float]) {
        self.peak = peak
        self.rms = rms
    }

    /// Nothing sounding. Two channels is the least the interface draws.
    public static func silent(channels: Int = 2) -> AudioLevels {
        let n = max(1, channels)
        return AudioLevels(peak: [Float](repeating: 0, count: n), rms: [Float](repeating: 0, count: n))
    }

    public var channelCount: Int { peak.count }

    /// The louder of each channel of the two, for several cues sounding at once.
    public func combined(with other: AudioLevels) -> AudioLevels {
        let n = max(channelCount, other.channelCount)
        func pick(_ a: [Float], _ b: [Float], _ i: Int) -> Float { max(i < a.count ? a[i] : 0, i < b.count ? b[i] : 0) }
        return AudioLevels(peak: (0..<n).map { pick(peak, other.peak, $0) }, rms: (0..<n).map { pick(rms, other.rms, $0) })
    }
}
