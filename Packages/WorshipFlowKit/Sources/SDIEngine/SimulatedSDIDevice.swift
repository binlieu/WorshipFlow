// HW-001: a simulated SDI card with a manual clock. Reaches "Simulated" verification at most; it proves
// scheduling and fill/key logic, never behaviour on a real card or a real signal.
import Foundation

/// Locking: all mutable state lives in `SimulatedBackend`, guarded by one `NSLock`. Callbacks are always
/// invoked after the lock is released, so handlers may call back into ports or the device. The device and
/// its ports hold only immutable references, so they are genuinely `Sendable`.
public final class SimulatedSDIDevice: SDIDevice {
    public typealias InputPort = SimulatedSDIInputPort
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

    public func openInput(connector: Int) throws -> SimulatedSDIInputPort {
        let id = try backend.openInput(connector: connector)
        return SimulatedSDIInputPort(connector: connector, id: id, backend: backend)
    }

    /// A BNC cable from what `output` carries to the input on `toInput`. The input receives what the output
    /// displays one frame period later. A keyed pair carries the fill on its first connector and the key on the next.
    /// Cables belong to the room, not to a port: they stay across unplug and replug. An input with no cable has no signal.
    public func connect(output: Int, toInput input: Int) { backend.connect(output: output, input: input) }

    /// Removes the cable from an input.
    public func disconnect(input: Int) { backend.disconnect(input: input) }

    /// Faults every cable of this card applies from now on (drop frames, swap fill and key, shift, wrong mode).
    public func setFaults(_ faults: SimulatedFaults) { backend.setFaults(faults) }

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

    /// Connection changes from now on: `false` when the card is unplugged, `true` when it is plugged back in. Every call
    /// makes its own stream, subscribed at once. This is what a provider turns into arrival and removal events.
    public func connectionEvents() -> AsyncStream<Bool> { backend.connectionEvents() }
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

public final class SimulatedSDIInputPort: SDIInputPort {
    public let connector: Int
    private let id: UUID
    private let backend: SimulatedBackend

    fileprivate init(connector: Int, id: UUID, backend: SimulatedBackend) {
        self.connector = connector
        self.id = id
        self.backend = backend
    }

    public func supports(mode: SDIVideoMode) -> Bool { SDIVideoMode.allKnown.contains(mode) && backend.inputIsOpen(connector: connector, id: id) }
    public func enable(mode: SDIVideoMode?) throws { try backend.enableInput(connector: connector, id: id, mode: mode) }
    public func disable() { backend.disableInput(connector: connector, id: id) }
    public func close() { backend.closeInput(connector: connector, id: id) }
    public var signal: SDIInputSignal { backend.inputSignal(connector: connector, id: id) }

    public var onFrameReceived: (@Sendable (SDICapturedFrame) -> Void)? {
        get { backend.inputHandlers(connector: connector, id: id)?.frame }
        set { backend.setInputHandlers(connector: connector, id: id) { $0.onFrame = newValue } }
    }

    public var onSignalChange: (@Sendable (SDIInputSignal) -> Void)? {
        get { backend.inputHandlers(connector: connector, id: id)?.signal }
        set { backend.setInputHandlers(connector: connector, id: id) { $0.onSignal = newValue } }
    }

