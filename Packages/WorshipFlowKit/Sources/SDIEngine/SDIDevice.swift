// HW-001 / SCRN-11: the device abstraction a real DeckLink bridge will implement later.
// Nothing here knows about any vendor SDK.
import Foundation

/// One frame of BGRA pixels, premultiplied, as the compositor produces them.
public struct SDIFrame: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var bgra: [UInt8]
    public init(width: Int, height: Int, bgra: [UInt8]) {
        self.width = width
        self.height = height
        self.bgra = bgra
    }
}

public enum SDIKeying: Equatable, Sendable {
    case none
    /// Fill on the connector, key on the next one.
    case external(fillAlphaMode: AlphaMode)
}

public struct SDIFrameCompletion: Equatable, Sendable {
    public var frameIndex: Int64
    public var result: SDICompletionResult
    public init(frameIndex: Int64, result: SDICompletionResult) {
        self.frameIndex = frameIndex
        self.result = result
    }
}

public enum SDIError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case deviceDisconnected
    case notEnabled
    case unsupportedMode(String)
    case connectorUnavailable(Int)
    case keyingUnavailable(connector: Int)
    /// The port was closed, or belongs to an earlier connection of the device.
    case portClosed

    public var description: String {
        switch self {
        case .deviceDisconnected:
            return "The SDI card was disconnected. Reconnect it, then start the output again."
        case .notEnabled:
            return "The SDI output has not been set up yet. Choose a video mode before sending frames."
        case .unsupportedMode(let name):
            return "The SDI card does not support the video mode \(name)."
        case .connectorUnavailable(let c):
            return "SDI connector \(c) is not available. It does not exist or is already in use."
        case .keyingUnavailable(let c):
            return "Fill and key cannot be used on SDI connector \(c). Start it on connector 1 or 3 with the next connector free."
        case .portClosed:
            return "That SDI output was closed. Open it again to continue."
        }
    }

    public var errorDescription: String? { description }
}

public struct SDIDeviceInfo: Equatable, Sendable {
    public var displayName: String
    public var connectorCount: Int
    public var supportsExternalKeying: Bool
    /// True for anything that is not real hardware, so a simulator is never mistaken for a card.
    public var isSimulated: Bool

    public init(displayName: String, connectorCount: Int, supportsExternalKeying: Bool, isSimulated: Bool) {
        self.displayName = displayName
        self.connectorCount = connectorCount
        self.supportsExternalKeying = supportsExternalKeying
        self.isSimulated = isSimulated
    }

    /// A four-connector card with fill and key, modelled on a DeckLink Duo 2. Simulated only.
    public static let simulatedDuo2 = SDIDeviceInfo(displayName: "Simulated SDI card (4 connectors)", connectorCount: 4, supportsExternalKeying: true, isSimulated: true)
}

public protocol SDIDevice: Sendable {
    associatedtype Port: SDIOutputPort
    var info: SDIDeviceInfo { get }
    var isConnected: Bool { get }
    /// Opens one connector. Throws if it does not exist, is already open, or is carrying another port's key.
    func openOutput(connector: Int) throws -> Port
}

/// One output connector (or fill-and-key pair).
///
/// Threading contract: `onFrameCompleted` and `onFailure` may be called from any thread, one at a time,
/// and never while the port holds an internal lock, so a handler may call back into the port.
public protocol SDIOutputPort: AnyObject, Sendable {
    var connector: Int { get }
    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws
    func disable()
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws
    func startPlayback(atFrame frameIndex: Int64)
    /// Stops playback; frames still queued are reported as flushed.
    func stopPlayback()
    func close()
    var bufferedFrameCount: Int { get }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? { get set }
    /// Called when the device fails underneath the port, for example when it is unplugged.
    var onFailure: (@Sendable (SDIError) -> Void)? { get set }
}
