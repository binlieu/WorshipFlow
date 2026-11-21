// CUE-004: a deliberately small, strict HTTP/1.1 request reader and response writer. What is not understood is refused.
import Foundation

struct HTTPLimits: Sendable {
    var maxHeaderBytes = 8 * 1024
    var maxBodyBytes = 64 * 1024
    var maxHeaderCount = 64
    var maxTargetBytes = 2048
    static let standard = HTTPLimits()
}

struct HTTPParseError: Error, Equatable {
    var status: Int
    var reason: String
}

struct HTTPHead: Sendable, Equatable {
    var method: String
    var target: String
    var path: String
    var query: String?
    /// Lower-cased names. Duplicates are refused, so each appears once.
    var headers: [String: String]
    var contentLength: Int
}

enum HTTPParseResult {
    case needMore
    case head(HTTPHead, headLength: Int)
    case failure(HTTPParseError)
}

enum HTTPRequestParser {
    private static let crlfcrlf = Data("\r\n\r\n".utf8)

    private static func isTokenByte(_ b: UInt8) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"), UInt8(ascii: "%"), UInt8(ascii: "&"), UInt8(ascii: "'"),
             UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "^"), UInt8(ascii: "_"),
             UInt8(ascii: "`"), UInt8(ascii: "|"), UInt8(ascii: "~"): return true
        default: return false
        }
    }

    private static func fail(_ status: Int, _ reason: String) -> HTTPParseResult { .failure(HTTPParseError(status: status, reason: reason)) }

    static func parseHead(_ buffer: Data, limits: HTTPLimits) -> HTTPParseResult {
        guard let end = buffer.range(of: crlfcrlf) else {
            if buffer.count > limits.maxHeaderBytes { return fail(431, "headers too large") }
            // A bare line feed can never become valid; do not wait for more.
            if buffer.contains(0x0A), !buffer.isEmpty {
                var prev: UInt8 = 0
                for b in buffer { if b == 0x0A && prev != 0x0D { return fail(400, "bad line ending") }; prev = b }
            }
            return .needMore
        }
        let headLength = end.upperBound
        if headLength > limits.maxHeaderBytes { return fail(431, "headers too large") }
        let head = Array(buffer[buffer.startIndex..<end.lowerBound])

        // Byte-level checks: ASCII only, no controls except HT, and CR and LF only as a pair.
        var i = 0
        while i < head.count {
            let b = head[i]
            if b == 0x0D {
                guard i + 1 < head.count, head[i + 1] == 0x0A else { return fail(400, "bad line ending") }
                i += 2
                continue
            }
            if b == 0x0A { return fail(400, "bad line ending") }
            if b == 0x09 { i += 1; continue }
            if b < 0x20 || b >= 0x7F { return fail(400, "invalid character") }
            i += 1
        }
        let text = String(decoding: head, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return fail(400, "empty request") }

        // Request line: METHOD SP target SP HTTP/1.1, single spaces only.
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return fail(400, "bad request line") }
        let method = parts[0], target = parts[1], version = parts[2]
        guard method.utf8.allSatisfy({ isTokenByte($0) && $0 >= 0x41 && $0 <= 0x5A }) else { return fail(400, "bad method") }
        guard version.hasPrefix("HTTP/") else { return fail(400, "bad version") }
        guard version == "HTTP/1.1" else {
            return version.utf8.count == 8 && version.dropFirst(5).first?.isNumber == true && version.dropFirst(6).first == "."
                ? fail(505, "HTTP version not supported") : fail(400, "bad version")
        }
        guard target.utf8.count <= limits.maxTargetBytes else { return fail(414, "target too long") }
        guard target.hasPrefix("/"), !target.contains("#"), !target.contains("\\") else { return fail(400, "bad target") }
        var path = target
        var query: String?
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q])
            query = String(target[target.index(after: q)...])
        }

        // Header fields.
        let fieldLines = Array(lines.dropFirst())
        if fieldLines.count > limits.maxHeaderCount { return fail(431, "too many headers") }
        var headers: [String: String] = [:]
        for line in fieldLines {
            guard let first = line.utf8.first else { return fail(400, "empty header line") }
            if first == 0x20 || first == 0x09 { return fail(400, "folded header") }
            guard let colon = line.firstIndex(of: ":") else { return fail(400, "header without colon") }
            let name = String(line[..<colon])
            guard !name.isEmpty, name.utf8.allSatisfy(isTokenByte) else { return fail(400, "bad header name") }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            let key = name.lowercased()
            if headers[key] != nil { return fail(400, "duplicate header") }
            headers[key] = value
        }

        guard let host = headers["host"], !host.isEmpty else { return fail(400, "Host header required") }
        if headers["transfer-encoding"] != nil { return fail(501, "transfer encodings are not supported") }
        if headers["expect"] != nil { return fail(417, "Expect is not supported") }
        var contentLength = 0
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return fail(400, "bad Content-Length") }
            if raw.utf8.count > 9 { return fail(413, "body too large") }
            guard let n = Int(raw) else { return fail(400, "bad Content-Length") }
            if n > limits.maxBodyBytes { return fail(413, "body too large") }
            if n > 0 && method != "POST" { return fail(400, "unexpected body") }
            contentLength = n
        }
        return .head(HTTPHead(method: method, target: target, path: path, query: query, headers: headers, contentLength: contentLength),
                     headLength: headLength)
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [(String, String)] = []
    var body = Data()

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 417: return "Expectation Failed"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        default: return "Status"
        }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let data = (try? encoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: [("Content-Type", "application/json; charset=utf-8")], body: data)
    }

    static func error(_ status: Int, _ message: String, extra: [(String, String)] = []) -> HTTPResponse {
        var r = json(status, ["error": message])
        r.headers += extra
        return r
    }

    /// An empty body, used for 401 so a refusal says nothing.
    static func bare(_ status: Int, extra: [(String, String)] = []) -> HTTPResponse {
        HTTPResponse(status: status, headers: extra, body: Data())
    }

    /// The bytes to send. Always closes the connection afterwards: one request per connection, so nothing can be smuggled
    /// behind another. `api` adds no-store; every response says nosniff.
    func serialized(noStore: Bool) -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        var names = Set<String>()
        for (k, v) in headers { lines.append("\(k): \(v)"); names.insert(k.lowercased()) }
        if noStore && !names.contains("cache-control") { lines.append("Cache-Control: no-store") }
        lines.append("X-Content-Type-Options: nosniff")
        lines.append("Content-Length: \(body.count)")
        lines.append("Connection: close")
        var d = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        d.append(body)
        return d
    }
}
