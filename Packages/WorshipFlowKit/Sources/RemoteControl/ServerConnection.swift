// CUE-004: one client connection. Reads one strict request, then either answers once and closes, or becomes an event stream.
import Foundation
import Network

struct HTTPRequest: Sendable {
    var head: HTTPHead
    var body: Data
}

/// Confined to the server's serial queue: every method runs there (Network.framework callbacks are delivered on it).
/// `@unchecked Sendable` only so it can be captured by blocks that are queued back onto that same queue.
final class ServerConnection: @unchecked Sendable {
    private enum Phase {
        case head
        case body(HTTPHead)
        case processing
        case streaming(tokenID: UUID)
        case closing
    }

    let peer: String
    let runtime: RemoteServer.Runtime
    private let connection: NWConnection
    private let server: RemoteServer
    private let limits: HTTPLimits
    private var phase = Phase.head
    private var buffer = Data()
    private var discarded = 0
    private var finished = false
    private var pendingWrites = 0
    private var deadline: DispatchWorkItem?

    init(connection: NWConnection, server: RemoteServer, runtime: RemoteServer.Runtime, peer: String) {
        self.connection = connection
        self.server = server
        self.runtime = runtime
        self.peer = peer
        self.limits = HTTPLimits(maxHeaderBytes: server.config.maxHeaderBytes, maxBodyBytes: server.config.maxBodyBytes)
    }

    var streamTokenID: UUID? {
        if case .streaming(let id) = phase { return id }
        return nil
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled: finish()
            default: break
            }
        }
        connection.start(queue: server.queue)
        schedule(after: server.config.requestTimeout) { [self] in
            switch phase {
            case .head, .body: finish()        // too slow: dropped without a word
            default: break
            }
        }
        receive()
    }

    // MARK: reading

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            if finished { return }
            if error != nil { finish(); return }
            if let data, !data.isEmpty { handle(data) }
            if finished { return }
            if isComplete {
                switch phase {
                case .head, .body, .streaming: finish()
                case .processing, .closing: break      // the answer is still on its way
                }
                return
            }
            receive()
        }
    }

    private func handle(_ data: Data) {
        switch phase {
        case .head, .body:
            buffer.append(data)
            advance()
        case .processing, .streaming, .closing:
            // Nothing more is expected from this client. Discard, with a bound.
            discarded += data.count
            if discarded > 1_000_000 { finish() }
        }
    }

    private func advance() {
        if case .head = phase {
            switch HTTPRequestParser.parseHead(buffer, limits: limits) {
            case .needMore:
                return
            case .failure(let e):
                respond(.error(e.status, e.reason), linger: true)
                return
            case .head(let head, let length):
                buffer = Data(buffer.dropFirst(length))
                phase = .body(head)
            }
        }
        if case .body(let head) = phase {
            if buffer.count > head.contentLength {
                respond(.error(400, "unexpected data after the request"), linger: true)
                return
            }
            if buffer.count == head.contentLength {
                phase = .processing
                let body = buffer
                buffer = Data()
                cancelDeadline()
                schedule(after: server.config.handlerTimeout) { [self] in
                    if case .processing = phase { respond(.error(504, "the show did not answer in time"), linger: false) }
                }
                server.handle(self, HTTPRequest(head: head, body: body))
            }
        }
    }

    // MARK: writing

    /// Sends the one response and closes. `linger` keeps reading for a moment so a client that is still sending is not
    /// reset before it has read the answer.
    func respond(_ response: HTTPResponse, linger: Bool = false) {
        if finished { return }
        switch phase {
        case .closing, .streaming: return
        default: break
        }
        phase = .closing
        cancelDeadline()
        let data = response.serialized(noStore: true)
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] _ in
            if linger {
                server.queue.asyncAfter(deadline: .now() + 0.25) { [self] in finish() }
            } else {
                finish()
            }
        })
    }

    /// Switches to a Server-Sent Events stream. The caller has already checked the token.
    func beginStream(tokenID: UUID) {
        if finished { return }
        phase = .streaming(tokenID: tokenID)
        cancelDeadline()
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\nretry: 3000\n\n"
        write(Data(head.utf8))
    }

    func sendEvent(_ data: Data) {
        if case .streaming = phase { write(data) }
    }

    private func write(_ data: Data) {
        if finished { return }
        pendingWrites += 1
        if pendingWrites > 32 { finish(); return }        // a client that does not read is dropped, not buffered without limit
        connection.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [self] error in
            pendingWrites -= 1
            if error != nil { finish() }
        })
    }

    // MARK: closing

    func finish() {
        if finished { return }
        finished = true
        cancelDeadline()
        connection.stateUpdateHandler = nil
        connection.cancel()
        server.connectionClosed(self)
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping @Sendable () -> Void) {
        cancelDeadline()
        let item = DispatchWorkItem(block: block)
        deadline = item
        server.queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelDeadline() {
        deadline?.cancel()
        deadline = nil
    }
}
