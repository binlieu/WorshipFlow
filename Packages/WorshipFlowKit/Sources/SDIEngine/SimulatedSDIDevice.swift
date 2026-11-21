// HW-001: a simulated SDI card with a manual clock. Reaches "Simulated" verification at most; it proves
// scheduling and fill/key logic, never behaviour on a real card or a real signal.
import Foundation

/// Locking: all mutable state lives in `SimulatedBackend`, guarded by one `NSLock`. Callbacks are always
/// invoked after the lock is released, so handlers may call back into ports or the device. The device and
/// its ports hold only immutable references, so they are genuinely `Sendable`.
public final class SimulatedSDIDevice: SDIDevice {
    public let info: SDIDeviceInfo
    private let backend: SimulatedBackend

    public init(info: SDIDeviceInfo = .simulatedDuo2) {
        self.info = info
        self.backend = SimulatedBackend(info: info)
    }

    public var isConnected: Bool { backend.isConnected }

    public func openOutput(connector: Int) throws -> SimulatedSDIOutputPort {
        let id = try backend.open(connector: connector)
        return SimulatedSDIOutputPort(connector: connector, id: id, backend: backend)
    }

    /// Plays `frames` frame periods on every playing port, delivering completions as the device would.
    public func advance(frames: Int) {
        guard frames > 0 else { return }
        for _ in 0..<frames { backend.tick() }
    }

    /// The last frame shown on a connector. On a keyed pair the second connector shows the key.
    public func lastDisplayed(onConnector connector: Int) -> SDIFrame? { backend.displayed(connector) }

    /// Removes the card: every open port fails and is invalidated.
    public func simulateUnplug() { backend.unplug() }

    /// Brings the card back. Ports from before the unplug stay dead; open new ones.
    public func simulateReplug() { backend.replug() }
}

public final class SimulatedSDIOutputPort: SDIOutputPort {
    public let connector: Int
    private let id: UUID
    private let backend: SimulatedBackend

    fileprivate init(connector: Int, id: UUID, backend: SimulatedBackend) {
        self.connector = connector
        self.id = id
        self.backend = backend
    }

    public func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { backend.supports(connector: connector, id: id, mode: mode, keying: keying) }
    public func enable(mode: SDIVideoMode, keying: SDIKeying) throws { try backend.enable(connector: connector, id: id, mode: mode, keying: keying) }
    public func disable() { backend.disable(connector: connector, id: id) }
    public func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws { try backend.schedule(connector: connector, id: id, frame: frame, index: frameIndex) }
    public func startPlayback(atFrame frameIndex: Int64) { backend.startPlayback(connector: connector, id: id, at: frameIndex) }
    public func stopPlayback() { backend.stopPlayback(connector: connector, id: id) }
    public func close() { backend.close(connector: connector, id: id) }
    public var bufferedFrameCount: Int { backend.buffered(connector: connector, id: id) }

    public var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? {
        get { backend.completionHandler(connector: connector, id: id) }
        set { backend.setCompletionHandler(newValue, connector: connector, id: id) }
    }

    public var onFailure: (@Sendable (SDIError) -> Void)? {
        get { backend.failureHandler(connector: connector, id: id) }
        set { backend.setFailureHandler(newValue, connector: connector, id: id) }
    }
}

/// `@unchecked Sendable`: every stored property is only touched while holding `lock`.
final class SimulatedBackend: @unchecked Sendable {
    private struct PortState {
        var id: UUID
        var mode: SDIVideoMode?
        var keying: SDIKeying = .none
        var scheduled: [Int64: SDIFrame] = [:]
        var playing = false
        var playhead: Int64 = 0
        var onCompleted: (@Sendable (SDIFrameCompletion) -> Void)?
        var onFailure: (@Sendable (SDIError) -> Void)?
    }

    private let info: SDIDeviceInfo
    private let lock = NSLock()
    private var connected = true
    private var ports: [Int: PortState] = [:]
    private var keyClaims: [Int: Int] = [:]      // key connector -> the fill connector that owns it
    private var shown: [Int: SDIFrame] = [:]

