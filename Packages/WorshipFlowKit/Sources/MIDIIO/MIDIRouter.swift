// CUE-003 (AUTO-03, AUTO-04): ties a MIDIPorts to a MIDIBindingSet. Received messages become commands through the
// engine's own rules (MIDICommandFilter: a held pad fires once), delivered on the main actor in arrival order. The
// router also learns patterns, keeps a chosen device across unplug and replug, and sends MIDI out.
import Foundation
import CueEngine

public enum MIDISourceState: Sendable, Equatable {
    /// No input device chosen.
    case none
    case connected(name: String)
    /// A device is chosen but not present (unplugged, powered off, or the Mac just started). It is reconnected by its
    /// stable id when it returns.
    case waiting(lastKnownName: String?)
    /// The device is present but could not be opened. Retried on the next device change or re-selection.
    case failed(message: String)
}

public enum MIDIDestinationState: Sendable, Equatable {
    case none
    case ready(name: String)
    case offline(lastKnownName: String?)
}

public struct MIDILearned: Sendable, Equatable {
    public var message: MIDIMessage
    /// The binding pattern a "learn" creates from the message (exact channel and number, any value).
    public var pattern: MIDIPattern
}

@MainActor
public final class MIDIRouter {
    public var bindings: MIDIBindingSet
    public var filter = MIDICommandFilter()

    public private(set) var selectedSourceID: MIDIEndpointID?
    public private(set) var selectedDestinationID: MIDIEndpointID?
    public private(set) var sourceState: MIDISourceState = .none
    public private(set) var destinationState: MIDIDestinationState = .none
    /// The newest problem, in words the operator can read. Cleared by a successful send or a new selection.
    public private(set) var lastError: String?
    public private(set) var isLearning = false
    /// Every message that reached the router (including ones no binding wanted).
    public private(set) var receivedCount = 0

    private let ports: any MIDIPorts
    private let onCommand: @MainActor (MIDICommand, MIDIMessage) -> Void
    private var messageTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval?
    private var learner = MIDILearner()
    private var learnContinuation: CheckedContinuation<MIDILearned?, Never>?
    private var lastSourceName: String?
    private var lastDestinationName: String?

    /// - Parameter pollInterval: as well as reacting to the system's device notifications, the router re-reads the
    ///   device list this often (seconds) so a missed notification cannot leave a returned device unconnected.
    ///   nil turns the safety net off.
    public init(ports: any MIDIPorts, bindings: MIDIBindingSet = MIDIBindingSet(), pollInterval: TimeInterval? = 3,
                onCommand: @escaping @MainActor (MIDICommand, MIDIMessage) -> Void) {
        self.ports = ports
        self.bindings = bindings
        self.onCommand = onCommand
        self.pollInterval = pollInterval
    }

    // MARK: Lifecycle

