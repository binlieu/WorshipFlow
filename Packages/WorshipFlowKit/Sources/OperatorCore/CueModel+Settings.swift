// CUE-002b (items 4 and 5): the settings of the two control inputs, kept in the library's app state, and the model's lifecycle.
// MIDI and the remote server are OFF until the operator turns them on; a relaunch brings back only what was turned on.
import Foundation
import MIDIIO

public struct MIDISettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    /// The input device by its stable id (CoreMIDI's unique id), and its name for showing while it is absent.
    public var inputID: Int32?
    public var inputName: String?
    public var outputID: Int32?
    public var outputName: String?
    /// The app's own virtual ports ("WorshipFlow In" and "WorshipFlow Out"), for other programs on this Mac.
    public var virtualPorts = false
    public init() {}
}

public struct RemoteSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var port: UInt16 = 8765
    public init() {}
}

extension CueModel {
    static let midiKey = "cue.midi.settings"
    static let remoteKey = "cue.remote.settings"

    /// Reads the library and the saved settings, and starts whatever the operator had turned on.
    public func start() async {
        await reload()
        midi = await load(MIDISettings.self, key: Self.midiKey) ?? MIDISettings()
        remote = await load(RemoteSettings.self, key: Self.remoteKey) ?? RemoteSettings()
        if midi.isEnabled { startMIDI() }
        if remote.isEnabled { await startRemote() }
    }

    /// Stops MIDI and releases its ports. The remote server is stopped by `stopRemote()`, which waits for the port to close.
    public func shutdown() {
        stopMIDI()
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) async -> T? {
        guard let settingsStore, let text = try? await settingsStore.state(for: key), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) async {
        guard let settingsStore, let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return }
        do { try await settingsStore.setState(text, for: key) } catch { lastError = "Could not remember the setting: \(error.localizedDescription)" }
    }
}
