// CUE-004: the server on a real loopback socket with an ephemeral port. Every test stops its server.
import Testing
import Foundation
import Synchronization
import CueEngine
@testable import RemoteControl

private let macroID = "11111111-1111-1111-1111-111111111111"

@Suite struct RemoteServerLifecycleTests {
    @Test func offUntilStartedAndStopReleasesThePort() async throws {
        let target = FakeTarget()
        var cfg = RemoteServerConfiguration(); cfg.port = 0; cfg.loopbackOnly = true
        let server = RemoteServer(target: target, configuration: cfg)
        #expect(!server.isRunning)
        #expect(server.port == nil)
        let port = try await server.start()
        #expect(server.isRunning)
        #expect(server.port == port)
        #expect(await http(port, "GET", "/").status == 200)
        await server.stop()
        #expect(!server.isRunning)
        #expect(await http(port, "GET", "/").isEmpty, "nothing answers after stop")
        #expect(RawClient(port: port) == nil, "the port is released")
    }

    @Test func startingTwiceFailsAndRestartWorksOnTheSamePort() async throws {
        var cfg = RemoteServerConfiguration(); cfg.port = 0; cfg.loopbackOnly = true
        let server = RemoteServer(target: FakeTarget(), configuration: cfg)
        let port = try await server.start()
        do {
            _ = try await server.start()
            Issue.record("second start should throw")
        } catch let e as RemoteServerError {
            #expect(e == .alreadyRunning)
        } catch { Issue.record("wrong error \(error)") }
        await server.stop()
        await server.stop()    // stopping twice is harmless
        var cfg2 = cfg; cfg2.port = port
        let again = RemoteServer(target: FakeTarget(), configuration: cfg2)
        let p2 = try await again.start()
        #expect(p2 == port)
        #expect(await http(p2, "GET", "/").status == 200)
        await again.stop()
        // Same instance restarts too.
        let p3 = try await server.start()
        #expect(await http(p3, "GET", "/").status == 200)
        await server.stop()
    }

    @Test func startFailsCleanlyWhenThePortIsTaken() async throws {
        try await withServer { r in
            var cfg = RemoteServerConfiguration(); cfg.port = r.port; cfg.loopbackOnly = true
            let other = RemoteServer(target: FakeTarget(), configuration: cfg)
            do {
                _ = try await other.start()
                await other.stop()
                Issue.record("expected a failure")
            } catch {
                #expect(!other.isRunning)
            }
        }
    }

    @Test func stopClosesOpenEventStreams() async throws {
        var cfg = RemoteServerConfiguration(); cfg.port = 0; cfg.loopbackOnly = true; cfg.heartbeatInterval = 0.2
        let server = RemoteServer(target: FakeTarget(), configuration: cfg)
        let port = try await server.start()
        let code = server.currentPairingCode
        let paired = await http(port, "POST", "/api/v1/pair", json: ["code": code, "label": "P"])
        let token = try #require(paired.json?["token"] as? String)
        let stream = try #require(RawClient(port: port))
        stream.send(rawRequestBytes(method: "GET", path: "/api/v1/events", host: "127.0.0.1:\(port)", headers: [("Authorization", "Bearer \(token)")]))
        await blocking { stream.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("event: state") } }
        await server.stop()
        let closed = await blocking { stream.read(timeout: 3) { _ in false }; return stream.closed }
        #expect(closed)
    }
}

@Suite struct RemoteServerAuthTests {
    @Test func everyApiEndpointRefusesWithoutATokenAndGivesNoDetail() async throws {
        try await withServer { r in
            let calls: [(String, String)] = [
                ("GET", "/api/v1/state"), ("POST", "/api/v1/transport"), ("POST", "/api/v1/macros/\(macroID)/run"),
                ("GET", "/api/v1/events"), ("GET", "/api/v1/nothing"), ("DELETE", "/api/v1/state"), ("GET", "/api/state"), ("GET", "/api/"),
            ]
            for (m, p) in calls {
                let res = await http(r.port, m, p, json: m == "POST" ? ["command": "next"] : nil)
                #expect(res.status == 401, "\(m) \(p) -> \(res.status)")
                #expect(res.body.isEmpty, "\(m) \(p) leaks detail")
                #expect(res.headers["www-authenticate"] == "Bearer")
            }
            // Wrong tokens, wrong scheme, malformed header.
            for h in ["Bearer nope", "Bearer ", "Basic abc", "bearer", "Bearer a b", "\(UUID().uuidString).\(String(repeating: "A", count: 43))"] {
                let res = await http(r.port, "GET", "/api/v1/state", headers: [("Authorization", h)])
                #expect(res.status == 401, "\(h)")
            }
            #expect(await r.target.log.isEmpty, "nothing reached the target")
            #expect(await r.target.snapshots == 0)
        }
    }

