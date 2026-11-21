// HW-003 / SCRN-11: one SDI input (capture), needed for the loopback hardware test.
//
// Conforms to SDIInputPort from SDIEngine (HWTEST-001). Status: Implemented, Not Verified. Frames arrive as BGRA,
// converted by the SDK when the signal is YCbCr. Handlers run on SDK threads.
import DeckLinkC
import Foundation
import SDIEngine
import Synchronization

/// The format the card detected on the input.
public struct DeckLinkDetectedFormat: Equatable, Sendable {
    /// The matching app video mode, or nil if the card sees a mode the app does not offer.
    public var mode: SDIVideoMode?
    public var width: Int
    public var height: Int
    public var frameDurationValue: Int64
    public var timeScale: Int64
    public var isInterlaced: Bool
    /// The raw BMDDisplayMode code.
    public var displayModeCode: UInt32
}

/// One capture connector as an `SDIInputPort`. Frames arrive as BGRA (converted by the SDK when the signal is YCbCr).
public final class DeckLinkInputPort: SDIInputPort {
    public let connector: Int
    private let device: DeckLinkDevice
    private let generation: Int

    private struct State {
        var bridge: DLBInput?
        var closed = false
        var failure: SDIError?
        var lastDetail: String?
        var hasSignal = false
        /// The mode frames are in: the fixed mode, or the last detected one (nil if detected but not an app mode).
        var mode: SDIVideoMode?
        var frameNumber: Int64 = 0
        var framesWithoutMode: Int64 = 0
        var onFrame: (@Sendable (SDICapturedFrame) -> Void)?
        var onSignal: (@Sendable (SDIInputSignal) -> Void)?
        var onFormat: (@Sendable (DeckLinkDetectedFormat) -> Void)?
        var onFailure: (@Sendable (SDIError) -> Void)?
    }

    private let state = Mutex(State())

    init(device: DeckLinkDevice, connector: Int, generation: Int) {
        self.device = device
        self.connector = connector
        self.generation = generation
    }

    // MARK: SDIInputPort

    public var onFrameReceived: (@Sendable (SDICapturedFrame) -> Void)? {
        get { state.withLock { $0.onFrame } }
        set { state.withLock { $0.onFrame = newValue } }
    }

    public var onSignalChange: (@Sendable (SDIInputSignal) -> Void)? {
        get { state.withLock { $0.onSignal } }
        set { state.withLock { $0.onSignal = newValue } }
    }

    public var onFailure: (@Sendable (SDIError) -> Void)? {
        get { state.withLock { $0.onFailure } }
        set { state.withLock { $0.onFailure = newValue } }
    }

    /// `.locked` only while frames carry a signal and their mode is one the app offers.
    public var signal: SDIInputSignal {
        state.withLock { Self.signal(hasSignal: $0.hasSignal, mode: $0.mode, running: $0.bridge != nil) }
    }

    public func supports(mode: SDIVideoMode) -> Bool {
        guard let code = DeckLinkModeMapping.displayMode(for: mode), (try? checkUsable()) != nil,
              let sub = try? device.resolveInput(connector: connector), let probe = try? sub.openInput() else { return false }
        defer { probe.close() }
        return probe.supportsDisplayMode(code)
    }

    /// Starts capture. `nil` auto-detects the format (and assumes 1080p59.94 until the card reports one); a fixed mode
    /// turns detection off, so any other signal shows as no signal.
    public func enable(mode: SDIVideoMode?) throws {
        try checkUsable()
        let initial = mode ?? .hd1080p5994
        guard let code = DeckLinkModeMapping.displayMode(for: initial) else { throw SDIError.unsupportedMode(initial.name) }
        disable()
        let sub = try device.resolveInput(connector: connector)
        let bridge: DLBInput
        do {
            bridge = try sub.openInput()
        } catch {
            record(error)
            throw DeckLinkMapping.sdiError(error, context: .open(connector: connector))
        }
        bridge.frameHandler = { [weak self] bytes, count, width, height, rowBytes, timestamp in
            self?.deliver(bytes: bytes, count: count, width: Int(width), height: Int(height), rowBytes: rowBytes, timestamp: timestamp)
        }
        bridge.signalHandler = { [weak self] present in self?.signalChanged(present) }
        bridge.formatHandler = { [weak self] code, width, height, duration, scale, interlaced in
            self?.formatDetected(code: code, width: Int(width), height: Int(height), duration: duration, scale: scale, interlaced: interlaced)
        }
        bridge.failureHandler = { [weak self] error in self?.fail(error) }
        state.withLock {
            $0.mode = initial
            $0.hasSignal = false
            $0.frameNumber = 0
            $0.framesWithoutMode = 0
        }
        do {
            try bridge.start(withInitialDisplayMode: code, detectFormat: mode == nil)
        } catch {
            bridge.close()
            record(error)
            throw DeckLinkMapping.sdiError(error, context: .enable(connector: connector, modeName: initial.name, keyed: false))
        }
        state.withLock { $0.bridge = bridge }
    }

