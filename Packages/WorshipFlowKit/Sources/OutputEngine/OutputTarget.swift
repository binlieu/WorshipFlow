// OUT-001: output target contract and the video hand-off types.
import Foundation
import Metal
import Domain
import SDIEngine

/// Supplies the scene an output should draw. Called on the output's render thread for every frame.
public typealias SceneProvider = @Sendable () -> SceneDescription

public enum OutputStatus: Sendable, Equatable {
    case idle
    case running
    /// The output stopped. `reason` is nil for an operator stop and an actionable message otherwise.
    case stopped(reason: String?)
}

/// A decoded video frame as a Metal texture. `keepAlive` must stay referenced until the GPU has finished with it.
public struct VideoTexture {
    public let texture: MTLTexture
    public let keepAlive: AnyObject

    public init(texture: MTLTexture, keepAlive: AnyObject) {
        self.texture = texture
        self.keepAlive = keepAlive
    }
}

/// One per render thread. Never called from the main thread.
public protocol VideoTextureProvider: AnyObject {
    func currentTexture() -> VideoTexture?
}

/// Shared video source; each output asks it for its own per-thread texture provider.
public protocol VideoSourceFactory: Sendable {
    func makeTextureProvider(device: MTLDevice) throws -> any VideoTextureProvider
}

@MainActor
public protocol OutputTarget: AnyObject {
    var name: String { get }
    var status: OutputStatus { get }
    /// Display refresh rate in Hz as reported by the screen the output is on (0 if unknown).
    var refreshRate: Double { get }
    var statistics: FrameStatistics { get }
    var lastRenderError: String? { get }
    /// Image files the output could not draw (missing or unreadable), sorted. For the operator window (OUT-003).
    var unavailableImagePaths: [String] { get }
    /// Display-link ticks and GPU submissions, for diagnosing an output that presents nothing.
    var diagnostics: String { get }
    /// True while the output's window is running but covered, minimised or on an inactive Space, so no frames
    /// are presented (KI-008). Reported as "hidden", not as a stall.
    var isOccluded: Bool { get }
    /// Layers the output skipped because they could not be drawn, de-duplicated; empty when the last frame had none (R2).
    var renderProblems: [String] { get }
    /// What only an SDI output has to say (HW-002): health, repeated frames, warnings. Nil for displays and windows.
    var sdiReport: SDIOutputReport? { get }
    /// True when the output stopped because its device went away (an SDI card unplugged), so the coordinator should
    /// bring it back when that device returns (KI-012).
    var stoppedByDeviceLoss: Bool { get }
    /// Called on the main actor whenever the status changes (including when the window is closed or the display disappears).
    var onStatusChange: (@MainActor (OutputStatus) -> Void)? { get set }
    func start() throws
    func stop()
}

extension OutputTarget {
    public var isOccluded: Bool { false }
    public var unavailableImagePaths: [String] { [] }
    public var renderProblems: [String] { [] }
    public var sdiReport: SDIOutputReport? { nil }
    public var stoppedByDeviceLoss: Bool { false }
}

/// The SDI-specific part of a screen's readout (HW-002).
public struct SDIOutputReport: Sendable, Equatable {
    public var health: SDIHealth
    /// Frames where nothing new was ready in time and the previous frame was sent again.
    public var repeatedFrames: Int
    /// For example "Nothing will key: background is opaque". Empty when there is nothing to warn about.
    public var warnings: [String]
    /// True when the card is a simulator, so the interface can say so wherever it is shown.
    public var isSimulated: Bool
    public var modeName: String

    public init(health: SDIHealth, repeatedFrames: Int, warnings: [String], isSimulated: Bool, modeName: String) {
        self.health = health
        self.repeatedFrames = repeatedFrames
        self.warnings = warnings
        self.isSimulated = isSimulated
        self.modeName = modeName
    }
}
