// CUE-004 (AUTO-10, AUTO-13): the local-network remote control server. Off until started. Plain HTTP on Network.framework;
// see docs/features/CUE-004-remote-control.md for the endpoints, the pairing flow and the limits of plain HTTP.
import Foundation
import Network
import Synchronization
import CueEngine

public final class RemoteServer: @unchecked Sendable {
    // Concurrency: `queue` is serial and owns `runtime` and everything inside it (connections, streams, listener). The
    // other stored properties are immutable or guarded by a Mutex, so the public methods may be called from any thread.
    // Every call into the target goes through the runtime's CommandPump: one at a time, in arrival order.

    /// Everything that exists only while the server is running. Touched on `queue` only.
    final class Runtime: @unchecked Sendable {
        let listener: NWListener
        let pump = CommandPump(maxPending: 256)
        var policy: HostPolicy?
        var connections: [ObjectIdentifier: ServerConnection] = [:]
        var streams: [ObjectIdentifier: ServerConnection] = [:]
        var lastState: RemoteState?
        var heartbeat: DispatchSourceTimer?
        var startContinuation: CheckedContinuation<UInt16, Error>?
        var stopContinuation: CheckedContinuation<Void, Never>?
        init(listener: NWListener) { self.listener = listener }
        func resumeStop() {
            if let c = stopContinuation { stopContinuation = nil; c.resume() }
        }
    }

    private struct Published { var running = false; var port: UInt16?; var open = 0 }

    let queue = DispatchQueue(label: "worshipflow.remote-control.server")
    let config: RemoteServerConfiguration
    private let target: RemoteControlTarget
    private let authority: TokenAuthority
    private let pairing: PairingManager
    private var runtime: Runtime?                       // queue only
    private let published = Mutex(Published())
    private let handler = Mutex<(@Sendable (RemoteServerEvent) -> Void)?>(nil)

    public convenience init(target: RemoteControlTarget, tokens: TokenStore = InMemoryTokenStore(),
                            configuration: RemoteServerConfiguration = RemoteServerConfiguration(),
                            clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(target: target, tokens: tokens, configuration: configuration, clock: clock, randomBytes: SecureRandom.bytes)
    }

    init(target: RemoteControlTarget, tokens: TokenStore, configuration: RemoteServerConfiguration,
         clock: @escaping @Sendable () -> Date, randomBytes: @escaping @Sendable (Int) throws -> Data) {
        self.target = target
        self.config = configuration
        self.authority = TokenAuthority(store: tokens, clock: clock, maxTokens: configuration.maxPairedDevices, randomBytes: randomBytes)
        self.pairing = PairingManager(configuration: configuration, clock: clock, randomBytes: randomBytes)
    }

    // MARK: public surface

    public var isRunning: Bool { published.withLock { $0.running } }
    /// The port in use while running (useful when the configured port was 0).
    public var port: UInt16? { published.withLock { $0.port } }
    var openConnectionCount: Int { published.withLock { $0.open } }

    /// The six-digit code to show the operator. Rotates every two minutes and after each successful pairing.
    public var currentPairingCode: String { pairing.currentCode }
    public var pairingCodeExpiresAt: Date { pairing.expiresAt }
    public func rotatePairingCode() { pairing.rotateNow() }

    public func listTokens() -> [TokenInfo] { authority.list() }

    public func revoke(id: UUID) {
        guard authority.revoke(id: id) else { return }
        emit(.tokenRevoked(id))
        queue.async { [self] in closeStreams { $0 == id } }
    }

    public func revokeAll() {
        authority.revokeAll()
        emit(.allTokensRevoked)
        queue.async { [self] in closeStreams { _ in true } }
    }

    public func setEventHandler(_ h: (@Sendable (RemoteServerEvent) -> Void)?) { handler.withLock { $0 = h } }

    /// The app calls this when the show changed from the operator's side. Connected phones get the new state.
    public func stateDidChange() {
        queue.async { [self] in
            guard let rt = runtime else { return }
            refresh(rt, initialFor: nil)
        }
    }