    public var onFailure: (@Sendable (SDIError) -> Void)? {
        get { backend.inputHandlers(connector: connector, id: id)?.failure }
        set { backend.setInputHandlers(connector: connector, id: id) { $0.onFailure = newValue } }
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

    struct InputState {
        var id: UUID
        var enabled = false
        var mode: SDIVideoMode?
        var signal: SDIInputSignal = .noSignal
        var ticks: Int64 = 0          // free-running device clock, in frame periods since enable
        var delivered: Int64 = 0
        var carried = 0               // frames the cable carried, for dropEveryNthFrame
        var onFrame: (@Sendable (SDICapturedFrame) -> Void)?
        var onSignal: (@Sendable (SDIInputSignal) -> Void)?
        var onFailure: (@Sendable (SDIError) -> Void)?
    }

    private struct InputBatch {
        var state: InputState
        var frame: SDICapturedFrame?
        var changedSignal: SDIInputSignal?
    }

    private let info: SDIDeviceInfo
    private let lock = NSLock()
    private var connected = true
    private var ports: [Int: PortState] = [:]
    private var keyClaims: [Int: Int] = [:]      // key connector -> the fill connector that owns it
    private var shown: [Int: SDIFrame] = [:]
    private var inputs: [Int: InputState] = [:]
    private var cables: [Int: Int] = [:]                      // input connector -> the connector whose signal it carries
    private var inFlight: [Int: (frame: SDIFrame, mode: SDIVideoMode)] = [:]   // shown this tick, on the wire until the next
    private var faults = SimulatedFaults.none
    /// The last fill/key split, reused while the same frame buffer comes round again (a still graphic is shown every frame).
    /// It holds the source array, so the buffer cannot be freed or changed in place while its address is compared.
    private var splitCache: (source: [UInt8], mode: AlphaMode, split: FillKeyFrames)?

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
            && inputs[connector] == nil
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
            guard ports[connector] == nil, keyClaims[connector] == nil, inputs[connector] == nil else { throw SDIError.connectorUnavailable(connector) }
            let id = UUID()
            ports[connector] = PortState(id: id)
            return id
        }
    }