    public func disable() {
        let bridge = state.withLock { s -> DLBInput? in
            let b = s.bridge
            s.bridge = nil
            s.hasSignal = false
            return b
        }
        bridge?.stop()
        bridge?.close()
    }

    public func close() {
        disable()
        state.withLock { $0.closed = true }
        device.release(connector: connector, port: ObjectIdentifier(self))
    }

    // MARK: Extra data

    /// Called when the card detects a format, with the SDK's own numbers. Not part of `SDIInputPort`.
    public var onFormatDetected: (@Sendable (DeckLinkDetectedFormat) -> Void)? {
        get { state.withLock { $0.onFormat } }
        set { state.withLock { $0.onFormat = newValue } }
    }

    public var lastErrorDetail: String? { state.withLock { $0.lastDetail } }

    /// Frames that arrived in a mode the app does not offer and were therefore not delivered.
    public var framesWithoutKnownMode: Int64 { state.withLock { $0.framesWithoutMode } }

    public func statusSnapshot() -> DeckLinkSnapshotValue {
        let (bridge, hasSignal, mode, frames) = state.withLock { ($0.bridge, $0.hasSignal, $0.mode, $0.frameNumber) }
        var fields: [String: DeckLinkSnapshotValue] = [
            "connector": .int(Int64(connector)),
            "running": .bool(bridge != nil),
            "signal": .bool(hasSignal),
            "mode": .string(mode?.name ?? "none"),
            "framesDelivered": .int(frames),
            "framesWithoutKnownMode": .int(framesWithoutKnownMode),
        ]
        if let bridge { fields["bridge"] = DeckLinkSnapshotValue(foundation: bridge.statusSnapshot()) }
        if let detail = lastErrorDetail { fields["lastError"] = .string(detail) }
        return .object(fields)
    }

    // MARK: Pure helpers

    static func signal(hasSignal: Bool, mode: SDIVideoMode?, running: Bool) -> SDIInputSignal {
        guard running, hasSignal, let mode else { return .noSignal }
        return .locked(mode)
    }

    /// The card's reference clock reading (nanoseconds) in units of 1/timeScale seconds, as `SDICapturedFrame` wants it.
    static func timestamp(nanoseconds: Int64, timeScale: Int64) -> Int64? {
        guard nanoseconds >= 0, timeScale > 0 else { return nil }
        let seconds = nanoseconds / 1_000_000_000
        let remainder = nanoseconds % 1_000_000_000
        let (whole, overflow) = seconds.multipliedReportingOverflow(by: timeScale)
        guard !overflow else { return nil }
        return whole + remainder * timeScale / 1_000_000_000
    }

    // MARK: Callbacks from the bridge (SDK threads)

    private func deliver(bytes: UnsafePointer<UInt8>, count: Int, width: Int, height: Int, rowBytes: Int, timestamp: Int64) {
        let (handler, mode, number) = state.withLock { s -> ((@Sendable (SDICapturedFrame) -> Void)?, SDIVideoMode?, Int64) in
            guard let mode = s.mode else { s.framesWithoutMode += 1; return (nil, nil, 0) }
            let n = s.frameNumber
            if s.onFrame != nil { s.frameNumber += 1 }
            return (s.onFrame, mode, n)
        }
        guard let handler, let mode else { return }
        let raw = UnsafeRawBufferPointer(start: bytes, count: count)
        guard let packed = DeckLinkFramePacking.tightBGRA(from: raw, width: width, height: height, rowBytes: rowBytes) else { return }
        handler(SDICapturedFrame(frame: SDIFrame(width: width, height: height, bgra: packed), frameNumber: number,
                                 hardwareTimestamp: Self.timestamp(nanoseconds: timestamp, timeScale: mode.timeScale), mode: mode))
    }

