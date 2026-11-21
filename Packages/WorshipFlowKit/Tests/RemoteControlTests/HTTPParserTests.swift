// CUE-004: strict request parsing. Every byte from the network is hostile; what is not understood is refused.
import Testing
import Foundation
@testable import RemoteControl

private func parse(_ s: String) -> HTTPParseResult {
    HTTPRequestParser.parseHead(Data(s.utf8), limits: .standard)
}
private func parseBytes(_ d: Data) -> HTTPParseResult { HTTPRequestParser.parseHead(d, limits: .standard) }

private func failure(_ r: HTTPParseResult) -> Int? {
    if case .failure(let e) = r { return e.status } else { return nil }
}

@Suite struct HTTPParserTests {
    @Test func parsesASimpleRequest() {
        guard case .head(let h, let len) = parse("GET /api/v1/state?x=1 HTTP/1.1\r\nHost: 127.0.0.1:80\r\nAuthorization: Bearer abc\r\n\r\n") else {
            Issue.record("not parsed"); return
        }
        #expect(h.method == "GET")
        #expect(h.path == "/api/v1/state")
        #expect(h.query == "x=1")
        #expect(h.headers["host"] == "127.0.0.1:80")
        #expect(h.headers["authorization"] == "Bearer abc")
        #expect(h.contentLength == 0)
        #expect(len > 0)
    }

    @Test func asksForMoreUntilTheBlankLine() {
        guard case .needMore = parse("GET / HTTP/1.1\r\nHost: a\r\n") else { Issue.record("expected needMore"); return }
        guard case .needMore = parse("") else { Issue.record("expected needMore"); return }
    }

    @Test func readsContentLength() {
        guard case .head(let h, _) = parse("POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 12\r\n\r\n") else { Issue.record("no"); return }
        #expect(h.contentLength == 12)
    }

    @Test(arguments: [
        ("GET / HTTP/1.1\nHost: a\n\n", "bare line feeds"),
        ("GET / HTTP/1.1\r\nHost: a\r\n\n", "bare line feed at the end"),
        ("GET / HTTP/1.1\r\nHost: a\r\nX: 1\r\n  folded\r\n\r\n", "obsolete line folding"),
        ("GET / HTTP/1.1\r\nHost : a\r\n\r\n", "space before the colon"),
        ("GET / HTTP/1.1\r\nHost: a\r\nNoColonHere\r\n\r\n", "header without a colon"),
        ("GET / HTTP/1.1\r\nHost: a\r\n: empty\r\n\r\n", "empty header name"),
        ("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n", "two Host headers"),
        ("GET / HTTP/1.1\r\n\r\n", "no Host header"),
        ("GET / HTTP/1.1\r\nHost: a\r\nX-A: 1\r\nx-a: 2\r\n\r\n", "duplicate header, different case"),
        ("get / HTTP/1.1\r\nHost: a\r\n\r\n", "lower-case method"),
        ("GET  / HTTP/1.1\r\nHost: a\r\n\r\n", "double space in the request line"),
        ("GET / HTTP/1.1 \r\nHost: a\r\n\r\n", "trailing space in the request line"),
        ("GET http://evil/ HTTP/1.1\r\nHost: a\r\n\r\n", "absolute-form target"),
        ("GET * HTTP/1.1\r\nHost: a\r\n\r\n", "asterisk target"),
        ("GET /a#frag HTTP/1.1\r\nHost: a\r\n\r\n", "fragment in the target"),
        ("GET / HTTP/1.1\r\nHost: a\r\nX: \u{e9}\r\n\r\n", "non-ASCII header value"),
        ("GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n", "duplicate Content-Length"),
        ("GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 5, 5\r\n\r\n", "list Content-Length"),
        ("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: +5\r\n\r\n", "signed Content-Length"),
        ("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: -1\r\n\r\n", "negative Content-Length"),
        ("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 0x10\r\n\r\n", "hex Content-Length"),
        ("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: \r\n\r\n", "empty Content-Length"),
        ("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 1 2\r\n\r\n", "Content-Length with a space inside"),
        ("GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 4\r\n\r\n", "a GET with a body"),
    ] as [(String, String)])
    func rejectsMalformedRequests(_ raw: String, _ why: String) {
        let status = failure(parse(raw))
        #expect(status == 400, "\(why): expected 400, got \(String(describing: status))")
    }

    @Test func rejectsControlBytesAndNul() {
        var d = Data("GET / HTTP/1.1\r\nHost: a\r\nX: 1".utf8)
        d.append(0)
        d.append(Data("\r\n\r\n".utf8))
        #expect(failure(parseBytes(d)) == 400)
        var d2 = Data("GET / HTTP/1.1\r\nHost: a\r\nX: 1".utf8)
        d2.append(0x01)
        d2.append(Data("\r\n\r\n".utf8))
        #expect(failure(parseBytes(d2)) == 400)
    }

    @Test func transferEncodingIsNotImplementedAndRefused() {
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n")) == 501)
        // The classic smuggling shape: both headers. Refused, not guessed at.
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n")) == 501)
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: identity\r\n\r\n")) == 501)
    }

    @Test func otherHTTPVersionsAreRefused() {
        #expect(failure(parse("GET / HTTP/1.0\r\nHost: a\r\n\r\n")) == 505)
        #expect(failure(parse("GET / HTTP/2.0\r\nHost: a\r\n\r\n")) == 505)
        #expect(failure(parse("GET / HTTP/1.1x\r\nHost: a\r\n\r\n")) == 400)
    }

    @Test func expectIsRefused() {
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nExpect: 100-continue\r\nContent-Length: 2\r\n\r\n")) == 417)
    }

    @Test func oversizeBodyIsDecidedFromTheHeader() {
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 65537\r\n\r\n")) == 413)
        #expect(failure(parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 99999999999999999999\r\n\r\n")) == 413)
        guard case .head = parse("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 65536\r\n\r\n") else { Issue.record("limit itself is allowed"); return }
    }

    @Test func oversizeHeadersAreRefused() {
        let big = "GET / HTTP/1.1\r\nHost: a\r\nX: " + String(repeating: "a", count: 9000)
        #expect(failure(parse(big)) == 431)     // even without the blank line: do not keep buffering
        var many = "GET / HTTP/1.1\r\nHost: a\r\n"
        for i in 0..<70 { many += "X-\(i): 1\r\n" }
        many += "\r\n"
        #expect(failure(parse(many)) == 431)
        let longTarget = "GET /" + String(repeating: "a", count: 3000) + " HTTP/1.1\r\nHost: a\r\n\r\n"
        #expect(failure(parse(longTarget)) == 414)
    }

    @Test func headStopsAtTheBlankLine() {
        let raw = "POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n\r\nabc"
        guard case .head(_, let len) = parse(raw) else { Issue.record("no"); return }
        #expect(raw.utf8.count - len == 3)
    }
}
