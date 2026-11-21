// HWTEST-001: the input (capture) side of the SDI abstraction. Kept small and close to what a capture card offers:
// enable a connector, optionally with a fixed mode or with auto-detect, receive frames with a hardware timestamp,
// learn when the signal appears or disappears, disable. Nothing here knows about any vendor SDK.
import Foundation

/// What a capture connector sees on its cable.
public enum SDIInputSignal: Equatable, Sendable {
    /// Nothing usable: no cable, no source, or a source in a mode the port was not set to accept.
    case noSignal
    /// A signal in this mode is present.
    case locked(SDIVideoMode)
}

/// One captured frame, converted to the same BGRA layout `SDIFrame` uses everywhere.
public struct SDICapturedFrame: Equatable, Sendable {
    public var frame: SDIFrame
    /// How many frames this port has delivered since it was enabled: 0 for the first. A frame the device lost
    /// does not consume a number, so use `hardwareTimestamp` to see gaps.
    public var frameNumber: Int64
    /// The device clock when the frame arrived, in units of `1 / mode.timeScale` seconds, or nil when the device
    /// cannot say. Consecutive frames of a clean signal differ by `mode.frameDurationValue`.
    public var hardwareTimestamp: Int64?
    /// The mode the device detected (or was told to expect) for this frame.
    public var mode: SDIVideoMode

    public init(frame: SDIFrame, frameNumber: Int64, hardwareTimestamp: Int64?, mode: SDIVideoMode) {
        self.frame = frame
        self.frameNumber = frameNumber
        self.hardwareTimestamp = hardwareTimestamp
        self.mode = mode
    }
}

/// One capture connector.
///
/// Threading contract (the same as `SDIOutputPort`): `onFrameReceived`, `onSignalChange` and `onFailure` may be called
/// from any thread, one at a time, and never while the port holds an internal lock, so a handler may call back into
/// the port. Set handlers before `enable`. Handlers must return quickly: copy what you need and leave.
public protocol SDIInputPort: AnyObject, Sendable {
    var connector: Int { get }
    /// Whether the device can capture this mode on this connector.
    func supports(mode: SDIVideoMode) -> Bool
    /// Starts capture. `mode` nil means auto-detect: the port reports whatever mode the cable carries. A fixed
    /// mode means only that mode is accepted; a different one reads as `.noSignal`.
    func enable(mode: SDIVideoMode?) throws
    /// Stops capture. Safe to call at any time, more than once.
    func disable()
    /// Releases the connector. The port is unusable afterwards.
    func close()
    /// The signal state now. `.noSignal` before `enable` and after `disable`.
    var signal: SDIInputSignal { get }
    var onFrameReceived: (@Sendable (SDICapturedFrame) -> Void)? { get set }
    /// Called when `signal` changes while capturing.
    var onSignalChange: (@Sendable (SDIInputSignal) -> Void)? { get set }
    /// Called when the device fails underneath the port, for example when it is unplugged.
    var onFailure: (@Sendable (SDIError) -> Void)? { get set }
}

/// The input port of a device that has no capture side. `SDIDevice.InputPort` defaults to it, so a device written
/// before the input side existed keeps compiling and simply refuses every input.
public final class UnsupportedSDIInputPort: SDIInputPort {
    public let connector: Int
    private init(connector: Int) { self.connector = connector }
    public func supports(mode: SDIVideoMode) -> Bool { false }
    public func enable(mode: SDIVideoMode?) throws { throw SDIError.connectorUnavailable(connector) }
    public func disable() {}
    public func close() {}
    public var signal: SDIInputSignal { .noSignal }
    public var onFrameReceived: (@Sendable (SDICapturedFrame) -> Void)? { get { nil } set {} }
    public var onSignalChange: (@Sendable (SDIInputSignal) -> Void)? { get { nil } set {} }
    public var onFailure: (@Sendable (SDIError) -> Void)? { get { nil } set {} }
}

extension SDIDevice where InputPort == UnsupportedSDIInputPort {
    public func openInput(connector: Int) throws -> UnsupportedSDIInputPort {
        throw SDIError.connectorUnavailable(connector)
    }
}

/// Faults the simulator can inject on its BNC cables, for testing a test kit against a card that misbehaves.
public struct SimulatedFaults: Equatable, Sendable {
    /// The cable loses every Nth frame (3 loses the 3rd, 6th, 9th ...). Nil or less than 1: none.
    public var dropEveryNthFrame: Int?
    /// A keyed pair arrives the wrong way round: the key on the fill connector, the fill on the key connector.
    public var swapFillAndKey: Bool
    /// The picture arrives this many pixels to the right (the vacated columns are black).
    public var shiftPixels: Int
    /// The input detects this mode instead of the one that was sent.
    public var wrongMode: SDIVideoMode?

    public init(dropEveryNthFrame: Int? = nil, swapFillAndKey: Bool = false, shiftPixels: Int = 0, wrongMode: SDIVideoMode? = nil) {
        self.dropEveryNthFrame = dropEveryNthFrame
        self.swapFillAndKey = swapFillAndKey
        self.shiftPixels = shiftPixels
        self.wrongMode = wrongMode
    }

    public static let none = SimulatedFaults()
}
