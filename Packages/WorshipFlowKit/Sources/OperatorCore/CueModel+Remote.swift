// CUE-002b (item 5): the remote control server. Off until the operator turns it on. While on, a phone pairs with the six-digit code
// shown here, and everything it sends goes through the one command path. Paired devices are kept as salted hashes in the library.
import Foundation
import CueEngine
import Domain
import Persistence
import RemoteControl

public struct RemoteDevice: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var createdAt: Date
    public var lastUsed: Date?
}

public struct RemoteStatus: Equatable, Sendable {
    public var isRunning = false
    public var port: UInt16?
    /// Where to open the control page on a phone, one per network address of this Mac.
    public var addresses: [String] = []
    public var devices: [RemoteDevice] = []
    public var error: String?
    public init() {}
}

public struct RemotePairing: Equatable, Sendable {
    public var code: String
    public var expiresAt: Date
}

extension CueModel {
    // MARK: On and off

    public func setRemoteEnabled(_ on: Bool) async {
        remote.isEnabled = on
        if on {
            await startRemote()
            if !remoteStatus.isRunning { remote.isEnabled = false }       // it could not start: stays off, and says why
        } else {
            await stopRemote()
        }
        await save(remote, key: Self.remoteKey)
    }

    public func setRemotePort(_ port: UInt16) async {
        guard port >= 1024, port != remote.port else { return }
        remote.port = port
        await save(remote, key: Self.remoteKey)
        if remoteServer != nil {
            await stopRemote()
            await startRemote()
        }
    }

    func startRemote() async {
        guard remoteServer == nil else { return }
        var configuration = RemoteServerConfiguration()
        configuration.port = remotePortOverride ?? remote.port
        configuration.loopbackOnly = remoteLoopbackOnly
        do {
            let tokens: any TokenStore
            if let settingsStore {
                let loaded = try await LibraryTokenStore.load(from: settingsStore)
                remoteTokens = loaded
                tokens = loaded
            } else {
                tokens = InMemoryTokenStore()
            }
            let target = CueRemoteTarget(model: self)
            let server = RemoteServer(target: target, tokens: tokens, configuration: configuration)
            server.setEventHandler { [weak self] event in
                Task { @MainActor in self?.remoteEvent(event) }
            }
            _ = try await server.start()
            remoteTarget = target
            remoteServer = server
            lastRemoteState = nil
            refreshRemote()
        } catch {
            let text = Self.remoteMessage(for: error, port: configuration.port)
            remoteStatus = { var s = RemoteStatus(); s.error = text; return s }()
            note(text)
            remoteTokens = nil
        }
    }

    /// Stops listening and releases the port. Waits until it is closed and the paired devices are written.
    public func stopRemote() async {
        if let server = remoteServer {
            remoteServer = nil
            await server.stop()
        }
        await remoteTokens?.flush()
        remoteTokens = nil
        remoteTarget = nil
        remoteStatus = RemoteStatus()
    }

    /// Waits for paired-device changes to reach the library.
    public func flushRemote() async { await remoteTokens?.flush() }

    private static func remoteMessage(for error: Error, port: UInt16) -> String {
        if case RemoteServerError.couldNotListen(let why) = error {
            return "Remote control could not start on port \(port): \(why) Another program may be using it; choose another port."
        }
        return "Remote control could not start: \(error.localizedDescription)"
    }

    // MARK: Status

    func remoteEvent(_ event: RemoteServerEvent) {
        switch event {
        case .pairingLockedOut(let address, _):
            note("A device at \(address) typed the wrong pairing code too many times and was locked out for a minute.")
        case .refusedPeer(let address):
            note("A device outside this network (\(address)) tried to connect and was refused.")
        default: break
        }
        refreshRemote()
    }

    public func refreshRemote() {
        guard let server = remoteServer, server.isRunning else { return }
        var status = RemoteStatus()
        status.isRunning = true
        status.port = server.port
        status.addresses = server.port.map { remoteAddresses(port: $0) } ?? []
        status.devices = server.listTokens().map { RemoteDevice(id: $0.id, label: $0.label, createdAt: $0.createdAt, lastUsed: $0.lastUsed) }
        if status != remoteStatus { remoteStatus = status }
    }

    public func remoteAddresses(port: UInt16) -> [String] {
        if remoteLoopbackOnly { return ["http://127.0.0.1:\(port)"] }
        return localAddresses().map { "http://\($0):\(port)" }
    }

    /// The code to read out and when it stops working. Read fresh each time: it changes every two minutes.
    public func remotePairing() -> RemotePairing? {
        guard let server = remoteServer, server.isRunning else { return nil }
        return RemotePairing(code: server.currentPairingCode, expiresAt: server.pairingCodeExpiresAt)
    }

    public func revokeDevice(_ id: UUID) async {
        remoteServer?.revoke(id: id)
        refreshRemote()
    }

    public func revokeAllDevices() async {
        remoteServer?.revokeAll()
        refreshRemote()
    }

    // MARK: What the server needs

    func hasMacro(_ id: UUID) -> Bool { library.macro(id: id) != nil }

    func remoteSnapshot() -> RemoteState {
        var state = remoteStateSource?() ?? RemoteState()
        state.macros = macros.map { RemoteMacro(id: $0.id, name: $0.name) }
        return state
    }

    /// The app calls this when the show, the timers or the playlist may have changed. Connected phones get the new state.
    public func remoteStateMayHaveChanged() {
        guard let server = remoteServer, server.isRunning else { return }
        let state = remoteSnapshot()
        guard state != lastRemoteState else { return }
        lastRemoteState = state
        server.stateDidChange()
    }
}
