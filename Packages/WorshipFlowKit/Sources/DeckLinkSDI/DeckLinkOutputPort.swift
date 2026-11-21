// HW-003 / SCRN-11: one SDI output (or fill-and-key pair) as an SDIOutputPort.
//
// Status: Implemented, Not Verified. Threading follows the SDIOutputPort contract: handlers run on SDK threads, one at a
// time, and never while this port holds its lock, so a handler may call back into the port.
import DeckLinkC
import Foundation
import SDIEngine
import Synchronization

public final class DeckLinkOutputPort: SDIOutputPort {
    public let connector: Int
    private let device: DeckLinkDevice
    private let generation: Int

    private struct State {
        var bridge: DLBOutput?
        var mode: SDIVideoMode?
        var keying: SDIKeying = .none
        var plan = DeckLinkMapping.KeyingPlan(useKeyer: false, straightAlpha: false)
        var route: DeckLinkKeyRoute?
        var closed = false
        /// Set when the device failed underneath this port; the port stays dead afterwards.
        var failure: SDIError?
        var lastDetail: String?
        var completion: (@Sendable (SDIFrameCompletion) -> Void)?
        var failureHandler: (@Sendable (SDIError) -> Void)?
    }

    private let state = Mutex(State())

    init(device: DeckLinkDevice, connector: Int, generation: Int) {
        self.device = device
        self.connector = connector
        self.generation = generation
    }

    // MARK: Handlers

    public var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? {
        get { state.withLock { $0.completion } }
        set { state.withLock { $0.completion = newValue } }
    }

    public var onFailure: (@Sendable (SDIError) -> Void)? {
        get { state.withLock { $0.failureHandler } }
        set { state.withLock { $0.failureHandler = newValue } }
    }

    // MARK: Data

    /// For a keyed port: the physical connectors that carry fill and key, as the layout understands them. Nil when not keyed.
    public var keyRoute: DeckLinkKeyRoute? { state.withLock { $0.route } }

    /// The bridge's own words for the last failure, with the SDK result code, for the log.
    public var lastErrorDetail: String? { state.withLock { $0.lastDetail } }

    public func statusSnapshot() -> DeckLinkSnapshotValue {
        let (bridge, mode, route, keying) = state.withLock { ($0.bridge, $0.mode, $0.route, $0.keying) }
        var fields: [String: DeckLinkSnapshotValue] = [
            "connector": .int(Int64(connector)),
            "enabled": .bool(bridge != nil),
            "mode": .string(mode?.name ?? "none"),
            "keyed": .bool(keying != .none),
        ]
        if let route {
            fields["fillConnector"] = .int(Int64(route.fillConnector))
            fields["keyConnector"] = .int(Int64(route.keyConnector))
            fields["routeFromDocumentation"] = .bool(route.fromDocumentation)
        }
        if let bridge { fields["bridge"] = DeckLinkSnapshotValue(foundation: bridge.statusSnapshot()) }
        if let detail = lastErrorDetail { fields["lastError"] = .string(detail) }
        return .object(fields)
    }

    // MARK: SDIOutputPort

    public func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool {
        guard let code = DeckLinkModeMapping.displayMode(for: mode) else { return false }
        let plan = DeckLinkMapping.keyingPlan(keying)
        guard (try? checkUsable()) != nil, let target = try? device.resolveOutput(connector: connector, keyed: plan.useKeyer) else { return false }
        guard let probe = try? target.device.openOutput() else { return false }
        defer { probe.close() }
        return probe.supportsDisplayMode(code, keying: plan.useKeyer, actualMode: nil)
    }

    public func enable(mode: SDIVideoMode, keying: SDIKeying) throws {
        try checkUsable()
        guard let code = DeckLinkModeMapping.displayMode(for: mode) else { throw SDIError.unsupportedMode(mode.name) }
        let plan = DeckLinkMapping.keyingPlan(keying)
        let context = DeckLinkMapping.Context.enable(connector: connector, modeName: mode.name, keyed: plan.useKeyer)

        disable()  // enabling again replaces the previous setup
        let target = try device.resolveOutput(connector: connector, keyed: plan.useKeyer)
        if plan.useKeyer { try device.claimKey(first: connector, port: ObjectIdentifier(self)) }

        let bridge: DLBOutput
        do {
            bridge = try target.device.openOutput()
        } catch {
            if plan.useKeyer { device.releaseKey(first: connector) }
            record(error)
            throw DeckLinkMapping.sdiError(error, context: .open(connector: connector))
        }
        bridge.completionHandler = { [weak self] index, result in self?.deliver(index: index, result: result) }
        bridge.failureHandler = { [weak self] error in self?.fail(error) }
        do {
            try bridge.enableDisplayMode(code, width: Int32(mode.width), height: Int32(mode.height),
                                         frameDuration: mode.frameDurationValue, timeScale: mode.timeScale,
                                         keying: plan.useKeyer, keyerLevel: 255)
        } catch {
            bridge.close()
            if plan.useKeyer { device.releaseKey(first: connector) }
            record(error)
            throw DeckLinkMapping.sdiError(error, context: context)
        }
        state.withLock {
            $0.bridge = bridge
            $0.mode = mode
            $0.keying = keying
            $0.plan = plan
            $0.route = target.route
        }
    }