    init(info: SDIDeviceInfo) { self.info = info }

    var isConnected: Bool { lock.withLock { connected } }
    func displayed(_ connector: Int) -> SDIFrame? { lock.withLock { shown[connector] } }

    // MARK: validation (call with the lock held)

    private func check(_ connector: Int, _ id: UUID) throws {
        guard connected else { throw SDIError.deviceDisconnected }
        guard ports[connector]?.id == id else { throw SDIError.portClosed }
    }

    private func isFree(_ connector: Int, except owner: Int) -> Bool {
        (ports[connector] == nil || connector == owner) && (keyClaims[connector] == nil || keyClaims[connector] == owner)
    }

    private func keyingProblem(connector: Int, keying: SDIKeying) -> SDIError? {
        guard case .external = keying else { return nil }
        let partner = connector + 1
        guard info.supportsExternalKeying, connector % 2 == 1, partner <= info.connectorCount else {
            return .keyingUnavailable(connector: connector)
        }
        return isFree(partner, except: connector) ? nil : .connectorUnavailable(partner)
    }

    // MARK: device level

    func open(connector: Int) throws -> UUID {
        try lock.withLock {
            guard connected else { throw SDIError.deviceDisconnected }
            guard connector >= 1, connector <= info.connectorCount else { throw SDIError.connectorUnavailable(connector) }
            guard ports[connector] == nil, keyClaims[connector] == nil else { throw SDIError.connectorUnavailable(connector) }
            let id = UUID()
            ports[connector] = PortState(id: id)
            return id
        }
    }

    func unplug() {
        let handlers: [@Sendable (SDIError) -> Void] = lock.withLock {
            guard connected else { return [] }
            connected = false
            let hs = ports.keys.sorted().compactMap { ports[$0]?.onFailure }
            ports.removeAll()
            keyClaims.removeAll()
            return hs
        }
        for h in handlers { h(.deviceDisconnected) }
    }

    func replug() { lock.withLock { connected = true } }

    func tick() {
        let batches: [(handler: (@Sendable (SDIFrameCompletion) -> Void)?, completions: [SDIFrameCompletion])] = lock.withLock {
            guard connected else { return [] }
            var out: [(handler: (@Sendable (SDIFrameCompletion) -> Void)?, completions: [SDIFrameCompletion])] = []
            for connector in ports.keys.sorted() {
                guard var state = ports[connector], state.playing else { continue }
                let now = state.playhead
                var completions: [SDIFrameCompletion] = []
                let stale = state.scheduled.keys.filter { $0 < now }.sorted()
                if let exact = state.scheduled.removeValue(forKey: now) {
                    for s in stale { state.scheduled[s] = nil; completions.append(.init(frameIndex: s, result: .dropped)) }
                    show(exact, on: connector, keying: state.keying)
                    completions.append(.init(frameIndex: now, result: .completed))
                } else if let newest = stale.last, let frame = state.scheduled.removeValue(forKey: newest) {
                    for s in stale.dropLast() { state.scheduled[s] = nil; completions.append(.init(frameIndex: s, result: .dropped)) }
                    show(frame, on: connector, keying: state.keying)
                    completions.append(.init(frameIndex: newest, result: .displayedLate))
                } else {
                    completions.append(.init(frameIndex: now, result: .dropped))
                }
                state.playhead = now + 1
                ports[connector] = state
                out.append((state.onCompleted, completions))
            }
            return out
        }
        for batch in batches {
            guard let handler = batch.handler else { continue }
            for c in batch.completions { handler(c) }
        }
    }