    /// Starts listening. Safe to call again after `stop`.
    public func start() {
        guard messageTask == nil else { return }
        let incoming = ports.makeIncomingStream()
        let changes = ports.makeChangeStream()
        messageTask = Task { [weak self] in
            for await received in incoming {
                guard let self else { return }
                self.handle(received)
            }
        }
        changeTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.reconcile()
            }
        }
        if let interval = pollInterval, interval > 0 {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard let self, !Task.isCancelled else { return }
                    self.reconcile()
                }
            }
        }
        reconcile()
    }

    public func stop() {
        pollTask?.cancel(); pollTask = nil
        messageTask?.cancel(); messageTask = nil
        changeTask?.cancel(); changeTask = nil
        cancelLearning()
    }

    // MARK: Devices

    /// Chooses the input device by its stable id (nil for none). `knownName` is shown while the device is absent.
    public func selectSource(_ id: MIDIEndpointID?, knownName: String? = nil) {
        if let old = selectedSourceID, old != id { ports.disconnect(source: old) }
        selectedSourceID = id
        lastSourceName = knownName
        filter.reset()
        lastError = nil
        reconcileSource()
    }

    public func selectDestination(_ id: MIDIEndpointID?, knownName: String? = nil) {
        selectedDestinationID = id
        lastDestinationName = knownName
        lastError = nil
        reconcileDestination()
    }

    /// Re-reads the system's device list and fixes the connection. Called on every device change.
    public func reconcile() {
        reconcileSource()
        reconcileDestination()
    }

    private func reconcileSource() {
        guard let id = selectedSourceID else { sourceState = .none; return }
        let info = ports.sources().first { $0.id == id }
        if let info, info.isOnline {
            lastSourceName = info.name
            if ports.connectedSourceIDs.contains(id) {
                sourceState = .connected(name: info.name)
                return
            }
            do {
                try ports.connect(source: id)
                sourceState = .connected(name: info.name)
            } catch {
                sourceState = .failed(message: "Could not open MIDI input \u{201C}\(info.name)\u{201D}: \(error.localizedDescription)")
            }
        } else {
            if ports.connectedSourceIDs.contains(id) { ports.disconnect(source: id) }
            if let info { lastSourceName = info.name }
            filter.reset()
            sourceState = .waiting(lastKnownName: lastSourceName)
        }
    }

    private func reconcileDestination() {
        guard let id = selectedDestinationID else { destinationState = .none; return }
        if let info = ports.destinations().first(where: { $0.id == id }), info.isOnline {
            lastDestinationName = info.name
            destinationState = .ready(name: info.name)
        } else {
            destinationState = .offline(lastKnownName: lastDestinationName)
        }
    }

    // MARK: Receiving

    private func handle(_ received: ReceivedMIDI) {
        receivedCount += 1
        if isLearning {
            if let pattern = learner.feed(received.message) {
                isLearning = false
                let c = learnContinuation
                learnContinuation = nil
                c?.resume(returning: MIDILearned(message: received.message, pattern: pattern))
            }
            return                                   // while learning nothing runs
        }
        if let command = filter.command(for: received.message, in: bindings, at: received.timestamp) {
            onCommand(command, received.message)
        }
    }

    /// Waits for the next message that can become a binding (a note-on, control change or program change) and returns
    /// it. Nothing runs while learning. Returns nil when cancelled (`cancelLearning`, task cancellation, `stop`, or a
    /// newer `learn`).
    public func learn() async -> MIDILearned? {
        cancelLearning()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<MIDILearned?, Never>) in
                learner = MIDILearner()
                learner.arm()
                isLearning = true
                learnContinuation = c
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelLearning() }
        }
    }

    public func cancelLearning() {
        learner.cancel()
        isLearning = false
        let c = learnContinuation
        learnContinuation = nil
        c?.resume(returning: nil)
    }

    // MARK: Sending

    /// True for the actions this router carries out.
    public func handles(_ action: CueAction) -> Bool {
        if case .midiOut = action { return true }
        return false
    }

    /// Carries out a `CueAction.midiOut`; other actions are ignored. Never blocks: it asks the system to send and
    /// returns. Throws a `CueTargetError` (text for the operator) when the message could not be delivered.
    public func perform(_ action: CueAction) throws {
        guard case .midiOut(let message) = action else { return }
        try send(message)
    }

    public func send(_ message: MIDIMessage) throws {
        guard message.isValid else {
            throw report("The MIDI message is not valid (channels are 1 to 16, values 0 to 127), so it was not sent.")
        }
        reconcileDestination()
        var problem: String?
        var delivered = false

        switch destinationState {
        case .ready:
            if let id = selectedDestinationID {
                do { try ports.send(message, to: id); delivered = true }
                catch { problem = "MIDI output \u{201C}\(lastDestinationName ?? "?")\u{201D} did not take the message: \(error.localizedDescription)" }
            }
        case .offline(let name):
            problem = "MIDI output \u{201C}\(name ?? "chosen device")\u{201D} is offline, so the message was not sent."
        case .none:
            break
        }

        if ports.virtualEndpointsEnabled {
            if (try? ports.publish(message)) != nil { delivered = true }
        }

        if let problem { throw report(problem) }
        if !delivered { throw report("No MIDI output is chosen, so the message was not sent.") }
        lastError = nil
    }

    private func report(_ text: String) -> CueTargetError {
        lastError = text
        return CueTargetError(text)
    }
}
