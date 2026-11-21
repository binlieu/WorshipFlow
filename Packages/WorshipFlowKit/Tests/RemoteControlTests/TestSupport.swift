// CUE-004 test helpers: a raw loopback HTTP client (so tests can send malformed bytes), a recording fake target, a clock.
import Foundation
import Synchronization
import CueEngine
@testable import RemoteControl

// MARK: raw HTTP over a blocking socket

struct RawResponse: Sendable {
    var raw: Data
    var status: Int
    var headers: [String: String]
    var body: Data
    var bodyText: String { String(decoding: body, as: UTF8.self) }
    var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }
    var isEmpty: Bool { raw.isEmpty }
}

func parseRaw(_ raw: Data) -> RawResponse {
    let sep = Data("\r\n\r\n".utf8)
    guard let r = raw.range(of: sep) else { return RawResponse(raw: raw, status: 0, headers: [:], body: Data()) }
    let head = String(decoding: raw[..<r.lowerBound], as: UTF8.self)
    let lines = head.components(separatedBy: "\r\n")
    let status = lines.first.flatMap { $0.split(separator: " ").dropFirst().first }.flatMap { Int($0) } ?? 0
    var headers: [String: String] = [:]
    for l in lines.dropFirst() {
        if let c = l.firstIndex(of: ":") {
            headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
    }
    return RawResponse(raw: raw, status: status, headers: headers, body: Data(raw[r.upperBound...]))
}

func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async { cont.resume(returning: work()) }
    }
}

/// One TCP connection to 127.0.0.1. Used from one task at a time.
final class RawClient: @unchecked Sendable {   // the descriptor and buffer are touched by one task at a time in every test
    private var fd: Int32 = -1
    private(set) var received = Data()

