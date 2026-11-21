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
    /// Fill and key on the pair of connectors that starts at the port's connector. Which of the two carries the fill is
    /// the device's to say (`SDIDeviceInfo.keyRoutes`); with no report, the fill is on the first.
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
    /// The card is there but the SDK refused or failed an operation (HW-004, KI-056). `detail` is the SDK's own words,
    /// kept for the log; it is never reported as "disconnected", because unplugging is a different problem with a different remedy.
    case hardwareFault(detail: String)

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
        case .hardwareFault(let detail):
            return "The SDI card reported a problem and did not carry out the request. \(detail) Check the card and its cables, then start the output again."
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
    /// Which connector of each keyable pair carries the fill and which the key, as the device reports it (KI-053). Empty:
    /// the device says nothing, and fill is assumed on the first connector of the pair.
    public var keyRoutes: [SDIKeyRoute]
    /// What each connector can do in the card's current profile. Empty when the device does not say.
    public var connectors: [SDIConnectorInfo]
    /// The profile state of each connector pair. Empty when the device has no profiles to report (KI-054).
    public var profiles: [SDIProfileState]

    public init(displayName: String, connectorCount: Int, supportsExternalKeying: Bool, isSimulated: Bool,
                keyRoutes: [SDIKeyRoute] = [], connectors: [SDIConnectorInfo] = [], profiles: [SDIProfileState] = []) {
        self.displayName = displayName
        self.connectorCount = connectorCount
        self.supportsExternalKeying = supportsExternalKeying
        self.isSimulated = isSimulated
        self.keyRoutes = keyRoutes
        self.connectors = connectors
        self.profiles = profiles
    }

    /// The reported route for the pair that starts at `firstConnector`, or nil when the device reports none.
    public func keyRoute(firstConnector: Int) -> SDIKeyRoute? { keyRoutes.first { $0.firstConnector == firstConnector } }

    public func profileState(forPair firstConnector: Int) -> SDIProfileState? { profiles.first { $0.firstConnector == firstConnector } }

    /// A four-connector card with fill and key, modelled on a DeckLink Duo 2. Simulated only. It reports the route it
    /// implements: fill on the first connector of each pair, key on the next.
    public static let simulatedDuo2 = simulated(reversedKeyRoutes: false)

    /// The same card with the fill on the second connector of each pair and the key on the first, so the planner, the
    /// interface and the hardware test can be exercised against the order the manual's table suggests (KI-053).
    public static let simulatedDuo2WithReversedKeyRoute = simulated(reversedKeyRoutes: true)

    private static func simulated(reversedKeyRoutes reversed: Bool) -> SDIDeviceInfo {
        let routes = [1, 3].map {
            SDIKeyRoute(firstConnector: $0, fillConnector: reversed ? $0 + 1 : $0, keyConnector: reversed ? $0 : $0 + 1, source: .simulator)
        }
        let connectors = (1...4).map { c -> SDIConnectorInfo in
            let route = routes.first { $0.fillConnector == c || $0.keyConnector == c }
            return SDIConnectorInfo(connector: c, canOutput: true, canInput: true, keyRole: route.map { $0.fillConnector == c ? .fill : .key })
        }
        return SDIDeviceInfo(displayName: "Simulated SDI card (4 connectors)", connectorCount: 4, supportsExternalKeying: true, isSimulated: true,
                             keyRoutes: routes, connectors: connectors)
    }
}

public protocol SDIDevice: Sendable {
    associatedtype Port: SDIOutputPort
    /// The capture side (HWTEST-001). Defaults to a port that refuses everything, so devices without it keep compiling.
    associatedtype InputPort: SDIInputPort = UnsupportedSDIInputPort
    var info: SDIDeviceInfo { get }
    var isConnected: Bool { get }
    /// Opens one connector. Throws if it does not exist, is already open, or is carrying another port's key.
    func openOutput(connector: Int) throws -> Port
    /// Opens one connector for capture. Throws if it does not exist, is already open, or the device cannot capture.
    func openInput(connector: Int) throws -> InputPort
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
    /// The fewest frames the device wants scheduled before playback starts (the SDK's minimum preroll), or 0 when it does
    /// not say. The output prerolls at least this many (FIX-C S11). Defaults to 0, so existing ports keep compiling.
    var minimumPrerollFrames: Int { get }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? { get set }
    /// Called when the device fails underneath the port, for example when it is unplugged.
    var onFailure: (@Sendable (SDIError) -> Void)? { get set }
}

extension SDIOutputPort {
    public var minimumPrerollFrames: Int { 0 }
}