    public func disable() {
        let (bridge, keyed) = state.withLock { s -> (DLBOutput?, Bool) in
            let result = (s.bridge, s.plan.useKeyer)
            s.bridge = nil
            s.mode = nil
            s.keying = .none
            s.plan = DeckLinkMapping.KeyingPlan(useKeyer: false, straightAlpha: false)
            s.route = nil
            return result
        }
        guard let bridge else { return }
        bridge.disable()   // stops playback, turns the keyer off, disables the output
        bridge.close()
        if keyed { device.releaseKey(first: connector) }
    }

    public func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws {
        let (bridge, mode, plan) = try state.withLock { s -> (DLBOutput, SDIVideoMode, DeckLinkMapping.KeyingPlan) in
            if s.closed { throw SDIError.portClosed }
            if let failure = s.failure { throw failure }
            guard let bridge = s.bridge, let mode = s.mode else { throw SDIError.notEnabled }
            return (bridge, mode, s.plan)
        }
        guard frame.width == mode.width, frame.height == mode.height, frame.bgra.count == mode.width * mode.height * 4 else {
            throw SDIError.unsupportedMode("\(frame.width)x\(frame.height) frame sent to a \(mode.name) output")
        }
        do {
            try frame.bgra.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { throw SDIError.notEnabled }
                try bridge.scheduleBGRA(base, byteCount: buffer.count, frameIndex: frameIndex,
                                        alphaMode: DeckLinkMapping.bridgeAlphaMode(straight: plan.straightAlpha))
            }
        } catch {
            record(error)
            throw DeckLinkMapping.sdiError(error, context: .schedule)
        }
    }

    public func startPlayback(atFrame frameIndex: Int64) {
        guard let bridge = state.withLock({ $0.bridge }) else { return }
        do {
            try bridge.startPlayback(atFrame: frameIndex)
        } catch {
            // The protocol cannot throw here; the failure reaches the session through onFailure.
            record(error)
            fail(error)
        }
    }

    public func stopPlayback() {
        state.withLock { $0.bridge }?.stopPlayback()
    }

    /// Changes the keyer level while a keyed output runs (255 is full, 0 is off). Not part of SDIOutputPort.
    public func setKeyerLevel(_ level: UInt8) throws {
        guard let bridge = state.withLock({ $0.plan.useKeyer ? $0.bridge : nil }) else { throw SDIError.notEnabled }
        do {
            try bridge.setKeyerLevel(level)
        } catch {
            record(error)
            throw DeckLinkMapping.sdiError(error, context: .runtime)
        }
    }

    public func close() {
        disable()
        state.withLock { $0.closed = true }
        device.release(connector: connector, port: ObjectIdentifier(self))
    }

    /// What the card's SDK asks to be scheduled before playback starts, from the device information the bridge read.
    /// 0 when the connector cannot be resolved or the device does not say.
    public var minimumPrerollFrames: Int {
        guard let target = try? device.resolveOutput(connector: connector, keyed: false) else { return 0 }
        let minimum = target.device.info.minimumPrerollFrames
        return minimum > 0 ? DeckLinkMapping.prerollFrames(deviceMinimum: minimum) : 0
    }

    public var bufferedFrameCount: Int {
        Int(state.withLock { $0.bridge }?.bufferedFrameCount ?? 0)
    }

    // MARK: Callbacks from the bridge (SDK threads)

    private func deliver(index: Int64, result: DLBCompletionResult) {
        guard index >= 0 else { return }
        let handler = state.withLock { $0.completion }
        handler?(SDIFrameCompletion(frameIndex: index, result: DeckLinkMapping.completionResult(result)))
    }

    private func fail(_ error: Error) {
        let mapped = DeckLinkMapping.sdiError(error, context: .runtime)
        let handler: (@Sendable (SDIError) -> Void)? = state.withLock { s in
            s.failure = mapped
            s.lastDetail = DeckLinkMapping.detail(error)
            return s.failureHandler
        }
        handler?(mapped)
    }

    private func record(_ error: Error) {
        let detail = DeckLinkMapping.detail(error)
        state.withLock { $0.lastDetail = detail }
    }

    /// The port is unusable if it was closed or its card went away since it was opened.
    private func checkUsable() throws {
        let (closed, failure) = state.withLock { ($0.closed, $0.failure) }
        if closed { throw SDIError.portClosed }
        guard device.isConnected else { throw SDIError.deviceDisconnected }
        if !device.isCurrent(generation: generation) { throw SDIError.portClosed }
        if let failure { throw failure }
    }
}