    private func show(_ frame: SDIFrame, on connector: Int, keying: SDIKeying) {
        switch keying {
        case .none:
            shown[connector] = frame
        case .external(let alphaMode):
            let split = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: alphaMode)
            shown[connector] = SDIFrame(width: frame.width, height: frame.height, bgra: split.fill)
            shown[connector + 1] = SDIFrame(width: frame.width, height: frame.height, bgra: split.key)
        }
    }

    // MARK: port level

    func supports(connector: Int, id: UUID, mode: SDIVideoMode, keying: SDIKeying) -> Bool {
        lock.withLock {
            guard connected, ports[connector]?.id == id else { return false }
            return SDIVideoMode.allKnown.contains(mode) && keyingProblem(connector: connector, keying: keying) == nil
        }
    }

    func enable(connector: Int, id: UUID, mode: SDIVideoMode, keying: SDIKeying) throws {
        try lock.withLock {
            try check(connector, id)
            guard SDIVideoMode.allKnown.contains(mode) else { throw SDIError.unsupportedMode(mode.name) }
            if let problem = keyingProblem(connector: connector, keying: keying) { throw problem }
            releaseKeyClaim(of: connector)
            if case .external = keying { keyClaims[connector + 1] = connector }
            ports[connector]?.mode = mode
            ports[connector]?.keying = keying
        }
    }

    private func releaseKeyClaim(of connector: Int) {
        for (key, owner) in keyClaims where owner == connector { keyClaims[key] = nil }
    }

    func disable(connector: Int, id: UUID) {
        lock.withLock {
            guard connected, ports[connector]?.id == id else { return }
            releaseKeyClaim(of: connector)
            ports[connector]?.mode = nil
            ports[connector]?.keying = .none
            ports[connector]?.playing = false
            ports[connector]?.scheduled.removeAll()
        }
    }

    func schedule(connector: Int, id: UUID, frame: SDIFrame, index: Int64) throws {
        try lock.withLock {
            try check(connector, id)
            guard ports[connector]?.mode != nil else { throw SDIError.notEnabled }
            ports[connector]?.scheduled[index] = frame
        }
    }

    func startPlayback(connector: Int, id: UUID, at index: Int64) {
        lock.withLock {
            guard connected, ports[connector]?.id == id, ports[connector]?.mode != nil else { return }
            ports[connector]?.playing = true
            ports[connector]?.playhead = index
        }
    }

    func stopPlayback(connector: Int, id: UUID) {
        let flushed: ((@Sendable (SDIFrameCompletion) -> Void)?, [Int64]) = lock.withLock {
            guard connected, var state = ports[connector], state.id == id else { return (nil, []) }
            let indexes = state.scheduled.keys.sorted()
            state.scheduled.removeAll()
            state.playing = false
            ports[connector] = state
            return (state.onCompleted, indexes)
        }
        if let handler = flushed.0 {
            for i in flushed.1 { handler(.init(frameIndex: i, result: .flushed)) }
        }
    }

    func close(connector: Int, id: UUID) {
        lock.withLock {
            guard ports[connector]?.id == id else { return }
            releaseKeyClaim(of: connector)
            ports[connector] = nil
        }
    }

    func buffered(connector: Int, id: UUID) -> Int {
        lock.withLock {
            guard connected, let state = ports[connector], state.id == id else { return 0 }
            return state.scheduled.count
        }
    }

    func completionHandler(connector: Int, id: UUID) -> (@Sendable (SDIFrameCompletion) -> Void)? {
        lock.withLock { ports[connector]?.id == id ? ports[connector]?.onCompleted : nil }
    }

    func setCompletionHandler(_ handler: (@Sendable (SDIFrameCompletion) -> Void)?, connector: Int, id: UUID) {
        lock.withLock { if ports[connector]?.id == id { ports[connector]?.onCompleted = handler } }
    }

    func failureHandler(connector: Int, id: UUID) -> (@Sendable (SDIError) -> Void)? {
        lock.withLock { ports[connector]?.id == id ? ports[connector]?.onFailure : nil }
    }

    func setFailureHandler(_ handler: (@Sendable (SDIError) -> Void)?, connector: Int, id: UUID) {
        lock.withLock { if ports[connector]?.id == id { ports[connector]?.onFailure = handler } }
    }
}