    @Test func pairingGivesATokenThatWorks() async throws {
        let events = Mutex<[RemoteServerEvent]>([])
        try await withServer { r in
            r.server.setEventHandler { e in events.withLock { $0.append(e) } }
            let before = r.server.currentPairingCode
            let res = await http(r.port, "POST", "/api/v1/pair", json: ["code": before, "label": "Pastor's phone"])
            #expect(res.status == 200)
            let token = try #require(res.json?["token"] as? String)
            #expect(token.count >= 64)
            #expect(res.headers["cache-control"] == "no-store")
            let state = await http(r.port, "GET", "/api/v1/state", token: token)
            #expect(state.status == 200)
            #expect(r.server.listTokens().map(\.label) == ["Pastor's phone"])
            #expect(r.server.listTokens().first?.lastUsed != nil)
            // The code was used up.
            let again = await http(r.port, "POST", "/api/v1/pair", json: ["code": before, "label": "x"])
            #expect(again.status == 403)
            // Events never contain the token or any code.
            let dump = events.withLock { "\($0)" }
            #expect(!dump.contains(token))
            #expect(!dump.contains(before))
        }
    }

    @Test func wrongAndExpiredCodesAreRefused() async throws {
        let clock = TestClock()
        try await withServer(clock: clock) { r in
            let code = r.server.currentPairingCode
            let wrong = code == "000000" ? "111111" : "000000"
            let w = await http(r.port, "POST", "/api/v1/pair", json: ["code": wrong, "label": "x"])
            #expect(w.status == 403)
            #expect(w.json?["token"] == nil)
            clock.advance(121)
            let fresh = r.server.currentPairingCode
            if fresh != code {
                let expired = await http(r.port, "POST", "/api/v1/pair", json: ["code": code, "label": "x"])
                #expect(expired.status == 403)
            }
            #expect(r.server.listTokens().isEmpty)
        }
    }

