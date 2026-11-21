// CUE-002b (item 5): the remote control server. Off until the operator turns it on. While on, a phone pairs with the six-digit code
// shown here, and everything it sends goes through the one command path. Paired devices are kept as salted hashes in the library.
import Foundation
import Network
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

/// FIX-E: what the model needs of the server. `RemoteServer` is the real one; a test puts a fake behind it.
public protocol RemoteServing: AnyObject, Sendable {
    var isRunning: Bool { get }
    var port: UInt16? { get }
    var currentPairingCode: String { get }
    var pairingCodeExpiresAt: Date { get }
    func listTokens() -> [TokenInfo]
    func revoke(id: UUID)
    func revokeAll()
    func setEventHandler(_ h: (@Sendable (RemoteServerEvent) -> Void)?)
    func stateDidChange()
    func start() async throws -> UInt16
    func stop() async
}

extension RemoteServer: RemoteServing {}

extension CueModel {
    // MARK: On and off

    /// FIX-E: start, stop and port change are queued one behind the other, so the last request wins and the saved setting
    /// always says whether a server is listening.
    private func serialRemote(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = remoteChain
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        remoteChain = task
        await task.value
    }

    public func setRemoteEnabled(_ on: Bool) async {
        remote.isEnabled = on
        await serialRemote { [self] in
            if on { await startRemoteNow() } else { await stopRemoteNow() }
            remote.isEnabled = on && remoteServer != nil          // it could not start: stays off, and says why
            await save(remote, key: Self.remoteKey)
        }
    }

    public func setRemotePort(_ port: UInt16) async {
        guard port >= 1024 else { return }
        await serialRemote { [self] in
            guard port != remote.port else { return }
            remote.port = port
            if remoteServer != nil {
                await stopRemoteNow()
                await startRemoteNow()
                remote.isEnabled = remoteServer != nil
            }
            await save(remote, key: Self.remoteKey)
        }
    }

    func startRemote() async { await serialRemote { [self] in await startRemoteNow() } }

    /// Stops listening and releases the port. Waits until it is closed and the paired devices are written.
    public func stopRemote() async { await serialRemote { [self] in await stopRemoteNow() } }

    private func startRemoteNow() async {
        guard remoteServer == nil else { return }
        var configuration = RemoteServerConfiguration()
        configuration.port = remotePortOverride ?? remote.port
        configuration.loopbackOnly = remoteLoopbackOnly
        do {
            let tokens: any TokenStore
            if let persistence = tokenPersistence ?? settingsStore {
                let loaded = try await LibraryTokenStore.load(from: persistence, retryDelay: tokenRetryDelay)
                remoteTokens = loaded
                tokens = loaded
            } else {
                tokens = InMemoryTokenStore()
            }
            let target = CueRemoteTarget(model: self)
            let server = remoteServerFactory(target, tokens, configuration)
            server.setEventHandler { [weak self] event in
                Task { @MainActor in self?.remoteEvent(event) }
            }
            _ = try await server.start()
            remoteTarget = target
            remoteServer = server
            lastRemoteState = nil
            startWatchingNetwork()
            networkChanged()
        } catch {
            let text = Self.remoteMessage(for: error, port: configuration.port)
            remoteStatus = { var s = RemoteStatus(); s.error = text; return s }()
            note(text)
            remoteTokens = nil
        }
    }

    private func stopRemoteNow() async {
        pathMonitor?.cancel()
        pathMonitor = nil
        remoteAddressCache = []
        if let server = remoteServer {
            remoteServer = nil
            await server.stop()
        }
        if let problem = await remoteTokens?.flush() { note(problem + " Devices paired or revoked just now may be different after a restart.") }
        remoteTokens = nil
        remoteTarget = nil
        remoteStatus = RemoteStatus()
    }

    /// Waits for paired-device changes to reach the library.
    public func flushRemote() async {
        if let problem = await remoteTokens?.flush() { note(problem + " Devices paired or revoked just now may be different after a restart.") }
    }

    // MARK: Addresses (FIX-E)

    /// The network addresses are looked up when the server starts and when the network changes, never on the one-second tick.
    private func startWatchingNetwork() {
        guard watchesNetwork, !remoteLoopbackOnly, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] (_: NWPath) in
            Task { @MainActor in self?.networkChanged() }
        }
        monitor.start(queue: DispatchQueue(label: "worshipflow.remote-control.network"))
        pathMonitor = monitor
    }

    /// The Mac's network changed (or the server just started): look the addresses up again.
    func networkChanged() {
        guard let server = remoteServer, server.isRunning else { return }
        remoteAddressCache = server.port.map { remoteAddresses(port: $0) } ?? []
        refreshRemote()
    }

    private static func remoteMessage(for error: Error, port: UInt16) -> String {
        if case RemoteServerError.couldNotListen(let why) = error {
            return "Remote control could not start on port \(port): \(why) Another program may be using it; choose another port."
        }
        return "Remote control could not start: \(error.localizedDescription)"
    }

    // MARK: Status

    func remoteEvent(_ event: RemoteServerEvent) {
        switch event {
        case .paired:
            Task { @MainActor [weak self] in
                if let problem = await self?.remoteTokens?.flush(.pairings) {
                    self?.note(problem + " The device that just paired will have to pair again after a restart.")
                }
            }
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
        status.addresses = remoteAddressCache
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

    /// The server refuses the device at once; this returns when the revoke is on disk. If it cannot be written the operator is
    /// told in plain words, because after a restart the device would be paired again.
    public func revokeDevice(_ id: UUID) async {
        remoteServer?.revoke(id: id)
        refreshRemote()
        await reportRevokeWrite(what: "The revoke")
    }

    public func revokeAllDevices() async {
        remoteServer?.revokeAll()
        refreshRemote()
        await reportRevokeWrite(what: "Revoke all")
    }

    private func reportRevokeWrite(what: String) async {
        guard let problem = await remoteTokens?.flush(.revokes) else { return }
        let text = "\(what) is not saved: \(problem) The device is refused now, but it may be able to connect again after WORSHIPFLOW restarts. Revoke it again."
        note(text)
        append(ActivityLine(time: wallClock(), source: .button, text: text, isProblem: true))
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