    private var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]

    func connectionEvents() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let key = UUID()
        lock.withLock { subscribers[key] = continuation }
        continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.subscribers[key] = nil } }
        return stream
    }

    private func announce(connected now: Bool) {
        let all = lock.withLock { Array(subscribers.values) }
        for c in all { c.yield(now) }
    }

    func unplug() {
        let handlers: [@Sendable (SDIError) -> Void] = lock.withLock {
            guard connected else { return [] }
            connected = false
            let hs = ports.keys.sorted().compactMap { ports[$0]?.onFailure } + inputs.keys.sorted().compactMap { inputs[$0]?.onFailure }
            ports.removeAll()
            inputs.removeAll()
            keyClaims.removeAll()
            inFlight.removeAll()
            return hs
        }
        for h in handlers { h(.deviceDisconnected) }
        announce(connected: false)
    }

    func replug() {
        let was = lock.withLock { () -> Bool in let was = connected; connected = true; return was }
        if !was { announce(connected: true) }
    }

    func tick() {
        let (batches, inputBatches): ([(handler: (@Sendable (SDIFrameCompletion) -> Void)?, completions: [SDIFrameCompletion])], [InputBatch]) = lock.withLock {
            guard connected else { return ([], []) }
            let onTheWire = inFlight          // what the outputs showed last tick reaches the inputs now: one frame later
            inFlight = [:]
            var out: [(handler: (@Sendable (SDIFrameCompletion) -> Void)?, completions: [SDIFrameCompletion])] = []
            for connector in ports.keys.sorted() {
                guard var state = ports[connector], state.playing else { continue }
                let now = state.playhead
                var completions: [SDIFrameCompletion] = []
                let stale = state.scheduled.keys.filter { $0 < now }.sorted()
                if let exact = state.scheduled.removeValue(forKey: now) {
                    for s in stale { state.scheduled[s] = nil; completions.append(.init(frameIndex: s, result: .dropped)) }
                    show(exact, on: connector, keying: state.keying, mode: state.mode)
                    completions.append(.init(frameIndex: now, result: .completed))
                } else if let newest = stale.last, let frame = state.scheduled.removeValue(forKey: newest) {
                    for s in stale.dropLast() { state.scheduled[s] = nil; completions.append(.init(frameIndex: s, result: .dropped)) }
                    show(frame, on: connector, keying: state.keying, mode: state.mode)
                    completions.append(.init(frameIndex: newest, result: .displayedLate))
                } else {
                    completions.append(.init(frameIndex: now, result: .dropped))
                }
                state.playhead = now + 1
                ports[connector] = state
                out.append((state.onCompleted, completions))
            }
            return (out, deliverToInputs(onTheWire))
        }
        for batch in batches {
            guard let handler = batch.handler else { continue }
            for c in batch.completions { handler(c) }
        }
        for batch in inputBatches {
            if let change = batch.changedSignal { batch.state.onSignal?(change) }
            if let frame = batch.frame { batch.state.onFrame?(frame) }
        }
    }

    /// Call with the lock held. Moves what was on the wire into each enabled input, applying the cable faults.
    private func deliverToInputs(_ onTheWire: [Int: (frame: SDIFrame, mode: SDIVideoMode)]) -> [InputBatch] {
        var result: [InputBatch] = []
        for connector in inputs.keys.sorted() {
            guard var st = inputs[connector], st.enabled else { continue }
            var signal: SDIInputSignal = .noSignal
            var captured: SDICapturedFrame?
            if let source = cables[connector], let wire = onTheWire[source] {
                let reported = faults.wrongMode ?? wire.mode
                if st.mode == nil || st.mode == reported {
                    signal = .locked(reported)
                    st.carried += 1
                    let lost = faults.dropEveryNthFrame.map { $0 >= 1 && st.carried % $0 == 0 } ?? false
                    if !lost {
                        captured = SDICapturedFrame(frame: shifted(wire.frame, by: faults.shiftPixels), frameNumber: st.delivered,
                                                    hardwareTimestamp: st.ticks * reported.frameDurationValue, mode: reported)
                        st.delivered += 1
                    }
                }
            }
            st.ticks += 1
            let changed: SDIInputSignal? = signal != st.signal ? signal : nil
            st.signal = signal
            inputs[connector] = st
            result.append(InputBatch(state: st, frame: captured, changedSignal: changed))
        }
        return result
    }

    private func shifted(_ frame: SDIFrame, by pixels: Int) -> SDIFrame {
        guard pixels > 0, frame.width > 0, frame.height > 0, frame.bgra.count >= frame.width * frame.height * 4 else { return frame }
        let rowBytes = frame.width * 4
        let move = min(pixels, frame.width) * 4
        let height = frame.height
        let source = frame.bgra
        let bytes = [UInt8](unsafeUninitializedCapacity: rowBytes * height) { out, count in
            source.withUnsafeBufferPointer { src in
                guard let s = src.baseAddress, let o = out.baseAddress else { count = 0; return }
                for y in 0..<height {
                    let row = y * rowBytes
                    for p in stride(from: 0, to: move, by: 4) { o[row + p] = 0; o[row + p + 1] = 0; o[row + p + 2] = 0; o[row + p + 3] = 255 }   // vacated columns: opaque black
                    if rowBytes > move { memcpy(o + row + move, s + row, rowBytes - move) }
                }
            }
            count = rowBytes * height
        }
        return SDIFrame(width: frame.width, height: frame.height, bgra: bytes)
    }

    /// Call with the lock held.
    private func show(_ frame: SDIFrame, on connector: Int, keying: SDIKeying, mode: SDIVideoMode?) {
        let carriedMode = mode ?? .hd1080p5994
        switch keying {
        case .none:
            shown[connector] = frame
            inFlight[connector] = (frame, carriedMode)
        case .external(let alphaMode):
            let split = cachedSplit(of: frame, alphaMode: alphaMode)
            var fill = SDIFrame(width: frame.width, height: frame.height, bgra: split.fill)
            var key = SDIFrame(width: frame.width, height: frame.height, bgra: split.key)
            if faults.swapFillAndKey { swap(&fill, &key) }
            // The card's own route: which connector of the pair carries the fill (KI-053).
            let route = info.keyRoute(firstConnector: connector)
            let fillConnector = route?.fillConnector ?? connector
            let keyConnector = route?.keyConnector ?? connector + 1
            shown[fillConnector] = fill
            shown[keyConnector] = key
            inFlight[fillConnector] = (fill, carriedMode)
            inFlight[keyConnector] = (key, carriedMode)
        }
    }

    /// Call with the lock held.
    private func cachedSplit(of frame: SDIFrame, alphaMode: AlphaMode) -> FillKeyFrames {
        if let c = splitCache, c.mode == alphaMode, c.source.count == frame.bgra.count, !c.source.isEmpty,
           c.source.withUnsafeBufferPointer({ a in frame.bgra.withUnsafeBufferPointer { a.baseAddress == $0.baseAddress } }) {
            return c.split
        }
        let split = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: alphaMode)
        splitCache = (frame.bgra, alphaMode, split)
        return split
    }

    // MARK: inputs and cables

    func openInput(connector: Int) throws -> UUID {
        try lock.withLock {
            guard connected else { throw SDIError.deviceDisconnected }
            guard connector >= 1, connector <= info.connectorCount else { throw SDIError.connectorUnavailable(connector) }
            guard ports[connector] == nil, keyClaims[connector] == nil, inputs[connector] == nil else { throw SDIError.connectorUnavailable(connector) }
            let id = UUID()
            inputs[connector] = InputState(id: id)
            return id
        }
    }

    func connect(output: Int, input: Int) { lock.withLock { cables[input] = output } }
    func disconnect(input: Int) { lock.withLock { cables[input] = nil } }
    func setFaults(_ f: SimulatedFaults) { lock.withLock { faults = f } }

    func inputIsOpen(connector: Int, id: UUID) -> Bool { lock.withLock { connected && inputs[connector]?.id == id } }

    func enableInput(connector: Int, id: UUID, mode: SDIVideoMode?) throws {
        try lock.withLock {
            guard connected else { throw SDIError.deviceDisconnected }
            guard inputs[connector]?.id == id else { throw SDIError.portClosed }
            if let mode, !SDIVideoMode.allKnown.contains(mode) { throw SDIError.unsupportedMode(mode.name) }
            inputs[connector]?.enabled = true
            inputs[connector]?.mode = mode
            inputs[connector]?.signal = .noSignal
            inputs[connector]?.ticks = 0
            inputs[connector]?.delivered = 0
            inputs[connector]?.carried = 0
        }
    }

    func disableInput(connector: Int, id: UUID) {
        lock.withLock {
            guard inputs[connector]?.id == id else { return }
            inputs[connector]?.enabled = false
            inputs[connector]?.signal = .noSignal
        }
    }

    func closeInput(connector: Int, id: UUID) {
        lock.withLock { if inputs[connector]?.id == id { inputs[connector] = nil } }
    }

    func inputSignal(connector: Int, id: UUID) -> SDIInputSignal {
        lock.withLock { connected && inputs[connector]?.id == id ? (inputs[connector]?.signal ?? .noSignal) : .noSignal }
    }

    func inputHandlers(connector: Int, id: UUID) -> (frame: (@Sendable (SDICapturedFrame) -> Void)?, signal: (@Sendable (SDIInputSignal) -> Void)?, failure: (@Sendable (SDIError) -> Void)?)? {
        lock.withLock {
            guard let st = inputs[connector], st.id == id else { return nil }
            return (st.onFrame, st.onSignal, st.onFailure)
        }
    }

    func setInputHandlers(connector: Int, id: UUID, _ change: (inout InputState) -> Void) {
        lock.withLock {
            guard var st = inputs[connector], st.id == id else { return }
            change(&st)
            inputs[connector] = st
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

    /// Call with the lock held. The signal a port was putting on the wire ends with the port: a frame still in flight
    /// does not reach an input that is enabled later.
    private func dropSignal(of connector: Int) {
        inFlight[connector] = nil
        if case .external = ports[connector]?.keying { inFlight[connector + 1] = nil }
    }

    private func releaseKeyClaim(of connector: Int) {
        for (key, owner) in keyClaims where owner == connector { keyClaims[key] = nil }
    }

    func disable(connector: Int, id: UUID) {
        lock.withLock {
            guard connected, ports[connector]?.id == id else { return }
            releaseKeyClaim(of: connector)
            dropSignal(of: connector)
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
            dropSignal(of: connector)
            return (state.onCompleted, indexes)
        }
        if let handler = flushed.0 {
            for i in flushed.1 { handler(.init(frameIndex: i, result: .flushed)) }
        }
    }

    func close(connector: Int, id: UUID) {
        lock.withLock {
            guard ports[connector]?.id == id else { return }
            dropSignal(of: connector)
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