    @Test func lockoutAndRecovery() async throws {
        let clock = TestClock()
        let events = Mutex<[RemoteServerEvent]>([])
        try await withServer(clock: clock) { r in
            r.server.setEventHandler { e in events.withLock { $0.append(e) } }
            let wrong = r.server.currentPairingCode == "000000" ? "111111" : "000000"
            for _ in 0..<4 { #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": wrong, "label": "x"]).status == 403) }
            let locked = await http(r.port, "POST", "/api/v1/pair", json: ["code": wrong, "label": "x"])
            #expect(locked.status == 429)
            #expect(locked.headers["retry-after"] != nil)
            // The right code is refused during the cool-down, and no token appears.
            let right = await http(r.port, "POST", "/api/v1/pair", json: ["code": r.server.currentPairingCode, "label": "x"])
            #expect(right.status == 429)
            #expect(r.server.listTokens().isEmpty)
            #expect(events.withLock { $0.contains { if case .pairingLockedOut = $0 { return true } else { return false } } })
            clock.advance(61)
            let ok = await http(r.port, "POST", "/api/v1/pair", json: ["code": r.server.currentPairingCode, "label": "x"])
            #expect(ok.status == 200)
        }
    }

    @Test func pairRequestsAreValidated() async throws {
        try await withServer { r in
            let code = r.server.currentPairingCode
            #expect(await http(r.port, "POST", "/api/v1/pair", body: Data("{".utf8)).status == 415, "no content type")
            #expect(await http(r.port, "POST", "/api/v1/pair", headers: [("Content-Type", "application/json")], body: Data("{".utf8)).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": code]).status == 400, "label required")
            #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": code, "label": ""]).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": code, "label": String(repeating: "a", count: 65)]).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": code, "label": "a\nb"]).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/pair", json: ["code": 123456, "label": "a"]).status == 400)
            #expect(await http(r.port, "GET", "/api/v1/pair").status == 405)
            #expect(r.server.listTokens().isEmpty)
        }
    }

    @Test func revokeTakesEffectOnTheNextRequestAndClosesThatClientsStream() async throws {
        try await withServer { r in
            let t1 = await pairClient(r, label: "One")
            let t2 = await pairClient(r, label: "Two")
            #expect(await http(r.port, "GET", "/api/v1/state", token: t1).status == 200)
            let s1 = try #require(RawClient(port: r.port))
            let s2 = try #require(RawClient(port: r.port))
            s1.send(rawRequestBytes(method: "GET", path: "/api/v1/events", host: "127.0.0.1:\(r.port)", headers: [("Authorization", "Bearer \(t1)")]))
            s2.send(rawRequestBytes(method: "GET", path: "/api/v1/events", host: "127.0.0.1:\(r.port)", headers: [("Authorization", "Bearer \(t2)")]))
            await blocking { s1.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("event: state") } }
            await blocking { s2.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("event: state") } }
            let id1 = try #require(r.server.listTokens().first { $0.label == "One" }?.id)
            r.server.revoke(id: id1)
            #expect(await http(r.port, "GET", "/api/v1/state", token: t1).status == 401)
            #expect(await http(r.port, "GET", "/api/v1/state", token: t2).status == 200)
            let closed1 = await blocking { s1.read(timeout: 3) { _ in false }; return s1.closed }
            #expect(closed1, "revoked client's stream is closed")
            #expect(await blocking { s2.read(timeout: 0.6) { _ in false }; return s2.closed } == false, "the other stream stays open")
            r.server.revokeAll()
            #expect(await http(r.port, "GET", "/api/v1/state", token: t2).status == 401)
            #expect(await blocking { s2.read(timeout: 3) { _ in false }; return s2.closed })
        }
    }
}