    private func signalChanged(_ present: Bool) {
        let (handler, value) = state.withLock { s -> ((@Sendable (SDIInputSignal) -> Void)?, SDIInputSignal) in
            s.hasSignal = present
            return (s.onSignal, Self.signal(hasSignal: present, mode: s.mode, running: s.bridge != nil))
        }
        handler?(value)
    }

    private func formatDetected(code: UInt32, width: Int, height: Int, duration: Int64, scale: Int64, interlaced: Bool) {
        let detected = DeckLinkModeMapping.videoMode(forDisplayMode: code)
        let (formatHandler, signalHandler, value) = state.withLock { s -> ((@Sendable (DeckLinkDetectedFormat) -> Void)?, (@Sendable (SDIInputSignal) -> Void)?, SDIInputSignal?) in
            let before = Self.signal(hasSignal: s.hasSignal, mode: s.mode, running: s.bridge != nil)
            s.mode = detected
            let after = Self.signal(hasSignal: s.hasSignal, mode: s.mode, running: s.bridge != nil)
            return (s.onFormat, s.onSignal, before == after ? nil : after)
        }
        formatHandler?(DeckLinkDetectedFormat(mode: detected, width: width, height: height, frameDurationValue: duration, timeScale: scale,
                                              isInterlaced: interlaced, displayModeCode: code))
        if let value { signalHandler?(value) }
    }

    private func fail(_ error: Error) {
        let mapped = DeckLinkMapping.sdiError(error, context: .runtime)
        let handler: (@Sendable (SDIError) -> Void)? = state.withLock { s in
            s.failure = mapped
            s.lastDetail = DeckLinkMapping.detail(error)
            return s.onFailure
        }
        handler?(mapped)
    }

    private func record(_ error: Error) {
        let detail = DeckLinkMapping.detail(error)
        state.withLock { $0.lastDetail = detail }
    }

    private func checkUsable() throws {
        let (closed, failure) = state.withLock { ($0.closed, $0.failure) }
        if closed { throw SDIError.portClosed }
        guard device.isConnected else { throw SDIError.deviceDisconnected }
        if !device.isCurrent(generation: generation) { throw SDIError.portClosed }
        if let failure { throw failure }
    }
}

/// Row handling for frames that come from the card with a row stride larger than the picture width.
public enum DeckLinkFramePacking {
    /// Copies `height` rows of `width*4` bytes out of a buffer whose rows are `rowBytes` apart. Nil if the buffer is
    /// too small or the arguments are impossible.
    public static func tightBGRA(from source: UnsafeRawBufferPointer, width: Int, height: Int, rowBytes: Int) -> [UInt8]? {
        guard width > 0, height > 0, rowBytes >= width * 4, let base = source.baseAddress else { return nil }
        let needed = (height - 1) * rowBytes + width * 4
        guard source.count >= needed else { return nil }
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { destination in
            guard let to = destination.baseAddress else { return }
            for y in 0..<height {
                to.advanced(by: y * width * 4).copyMemory(from: base.advanced(by: y * rowBytes), byteCount: width * 4)
            }
        }
        return out
    }

    /// Packs premultiplied BGRA (top row first, no padding) into a destination whose rows are `destinationRowBytes`
    /// apart, through the same routine the bridge uses for SDK frame buffers. Returns false for impossible arguments.
    /// Padding bytes in the destination are left as they were.
    public static func pack(bgra: [UInt8], width: Int, height: Int, into destination: UnsafeMutableRawBufferPointer,
                            destinationRowBytes: Int, straightAlpha: Bool = false) -> Bool {
        guard width > 0, height > 0, bgra.count == width * height * 4, destinationRowBytes >= width * 4,
              destination.count >= (height - 1) * destinationRowBytes + width * 4,
              let to = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
        return bgra.withUnsafeBufferPointer { source in
            guard let from = source.baseAddress else { return false }
            return DLBPackBGRA(from, width * 4, width, height, to, destinationRowBytes, straightAlpha ? .straight : .premultiplied)
        }
    }
}
