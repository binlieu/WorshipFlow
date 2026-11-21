// OUT-001: output target contract and the video hand-off types.
import Foundation
import Metal
import Domain

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
    /// Display-link ticks and GPU submissions, for diagnosing an output that presents nothing.
    var diagnostics: String { get }
    /// True while the output's window is running but covered, minimised or on an inactive Space, so no frames
    /// are presented (KI-008). Reported as "hidden", not as a stall.
    var isOccluded: Bool { get }
    /// Called on the main actor whenever the status changes (including when the window is closed or the display disappears).
    var onStatusChange: (@MainActor (OutputStatus) -> Void)? { get set }
    func start() throws
    func stop()
}

extension OutputTarget {
    public var isOccluded: Bool { false }
}