@Suite struct RemoteServerCommandTests {
    @Test func stateAndEachTransportCommandReachTheTargetOnce() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let st = await http(r.port, "GET", "/api/v1/state", token: t)
            #expect(st.status == 200)
            #expect(st.headers["cache-control"] == "no-store")
            #expect(st.headers["content-type"]?.hasPrefix("application/json") == true)
            #expect(st.json?["position"] as? String == "1 of 3")
            #expect(st.json?["presentationTitle"] as? String == "Sunday")
            #expect((st.json?["playlist"] as? [[String: Any]])?.count == 2)
            let cases: [([String: Any], String)] = [
                (["command": "next"], "Next slide"), (["command": "previous"], "Previous slide"),
                (["command": "goToSlide", "index": 4], "Go to slide 5"), (["command": "clear"], "Clear"),
                (["command": "clearAll"], "Clear all"), (["command": "blackout", "mode": "on"], "Blackout on"),
                (["command": "blackout", "mode": "off"], "Blackout off"), (["command": "stop"], "Stop"),
            ]
            for (body, summary) in cases {
                await r.target.resetLog()
                let res = await http(r.port, "POST", "/api/v1/transport", token: t, json: body)
                #expect(res.status == 200, "\(body)")
                #expect(res.json?["state"] != nil, "acknowledged with the resulting state")
                #expect(await r.target.log == ["begin \(summary)", "end \(summary)"], "\(body)")
            }
        }
    }

    @Test func theAcknowledgementCarriesTheStateAfterTheCommand() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let res = await http(r.port, "POST", "/api/v1/transport", token: t, json: ["command": "next"])
            let live = (res.json?["state"] as? [String: Any])?["live"] as? [String: Any]
            #expect(live?["primary"] as? String == "Slide 2")
        }
    }

    @Test func badTransportBodiesAreRefusedAndNeverReachTheTarget() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let bad: [Any] = [
                ["command": "explode"], ["command": "goToSlide"], ["command": "goToSlide", "index": -1], ["command": "goToSlide", "index": 1.5],
                ["command": "goToSlide", "index": true], ["command": "goToSlide", "index": 99_999_999], ["command": "blackout"],
                ["command": "blackout", "mode": "dim"], ["command": "next", "extra": 1], ["command": 5], [:], [1, 2], "next",
            ]
            for b in bad {
                let res = await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "application/json")],
                                     body: try? JSONSerialization.data(withJSONObject: b, options: [.fragmentsAllowed]))
                #expect(res.status == 400, "\(b) -> \(res.status)")
                #expect(res.json?["error"] is String)
            }
            #expect(await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "application/json")], body: Data("{not json".utf8)).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "application/json")], body: Data()).status == 400)
            #expect(await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "text/plain")], body: Data("{\"command\":\"next\"}".utf8)).status == 415)
            #expect(await r.target.log.isEmpty)
        }
    }

    @Test func macrosRunByIdAndUnknownOnesAre404() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            #expect(await http(r.port, "POST", "/api/v1/macros/\(macroID)/run", token: t).status == 200)
            #expect(await r.target.log == ["begin macro \(macroID)", "end macro \(macroID)"])
            let unknown = "22222222-2222-2222-2222-222222222222"
            #expect(await http(r.port, "POST", "/api/v1/macros/\(unknown)/run", token: t).status == 404)
            #expect(await http(r.port, "POST", "/api/v1/macros/not-a-uuid/run", token: t).status == 404)
            #expect(await http(r.port, "POST", "/api/v1/macros/%31/run", token: t).status == 404)
            #expect(await http(r.port, "GET", "/api/v1/macros/\(macroID)/run", token: t).status == 405)
        }
    }

    @Test func targetFailuresBecomeCleanErrors() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            await r.target.setFail(.rejected("Nothing is live"))
            let res = await http(r.port, "POST", "/api/v1/transport", token: t, json: ["command": "next"])
            #expect(res.status == 409)
            #expect(res.json?["error"] as? String == "Nothing is live")
            await r.target.setFail(.unavailable)
            #expect(await http(r.port, "POST", "/api/v1/transport", token: t, json: ["command": "next"]).status == 503)
        }
    }

    @Test func concurrentCommandsAreAppliedInArrivalOrderWithoutInterleaving() async throws {
        let target = FakeTarget()
        await target.setDelay(25)
        try await withServer(target: target) { r in
            let t = await pairClient(r)
            // Ten clients, each on its own connection, sending in a known order with a gap that is longer than parsing takes.
            let order: [(String, [String: Any])] = [
                ("Next slide", ["command": "next"]), ("Previous slide", ["command": "previous"]), ("Go to slide 3", ["command": "goToSlide", "index": 2]),
                ("Clear", ["command": "clear"]), ("Stop", ["command": "stop"]), ("Blackout on", ["command": "blackout", "mode": "on"]),
                ("Blackout off", ["command": "blackout", "mode": "off"]), ("Clear all", ["command": "clearAll"]),
                ("Next slide", ["command": "next"]), ("Previous slide", ["command": "previous"]),
            ]
            var clients: [RawClient] = []
            for (_, body) in order {
                let c = try #require(RawClient(port: r.port))
                let data = try JSONSerialization.data(withJSONObject: body)
                c.send(rawRequestBytes(method: "POST", path: "/api/v1/transport", host: "127.0.0.1:\(r.port)",
                                       headers: [("Authorization", "Bearer \(t)"), ("Content-Type", "application/json")], body: data))
                clients.append(c)
                try await Task.sleep(nanoseconds: 40_000_000)
            }
            for c in clients {
                await blocking { c.read(timeout: 5) { $0.range(of: Data("\r\n\r\n".utf8)) != nil && String(decoding: $0, as: UTF8.self).contains("\"state\"") } }
                #expect(parseRaw(c.received).status == 200)
            }
            let log = await target.log
            let expected = order.flatMap { ["begin \($0.0)", "end \($0.0)"] }
            #expect(log == expected)
        }
    }

    @Test func manyClientsAtOnceNeverInterleave() async throws {
        let target = FakeTarget()
        await target.setDelay(5)
        try await withServer(configure: { $0.maxConnections = 64 }, target: target) { r in
            let t = await pairClient(r)
            let port = r.port
            await withTaskGroup(of: Int.self) { g in
                for i in 0..<30 {
                    g.addTask { await http(port, "POST", "/api/v1/transport", token: t, json: i % 2 == 0 ? ["command": "next"] : ["command": "previous"]).status }
                }
                var ok = 0
                for await s in g where s == 200 { ok += 1 }
                #expect(ok == 30)
            }
            let log = await target.log
            #expect(log.count == 60)
            for i in stride(from: 0, to: log.count, by: 2) {
                #expect(log[i].hasPrefix("begin "))
                #expect(log[i + 1] == "end " + log[i].dropFirst(6), "no other command started between begin and end")
            }
        }
    }
}

