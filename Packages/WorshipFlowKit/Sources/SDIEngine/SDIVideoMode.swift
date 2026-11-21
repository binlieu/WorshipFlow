// HW-001 / SCRN-11: the video modes the SDI output offers. Nothing above HD (NG-1).
import Foundation

/// A broadcast video mode. 59.94 and 60 are different modes (HW-09): the frame duration is an exact
/// rational (`frameDurationValue / timeScale` seconds), never a rounded frame rate.
public struct SDIVideoMode: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// Frame duration numerator, in `timeScale` units.
    public let frameDurationValue: Int64
    public let timeScale: Int64
    public let isInterlaced: Bool
    public let name: String

    /// Frames (not fields) per second.
    public var framesPerSecond: Double { Double(timeScale) / Double(frameDurationValue) }

    public init(width: Int, height: Int, frameDurationValue: Int64, timeScale: Int64, isInterlaced: Bool = false, name: String) {
        self.width = width
        self.height = height
        self.frameDurationValue = frameDurationValue
        self.timeScale = timeScale
        self.isInterlaced = isInterlaced
        self.name = name
    }

    public static let hd1080p5994 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 60000, name: "1080p59.94")
    public static let hd1080p60 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 60000, name: "1080p60")
    public static let hd1080p50 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 50000, name: "1080p50")
    public static let hd1080p2997 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 30000, name: "1080p29.97")
    public static let hd1080p30 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 30000, name: "1080p30")
    public static let hd1080p25 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 25000, name: "1080p25")
    /// 59.94 fields per second, so 29.97 frames per second.
    public static let hd1080i5994 = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 30000, isInterlaced: true, name: "1080i59.94")
    public static let hd720p5994 = SDIVideoMode(width: 1280, height: 720, frameDurationValue: 1001, timeScale: 60000, name: "720p59.94")
    public static let hd720p60 = SDIVideoMode(width: 1280, height: 720, frameDurationValue: 1000, timeScale: 60000, name: "720p60")
    public static let hd720p50 = SDIVideoMode(width: 1280, height: 720, frameDurationValue: 1000, timeScale: 50000, name: "720p50")

    public static let allKnown: [SDIVideoMode] = [
        .hd1080p5994, .hd1080p60, .hd1080p50, .hd1080p2997, .hd1080p30, .hd1080p25,
        .hd1080i5994, .hd720p5994, .hd720p60, .hd720p50,
    ]
}
