// CUE-002b (item 4): MIDI in and out. The ports and the router exist only while MIDI is on. Incoming commands are submitted to
// the one command path like any other source.
import Foundation
import CueEngine
import CueStore
import MIDIIO

public struct MIDIStatus: Equatable, Sendable {
    public var isEnabled = false
    public var source: MIDISourceState = .none
    public var destination: MIDIDestinationState = .none
    public var virtualPortsOn = false
    public var isLearning = false
    /// The newest problem in words the operator can read.
    public var error: String?
    public var inputs: [MIDIEndpointInfo] = []
    public var outputs: [MIDIEndpointInfo] = []
    public var receivedCount = 0
    public var virtualInputName = "WorshipFlow In"
    public var virtualOutputName = "WorshipFlow Out"
    public init() {}
}

extension CueModel {
    public var bindingConflicts: [MIDIConflict] { bindings.conflicts() }

    /// Ids of bindings that clash with another.
    public var conflictingBindingIDs: Set<UUID> { Set(bindingConflicts.flatMap { [$0.first, $0.second] }) }

    // MARK: On and off

    public func setMIDIEnabled(_ on: Bool) async {
        midi.isEnabled = on
        await save(midi, key: Self.midiKey)
        if on { startMIDI() } else { stopMIDI() }
    }

    func startMIDI() {
        guard midiRouter == nil else { return }
        guard let factory = midiPortsFactory else {
            midiProblem("MIDI is not available in this build.")
            return
        }
        do {
            let ports = try factory()
            let router = MIDIRouter(ports: ports, bindings: bindings) { [weak self] command, _ in self?.midiCommand(command) }
            midiPorts = ports
            midiRouter = router
            router.start()
            if let id = midi.inputID { router.selectSource(MIDIEndpointID(id), knownName: midi.inputName) }
            if let id = midi.outputID { router.selectDestination(MIDIEndpointID(id), knownName: midi.outputName) }
            if midi.virtualPorts { try ports.setVirtualEndpointsEnabled(true) }
            refreshMIDI()
        } catch {
            midiPorts?.close()
            midiPorts = nil
            midiRouter = nil
            midiProblem((error as? MIDIPortError)?.message ?? "MIDI could not start: \(error.localizedDescription)")
        }
    }

    func stopMIDI() {
        midiRouter?.stop()
        if let ports = midiPorts {
            try? ports.setVirtualEndpointsEnabled(false)
            ports.close()
        }
        midiRouter = nil
        midiPorts = nil
        midiStatus = MIDIStatus()
    }

    private func midiProblem(_ text: String) {
        var status = midiStatus
        status.error = text
        midiStatus = status
        note(text)
    }

    // MARK: Devices

    public func chooseMIDIInput(_ id: MIDIEndpointID?) async {
        midi.inputID = id?.rawValue
        midi.inputName = id.flatMap { id in midiPorts?.sources().first { $0.id == id }?.name } ?? (id == nil ? nil : midi.inputName)
        await save(midi, key: Self.midiKey)
        midiRouter?.selectSource(id, knownName: midi.inputName)
        refreshMIDI()
    }

    public func chooseMIDIOutput(_ id: MIDIEndpointID?) async {
        midi.outputID = id?.rawValue
        midi.outputName = id.flatMap { id in midiPorts?.destinations().first { $0.id == id }?.name } ?? (id == nil ? nil : midi.outputName)
        await save(midi, key: Self.midiKey)
        midiRouter?.selectDestination(id, knownName: midi.outputName)
        refreshMIDI()
    }

    public func setVirtualPorts(_ on: Bool) async {
        midi.virtualPorts = on
        await save(midi, key: Self.midiKey)
        if let ports = midiPorts {
            do { try ports.setVirtualEndpointsEnabled(on) } catch { midiProblem((error as? MIDIPortError)?.message ?? error.localizedDescription) }
        }
        refreshMIDI()
    }

    /// Reads the router and the device lists. The app calls it every second, and the models call it after a change.
    public func refreshMIDI() {
        guard let router = midiRouter, let ports = midiPorts else { return }
        router.reconcile()
        var status = MIDIStatus()
        status.isEnabled = true
        status.source = router.sourceState
        status.destination = router.destinationState
        status.virtualPortsOn = ports.virtualEndpointsEnabled
        status.isLearning = midiStatus.isLearning
        status.error = router.lastError
        status.inputs = ports.sources()
        status.outputs = ports.destinations()
        status.receivedCount = router.receivedCount
        if case .failed(let message) = router.sourceState { status.error = message }
        if status != midiStatus { midiStatus = status }
    }

    // MARK: Commands in

    func midiCommand(_ command: MIDICommand) {
        switch command {
        case .transport(let t): submit(.transport(t), from: .midi)
        case .macro(let id): submit(.runMacro(id), from: .midi)
        }
    }

    // MARK: Bindings

    public func saveBinding(_ binding: MIDIBinding) async {
        do {
            _ = try await store.saveMIDIBinding(binding)
            lastError = nil
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    public func deleteBinding(_ id: UUID) async {
        do {
            try await store.deleteMIDIBinding(id: id)
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    /// "Learn": waits for the next usable message from the chosen device (or the virtual port) and makes a binding of it for
    /// `command`. Nothing runs while it waits. Returns nil when cancelled or when MIDI is off.
    public func learnBinding(command: MIDICommand) async -> MIDIBinding? {
        guard let router = midiRouter else {
            lastError = "Turn MIDI on first, then choose the device you want to learn from."
            return nil
        }
        midiStatus.isLearning = true
        let learned = await router.learn()
        midiStatus.isLearning = false
        guard let learned else { return nil }
        let binding = MIDIBinding(name: MIDIText.pattern(learned.pattern), pattern: learned.pattern, command: command)
        let clashes = bindings.conflicts(with: binding)
        await saveBinding(binding)
        if !clashes.isEmpty {
            let names = clashes.map { "\u{201C}\($0.name)\u{201D}" }.joined(separator: ", ")
            note("\(binding.name) is also used by \(names). Both would run; change one so a pad does one thing.")
        }
        return binding
    }

    public func cancelLearning() { midiRouter?.cancelLearning() }
}