@Suite struct RemoteServerEventTests {
    @Test func streamSendsTheStateThenChangesAndHeartbeats() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let c = try #require(RawClient(port: r.port))
            c.send(rawRequestBytes(method: "GET", path: "/api/v1/events", host: "127.0.0.1:\(r.port)", headers: [("Authorization", "Bearer \(t)")]))
            let first = await blocking { c.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("event: state") } }
            let head = parseRaw(first)
            #expect(head.status == 200)
            #expect(head.headers["content-type"]?.hasPrefix("text/event-stream") == true)
            #expect(head.headers["cache-control"] == "no-store")
            #expect(String(decoding: first, as: UTF8.self).contains("Slide 1"))
            // A change made by the app is pushed when the app says so.
            var s = await r.target.state
            s.live = RemoteSlideText(primary: "Changed <b>by app</b>")
            await r.target.setState(s)
            r.server.stateDidChange()
            let after = await blocking { c.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("Changed") } }
            #expect(String(decoding: after, as: UTF8.self).contains("Changed"))
            // A heartbeat arrives while nothing changes.
            let beat = await blocking { c.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains(": heartbeat") } }
            #expect(String(decoding: beat, as: UTF8.self).contains(": heartbeat"))
            // A command from another client is pushed to this one.
            _ = await http(r.port, "POST", "/api/v1/transport", token: t, json: ["command": "blackout", "mode": "on"])
            let black = await blocking { c.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("blackedOut") } }
            #expect(String(decoding: black, as: UTF8.self).contains("blackedOut"))
        }
    }

    @Test func unchangedStateIsNotRepeated() async throws {
        try await withServer(configure: { $0.heartbeatInterval = 30 }) { r in
            let t = await pairClient(r)
            let c = try #require(RawClient(port: r.port))
            c.send(rawRequestBytes(method: "GET", path: "/api/v1/events", host: "127.0.0.1:\(r.port)", headers: [("Authorization", "Bearer \(t)")]))
            await blocking { c.read(timeout: 3) { String(decoding: $0, as: UTF8.self).contains("event: state") } }
            r.server.stateDidChange()
            r.server.stateDidChange()
            let all = await blocking { c.read(timeout: 0.7) { _ in false } }
            let count = String(decoding: all, as: UTF8.self).components(separatedBy: "event: state").count - 1
            #expect(count == 1)
        }
    }
}