    /// Starts listening and returns the port. Throws if it is already running or the port cannot be used.
    public func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in beginStart(cont) }
        }
    }

    /// Stops listening, closes every connection and releases the port. Requests still waiting for the app are dropped.
    public func stop() async {
        await withCheckedContinuation { cont in
            queue.async { [self] in beginStop(cont) }
        }
    }

    // MARK: start and stop (queue)

    private func beginStart(_ cont: CheckedContinuation<UInt16, Error>) {
        guard runtime == nil else { cont.resume(throwing: RemoteServerError.alreadyRunning); return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let wanted = config.port == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: config.port) ?? .any)
        let listener: NWListener
        do {
            if config.loopbackOnly {
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: wanted)
                listener = try NWListener(using: params)
            } else {
                listener = try NWListener(using: params, on: wanted)
            }
        } catch {
            cont.resume(throwing: RemoteServerError.couldNotListen("\(error)"))
            return
        }
        let rt = Runtime(listener: listener)
        rt.startContinuation = cont
        runtime = rt
        listener.stateUpdateHandler = { [self] state in listenerState(state, rt) }
        listener.newConnectionHandler = { [self] connection in accept(connection, rt) }
        listener.start(queue: queue)
    }

    private func listenerState(_ state: NWListener.State, _ rt: Runtime) {
        switch state {
        case .ready:
            guard runtime === rt, let port = rt.listener.port?.rawValue else { return }
            rt.policy = HostPolicy(port: port, allowedNames: HostPolicy.ownNames(extra: config.additionalAllowedHosts),
                                   localAddresses: HostPolicy.systemLocalAddresses)
            startHeartbeat(rt)
            published.withLock { $0 = Published(running: true, port: port, open: 0) }
            emit(.started(port: port))
            if let c = rt.startContinuation { rt.startContinuation = nil; c.resume(returning: port) }
        case .failed(let error):
            guard runtime === rt else { return }
            if let c = rt.startContinuation {
                rt.startContinuation = nil
                c.resume(throwing: RemoteServerError.couldNotListen("\(error)"))
            }
            tearDown(rt)
        case .cancelled:
            if let c = rt.startContinuation { rt.startContinuation = nil; c.resume(throwing: RemoteServerError.couldNotListen("cancelled")) }
            rt.resumeStop()
        default:
            break
        }
    }

    private func tearDown(_ rt: Runtime) {
        if runtime === rt { runtime = nil }
        let wasRunning = published.withLock { p -> Bool in let r = p.running; p = Published(); return r }
        rt.pump.stop()
        rt.heartbeat?.cancel()
        rt.heartbeat = nil
        let all = Array(rt.connections.values)
        rt.connections.removeAll()
        rt.streams.removeAll()
        for c in all { c.finish() }
        rt.listener.stateUpdateHandler = nil
        rt.listener.newConnectionHandler = nil
        rt.listener.cancel()
        if wasRunning { emit(.stopped) }
    }

    private func beginStop(_ cont: CheckedContinuation<Void, Never>) {
        guard let rt = runtime else { cont.resume(); return }
        rt.stopContinuation = cont
        // The listener's state handler is cleared by tearDown, so wait on the cancellation another way: poll briefly.
        tearDown(rt)
        waitForCancellation(rt, attempts: 40)
    }

    /// Resumes the stop once the listening socket is really gone (the port can be bound again), or after a bound.
    private func waitForCancellation(_ rt: Runtime, attempts: Int) {
        if rt.listener.state == .cancelled || attempts <= 0 {
            rt.resumeStop()
            return
        }
        queue.asyncAfter(deadline: .now() + 0.05) { [self] in waitForCancellation(rt, attempts: attempts - 1) }
    }

    private func startHeartbeat(_ rt: Runtime) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.heartbeatInterval, repeating: config.heartbeatInterval)
        timer.setEventHandler { [self] in
            let beat = Data(": heartbeat\n\n".utf8)
            for conn in rt.streams.values {
                if let id = conn.streamTokenID, !authority.contains(id: id) { conn.finish() } else { conn.sendEvent(beat) }
            }
        }
        rt.heartbeat = timer
        timer.resume()
    }

    // MARK: connections (queue)

    private func accept(_ connection: NWConnection, _ rt: Runtime) {
        guard runtime === rt else { connection.cancel(); return }
        guard let raw = PeerAddress.raw(of: connection.endpoint), PeerAddress.isLocalNetwork(raw) else {
            emit(.refusedPeer(address: PeerAddress.raw(of: connection.endpoint).map(PeerAddress.key) ?? "unknown"))
            connection.cancel()
            return
        }
        guard rt.connections.count < config.maxConnections else {
            emit(.refusedConnectionLimit)
            connection.cancel()
            return
        }
        let conn = ServerConnection(connection: connection, server: self, runtime: rt, peer: PeerAddress.key(raw))
        rt.connections[ObjectIdentifier(conn)] = conn
        published.withLock { $0.open = rt.connections.count }
        conn.start()
    }

    func connectionClosed(_ conn: ServerConnection) {
        let rt = conn.runtime
        rt.connections[ObjectIdentifier(conn)] = nil
        rt.streams[ObjectIdentifier(conn)] = nil
        if runtime === rt { published.withLock { $0.open = rt.connections.count } }
    }

    private func closeStreams(where match: (UUID) -> Bool) {
        guard let rt = runtime else { return }
        for conn in Array(rt.streams.values) {
            if let id = conn.streamTokenID, match(id) { conn.finish() }
        }
    }

    private func emit(_ event: RemoteServerEvent) {
        let h = handler.withLock { $0 }
        h?(event)
    }

    // MARK: routing (queue)

    func handle(_ conn: ServerConnection, _ request: HTTPRequest) {
        let rt = conn.runtime
        guard runtime === rt, let policy = rt.policy else { conn.finish(); return }
        let head = request.head
        let host = head.headers["host"] ?? ""
        guard policy.isAllowedHost(host) else { conn.respond(.error(403, "host not allowed")); return }
        guard policy.isAllowedOrigin(head.headers["origin"], host: host) else { conn.respond(.error(403, "cross-site request refused")); return }

        let path = head.path
        if path == "/" {
            guard head.method == "GET" else { conn.respond(.error(405, "method not allowed", extra: [("Allow", "GET")])); return }
            conn.respond(HTTPResponse(status: 200, headers: [
                ("Content-Type", "text/html; charset=utf-8"),
                ("Content-Security-Policy", ControlPage.contentSecurityPolicy),
                ("X-Frame-Options", "DENY"),
                ("Referrer-Policy", "no-referrer"),
            ], body: Data(ControlPage.html.utf8)))
            return
        }
        if path == "/api/v1/pair" { pair(conn, request); return }
        guard path.hasPrefix("/api/") else { conn.respond(.error(404, "not found")); return }

        // Everything else under /api needs a token, checked before the route is even looked at, so an unknown
        // client learns nothing about which routes exist.
        guard let token = Self.bearer(head.headers["authorization"]), let info = authority.authenticate(token) else {
            conn.respond(.bare(401, extra: [("WWW-Authenticate", "Bearer")]))
            return
        }
        authenticated(conn, request, tokenID: info.id)
    }

    private static func bearer(_ header: String?) -> String? {
        guard let header else { return nil }
        let parts = header.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].lowercased() == "bearer", !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    private static func isJSON(_ head: HTTPHead) -> Bool {
        guard let ct = head.headers["content-type"] else { return false }
        let main = ct.split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return main == "application/json"
    }

    private static func object(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private func pair(_ conn: ServerConnection, _ request: HTTPRequest) {
        guard request.head.method == "POST" else { conn.respond(.error(405, "method not allowed", extra: [("Allow", "POST")])); return }
        guard Self.isJSON(request.head) else { conn.respond(.error(415, "send application/json")); return }
        guard let obj = Self.object(request.body), Set(obj.keys) == ["code", "label"],
              let code = obj["code"] as? String, let label = obj["label"] as? String else {
            conn.respond(.error(400, "expected {\"code\": string, \"label\": string}"))
            return
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            conn.respond(.error(400, "label must be 1 to 64 characters without control characters"))
            return
        }
        switch pairing.attempt(code: code, address: conn.peer) {
        case .lockedOut(let retry, let isNew):
            if isNew { emit(.pairingLockedOut(address: conn.peer, retryAfter: retry)) }
            conn.respond(.error(429, "too many attempts", extra: [("Retry-After", String(Int(retry.rounded(.up)))) ]))
        case .wrong:
            emit(.pairingRejected(address: conn.peer))
            conn.respond(.error(403, "invalid or expired code"))
        case .accepted:
            do {
                let issued = try authority.issue(label: name)
                emit(.paired(tokenID: issued.info.id, label: name))
                conn.respond(.json(200, ["token": issued.token, "tokenID": issued.info.id.uuidString.lowercased()]))
            } catch TokenAuthority.Failure.tooManyDevices {
                conn.respond(.error(409, "too many paired devices; revoke one first"))
            } catch {
                conn.respond(.error(500, "could not create a token"))
            }
        }
    }

    private func authenticated(_ conn: ServerConnection, _ request: HTTPRequest, tokenID: UUID) {
        let head = request.head
        let method = head.method
        func wrongMethod(_ allow: String) { conn.respond(.error(405, "method not allowed", extra: [("Allow", allow)])) }
        let segments = head.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        switch head.path {
        case "/api/v1/state":
            guard method == "GET" else { wrongMethod("GET"); return }
            submit(conn) { target in
                let s = await target.snapshot()
                return (.json(200, s), s)
            }
        case "/api/v1/transport":
            guard method == "POST" else { wrongMethod("POST"); return }
            guard Self.isJSON(head) else { conn.respond(.error(415, "send application/json")); return }
            switch Self.parseTransport(request.body) {
            case .failure(let message):
                conn.respond(.error(400, message.text))
            case .success(let command):
                submit(conn) { target in
                    do { try await target.perform(command) } catch { return (Self.mapped(error), nil) }
                    let s = await target.snapshot()
                    return (.json(200, StateEnvelope(state: s)), s)
                }
            }
        case "/api/v1/events":
            guard method == "GET" else { wrongMethod("GET"); return }
            openStream(conn, tokenID: tokenID)
        default:
            if segments.count == 6, segments[0].isEmpty, segments[1] == "api", segments[2] == "v1", segments[3] == "macros", segments[5] == "run",
               !segments[4].contains("%"), let id = UUID(uuidString: segments[4]) {
                guard method == "POST" else { wrongMethod("POST"); return }
                submit(conn) { target in
                    do { try await target.runMacro(id: id) } catch { return (Self.mapped(error), nil) }
                    let s = await target.snapshot()
                    return (.json(200, StateEnvelope(state: s)), s)
                }
            } else {
                conn.respond(.error(404, "not found"))
            }
        }
    }

    private struct StateEnvelope: Encodable { var state: RemoteState }

    private static func mapped(_ error: Error) -> HTTPResponse {
        switch error as? RemoteTargetError {
        case .unknownMacro?: return .error(404, "unknown macro")
        case .unavailable?: return .error(503, "not available right now")
        case .rejected(let why)?: return .error(409, String(why.prefix(200)))
        case nil: return .error(500, "the command failed")
        }
    }

    // MARK: commands

    private enum TransportProblem: Error { case message(String); var text: String { if case .message(let m) = self { return m }; return "" } }

    private static func parseTransport(_ body: Data) -> Result<CueTransport, TransportProblem> {
        guard let obj = object(body) else { return .failure(.message("body must be a JSON object")) }
        guard let name = obj["command"] as? String else { return .failure(.message("missing \"command\"")) }
        func only(_ keys: Set<String>) -> Bool { Set(obj.keys) == keys }
        switch name {
        case "next", "previous", "clear", "clearAll", "stop":
            guard only(["command"]) else { return .failure(.message("unexpected fields")) }
            switch name {
            case "next": return .success(.next)
            case "previous": return .success(.previous)
            case "clear": return .success(.clear)
            case "clearAll": return .success(.clearAll)
            default: return .success(.stop)
            }
        case "goToSlide":
            guard only(["command", "index"]) else { return .failure(.message("goToSlide needs \"index\" and nothing else")) }
            guard let n = obj["index"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !CFNumberIsFloatType(n),
                  (0...100_000).contains(n.intValue) else { return .failure(.message("\"index\" must be a whole number from 0 to 100000")) }
            return .success(.goToSlide(index: n.intValue))
        case "blackout":
            guard only(["command", "mode"]) else { return .failure(.message("blackout needs \"mode\" and nothing else")) }
            guard let mode = (obj["mode"] as? String).flatMap(CueBlackout.init(rawValue:)) else {
                return .failure(.message("\"mode\" must be on, off or toggle"))
            }
            return .success(.blackout(mode))
        default:
            return .failure(.message("unknown command"))
        }
    }

    /// Queues work on the target. The pump runs it one at a time in submission order; the answer goes back on `queue`.
    private func submit(_ conn: ServerConnection, _ work: @escaping @Sendable (RemoteControlTarget) async -> (HTTPResponse, RemoteState?)) {
        let rt = conn.runtime
        let target = self.target
        let accepted = rt.pump.submit { [self] in
            let (response, state) = await work(target)
            queue.async { [self] in
                if let state { publish(state, rt, initialFor: nil) }
                conn.respond(response)
            }
        }
        if !accepted { conn.respond(.error(503, "busy")) }
    }

    // MARK: events (queue)

    private func openStream(_ conn: ServerConnection, tokenID: UUID) {
        let rt = conn.runtime
        conn.beginStream(tokenID: tokenID)
        rt.streams[ObjectIdentifier(conn)] = conn
        if !refresh(rt, initialFor: conn) { conn.finish() }
    }

    /// Reads the state through the pump and publishes it. `initialFor` always receives it; others only if it changed.
    @discardableResult
    private func refresh(_ rt: Runtime, initialFor conn: ServerConnection?) -> Bool {
        let target = self.target
        return rt.pump.submit { [self] in
            let state = await target.snapshot()
            queue.async { [self] in publish(state, rt, initialFor: conn) }
        }
    }

    private func publish(_ state: RemoteState, _ rt: Runtime, initialFor conn: ServerConnection?) {
        guard runtime === rt else { return }
        let changed = state != rt.lastState
        rt.lastState = state
        guard changed || conn != nil else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(state) else { return }
        var message = Data("event: state\ndata: ".utf8)
        message.append(json)
        message.append(Data("\n\n".utf8))
        if changed {
            for stream in rt.streams.values { stream.sendEvent(message) }
        } else if let conn {
            conn.sendEvent(message)
        }
    }
}