    init?(port: UInt16) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if ok != 0 { Darwin.close(fd); fd = -1; return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { if fd >= 0 { Darwin.close(fd) } }

    func send(_ data: Data) {
        data.withUnsafeBytes { p in
            var off = 0
            while off < p.count {
                let n = write(fd, p.baseAddress.map { $0 + off }, p.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    /// Reads until the peer closes, `until` says enough, or `timeout` passes. Returns everything received so far.
    @discardableResult
    func read(timeout: TimeInterval = 3, until: ((Data) -> Bool)? = nil) -> Data {
        let end = Date().addingTimeInterval(timeout)
        while true {
            if let until, until(received) { break }
            let left = end.timeIntervalSinceNow
            if left <= 0 { break }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(min(left, 0.2) * 1000))
            if r < 0 { break }
            if r == 0 { continue }
            var buf = [UInt8](repeating: 0, count: 16384)
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { closed = true; break }
            received.append(contentsOf: buf[0..<n])
        }
        return received
    }
    private(set) var closed = false

    func close() { if fd >= 0 { Darwin.close(fd); fd = -1 } }
}

func rawRequestBytes(method: String, path: String, host: String?, headers: [(String, String)] = [], body: Data? = nil) -> Data {
    var s = "\(method) \(path) HTTP/1.1\r\n"
    if let host { s += "Host: \(host)\r\n" }
    for (k, v) in headers { s += "\(k): \(v)\r\n" }
    if let body { s += "Content-Length: \(body.count)\r\n" }
    s += "\r\n"
    var d = Data(s.utf8)
    if let body { d.append(body) }
    return d
}

/// Sends one request on a fresh connection and reads the full response (the server closes after each).
func http(_ port: UInt16, _ method: String = "GET", _ path: String, token: String? = nil, host: String? = nil,
          headers: [(String, String)] = [], json: Any? = nil, body: Data? = nil) async -> RawResponse {
    var hs = headers
    if let token { hs.append(("Authorization", "Bearer \(token)")) }
    var payload = body
    if let json, let d = try? JSONSerialization.data(withJSONObject: json) {
        payload = d
        hs.append(("Content-Type", "application/json"))
    }
    let bytes = rawRequestBytes(method: method, path: path, host: host ?? "127.0.0.1:\(port)", headers: hs, body: payload)
    return await blocking {
        guard let c = RawClient(port: port) else { return RawResponse(raw: Data(), status: 0, headers: [:], body: Data()) }
        c.send(bytes)
        c.read(timeout: 5)
        return parseRaw(c.received)
    }
}

// MARK: fakes

actor FakeTarget: RemoteControlTarget {
    private(set) var log: [String] = []
    private(set) var snapshots = 0
    var delayNanos: UInt64 = 0
    var state = RemoteState(mode: .live, live: RemoteSlideText(primary: "Slide 1"), next: RemoteSlideText(primary: "Slide 2"),
                            position: "1 of 3", presentationTitle: "Sunday",
                            playlist: [RemotePlaylistItem(title: "Opening", isLive: true), RemotePlaylistItem(title: "Sermon", isLive: false)],
                            timers: [RemoteTimer(name: "Message", value: "04:32", isRunning: true)],
                            macros: [RemoteMacro(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(), name: "Welcome")])
    var knownMacros: Set<UUID> = [UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()]
    var failNext: RemoteTargetError?

    func setDelay(_ ms: UInt64) { delayNanos = ms * 1_000_000 }
    func setState(_ s: RemoteState) { state = s }
    func setFail(_ e: RemoteTargetError?) { failNext = e }
    func resetLog() { log = [] }

    func perform(_ command: CueTransport) async throws {
        log.append("begin \(command.summary)")
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        if let e = failNext { failNext = nil; log.append("end \(command.summary)"); throw e }
        if case .next = command, let live = state.live {
            let n = (Int(live.primary.split(separator: " ").last ?? "") ?? 0) + 1
            state.live = RemoteSlideText(primary: "Slide \(n)")
        }
        if case .blackout(let m) = command { state.mode = (m == .off) ? .live : .blackedOut }
        log.append("end \(command.summary)")
    }

    func runMacro(id: UUID) async throws {
        log.append("begin macro \(id.uuidString.lowercased())")
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        guard knownMacros.contains(id) else { log.append("end macro"); throw RemoteTargetError.unknownMacro }
        log.append("end macro \(id.uuidString.lowercased())")
    }

    func snapshot() async -> RemoteState { snapshots += 1; return state }
}

final class TestClock: Sendable {
    private let t = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))
    var now: Date { t.withLock { $0 } }
    func advance(_ s: TimeInterval) { t.withLock { $0 = $0.addingTimeInterval(s) } }
    var asClosure: @Sendable () -> Date { { [self] in now } }
}

// MARK: running a server inside a test

struct Running {
    let server: RemoteServer
    let port: UInt16
    let target: FakeTarget
}

/// Starts a loopback server on an ephemeral port, runs `body`, and always stops the server afterwards.
func withServer(configure: (inout RemoteServerConfiguration) -> Void = { _ in },
                target: FakeTarget = FakeTarget(),
                clock: TestClock = TestClock(),
                tokens: TokenStore = InMemoryTokenStore(),
                _ body: (Running) async throws -> Void) async throws {
    var cfg = RemoteServerConfiguration()
    cfg.port = 0
    cfg.loopbackOnly = true
    cfg.requestTimeout = 2
    cfg.heartbeatInterval = 0.2
    configure(&cfg)
    let server = RemoteServer(target: target, tokens: tokens, configuration: cfg, clock: clock.asClosure)
    let port = try await server.start()
    do {
        try await body(Running(server: server, port: port, target: target))
    } catch {
        await server.stop()
        throw error
    }
    await server.stop()
}

/// Pairs with the current code and returns the bearer token.
func pairClient(_ r: Running, label: String = "Phone") async -> String {
    let res = await http(r.port, "POST", "/api/v1/pair", json: ["code": r.server.currentPairingCode, "label": label])
    return (res.json?["token"] as? String) ?? ""
}