@Suite struct RemoteServerHardeningTests {
    @Test func oversizedBodyIs413AndNeverParsed() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let big = Data(repeating: 0x61, count: 70_000)
            let res = await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "application/json")], body: big)
            #expect(res.status == 413)
            // Declared size alone is enough; the server does not wait for the body.
            let bytes = Data("POST /api/v1/transport HTTP/1.1\r\nHost: 127.0.0.1:\(r.port)\r\nAuthorization: Bearer \(t)\r\nContent-Type: application/json\r\nContent-Length: 1000000\r\n\r\n".utf8)
            let res2: RawResponse = await blocking {
                guard let c = RawClient(port: r.port) else { return RawResponse(raw: Data(), status: 0, headers: [:], body: Data()) }
                c.send(bytes); c.read(timeout: 3)
                return parseRaw(c.received)
            }
            #expect(res2.status == 413)
            #expect(await r.target.log.isEmpty)
        }
    }

    @Test func bodyAtTheLimitIsReadButStillNeedsToBeValid() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let res = await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Content-Type", "application/json")], body: Data(repeating: 0x20, count: 65_536))
            #expect(res.status == 400)
        }
    }

    @Test func malformedRequestsGetErrorsAndNeverReachTheTarget() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let host = "127.0.0.1:\(r.port)"
            let cases: [(String, Int)] = [
                ("GET /api/v1/state HTTP/1.1\r\nHost: \(host)\r\nAuthorization: Bearer \(t)\r\nHost: \(host)\r\n\r\n", 400),
                ("POST /api/v1/transport HTTP/1.1\r\nHost: \(host)\r\nAuthorization: Bearer \(t)\r\nContent-Type: application/json\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", 501),
                ("POST /api/v1/transport HTTP/1.1\r\nHost: \(host)\r\nAuthorization: Bearer \(t)\r\nContent-Type: application/json\r\nContent-Length: 4\r\nContent-Length: 4\r\n\r\nnext", 400),
                ("GET /api/v1/state HTTP/1.0\r\nHost: \(host)\r\nAuthorization: Bearer \(t)\r\n\r\n", 505),
                ("GET /api/v1/state HTTP/1.1\nHost: \(host)\n\n", 400),
                ("GARBAGE\r\n\r\n", 400),
            ]
            for (raw, want) in cases {
                let res: RawResponse = await blocking {
                    guard let c = RawClient(port: r.port) else { return RawResponse(raw: Data(), status: 0, headers: [:], body: Data()) }
                    c.send(Data(raw.utf8)); c.read(timeout: 3)
                    return parseRaw(c.received)
                }
                #expect(res.status == want, "\(raw.debugDescription) -> \(res.status)")
            }
            #expect(await r.target.log.isEmpty)
        }
    }

    @Test func smuggledSecondRequestInTheSameBytesIsRefused() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let body = "{\"command\":\"next\"}"
            let first = "POST /api/v1/transport HTTP/1.1\r\nHost: 127.0.0.1:\(r.port)\r\nAuthorization: Bearer \(t)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            let second = "POST /api/v1/transport HTTP/1.1\r\nHost: 127.0.0.1:\(r.port)\r\nAuthorization: Bearer \(t)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            let res: RawResponse = await blocking {
                guard let c = RawClient(port: r.port) else { return RawResponse(raw: Data(), status: 0, headers: [:], body: Data()) }
                c.send(Data((first + second).utf8)); c.read(timeout: 3)
                return parseRaw(c.received)
            }
            #expect(res.status == 400)
            #expect(await r.target.log.isEmpty, "neither request ran")
        }
    }

    @Test func routingErrors() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            #expect(await http(r.port, "GET", "/api/v1/nothing", token: t).status == 404)
            #expect(await http(r.port, "GET", "/api/state", token: t).status == 404, "only /api/v1 exists")
            #expect(await http(r.port, "GET", "/nothing").status == 404)
            #expect(await http(r.port, "GET", "/favicon.ico").status == 404)
            #expect(await http(r.port, "POST", "/api/v1/state", token: t, json: [:]).status == 405)
            #expect(await http(r.port, "GET", "/api/v1/transport", token: t).status == 405)
            #expect(await http(r.port, "DELETE", "/api/v1/state", token: t).status == 405)
            #expect(await http(r.port, "POST", "/", json: [:]).status == 405)
            let opt = await http(r.port, "OPTIONS", "/api/v1/state", headers: [("Origin", "http://evil.example.com"), ("Access-Control-Request-Method", "GET")])
            #expect(opt.headers.keys.allSatisfy { !$0.hasPrefix("access-control-") })
        }
    }

    @Test func wrongHostHeaderIsRefusedEverywhere() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            for host in ["evil.example.com", "evil.example.com:\(r.port)", "localhost.evil.com", "127.0.0.1:1", "8.8.8.8"] {
                for (m, p) in [("GET", "/"), ("GET", "/api/v1/state"), ("POST", "/api/v1/pair"), ("GET", "/api/v1/events")] {
                    let res = await http(r.port, m, p, token: t, host: host, json: m == "POST" ? ["code": r.server.currentPairingCode, "label": "x"] : nil)
                    #expect(res.status == 403, "\(host) \(m) \(p) -> \(res.status)")
                }
            }
            #expect(r.server.listTokens().count == 1, "a rebinding page cannot pair")
            // Names that are ours work.
            #expect(await http(r.port, "GET", "/api/v1/state", token: t, host: "localhost:\(r.port)").status == 200)
            #expect(await http(r.port, "GET", "/api/v1/state", token: t, host: "127.0.0.1:\(r.port)").status == 200)
        }
    }

    @Test func crossSiteOriginsAreRefusedAndNoCorsHeadersAreEverSent() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            let evil = await http(r.port, "POST", "/api/v1/transport", token: t, headers: [("Origin", "http://evil.example.com")], json: ["command": "next"])
            #expect(evil.status == 403)
            #expect(await r.target.log.isEmpty)
            let same = await http(r.port, "GET", "/api/v1/state", token: t, headers: [("Origin", "http://127.0.0.1:\(r.port)")])
            #expect(same.status == 200)
            for res in [evil, same, await http(r.port, "GET", "/"), await http(r.port, "GET", "/api/v1/state"), await http(r.port, "GET", "/nothing")] {
                #expect(res.headers.keys.allSatisfy { !$0.hasPrefix("access-control-") })
            }
        }
    }

    @Test func apiResponsesAreNeverCached() async throws {
        try await withServer { r in
            let t = await pairClient(r)
            for res in [await http(r.port, "GET", "/api/v1/state", token: t), await http(r.port, "GET", "/api/v1/state"),
                        await http(r.port, "GET", "/api/v1/nothing", token: t), await http(r.port, "POST", "/api/v1/pair", json: ["code": "000000", "label": "x"])] {
                #expect(res.headers["cache-control"] == "no-store")
                #expect(res.headers["x-content-type-options"] == "nosniff")
            }
        }
    }

    @Test func aClientThatSendsNothingIsDropped() async throws {
        try await withServer(configure: { $0.requestTimeout = 0.5 }) { r in
            let c = try #require(RawClient(port: r.port))
            // The server's own 0.5 s deadline must close the connection. The read waits up to 10 s so a busy
            // machine cannot fail this on wall-clock time: the proof is that the server closed it, not how fast.
            let closed = await blocking { c.read(timeout: 10) { _ in false }; return c.closed }
            #expect(closed)
        }
    }

    @Test func aSlowRequestThatNeverFinishesIsDropped() async throws {
        try await withServer(configure: { $0.requestTimeout = 0.6 }) { r in
            let c = try #require(RawClient(port: r.port))
            c.send(Data("GET /api/v1/state HTTP/1.1\r\nHost: 127.0.0.1:\(r.port)\r\n".utf8))
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 300_000_000)
                c.send(Data("X-Drip: 1\r\n".utf8))     // trickling does not extend the deadline
            }
            let closed = await blocking { c.read(timeout: 10) { _ in false }; return c.closed }
            #expect(closed)
        }
    }

    @Test func aTargetThatNeverAnswersGets504AndTheServerStaysUp() async throws {
        let target = FakeTarget()
        await target.setDelay(1500)
        try await withServer(configure: { $0.handlerTimeout = 0.4 }, target: target) { r in
            let t = await pairClient(r)
            let slow = await http(r.port, "POST", "/api/v1/transport", token: t, json: ["command": "next"])
            #expect(slow.status == 504)
            #expect(await http(r.port, "GET", "/").status == 200, "unrelated requests are still answered")
            #expect(await http(r.port, "GET", "/api/v1/state").status == 401)
        }
    }

    @Test func connectionsAreCapped() async throws {
        try await withServer(configure: { $0.maxConnections = 4; $0.requestTimeout = 5 }) { r in
            var idle: [RawClient] = []
            for _ in 0..<4 { idle.append(try #require(RawClient(port: r.port))) }
            try await Task.sleep(nanoseconds: 200_000_000)
            let extra = try #require(RawClient(port: r.port))
            let dropped = await blocking { extra.read(timeout: 2) { _ in false }; return extra.closed }
            #expect(dropped, "the fifth connection is refused")
            idle.removeFirst().close()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(await http(r.port, "GET", "/").status == 200, "a freed slot can be used again")
            _ = idle
        }
    }

    @Test func twoHundredSequentialRequestsLeaveNoConnectionsBehind() async throws {
        try await withServer(configure: { $0.maxConnections = 8 }) { r in
            let t = await pairClient(r)
            var ok = 0
            for i in 0..<200 {
                let res = i % 2 == 0 ? await http(r.port, "GET", "/api/v1/state", token: t) : await http(r.port, "GET", "/api/v1/state")
                if res.status == (i % 2 == 0 ? 200 : 401) { ok += 1 }
            }
            #expect(ok == 200)
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(r.server.openConnectionCount == 0)
        }
    }
}
