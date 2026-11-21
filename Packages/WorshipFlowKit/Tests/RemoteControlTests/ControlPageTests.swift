// CUE-004: the one self-contained page for a phone. No external loads, no HTML built from text, a CSP that pins the inline code.
import Testing
import Foundation
import CryptoKit
@testable import RemoteControl

@Suite struct ControlPageTests {
    @Test func pageIsServedWithoutATokenAndCarriesNoState() async throws {
        try await withServer { r in
            var s = await r.target.state
            s.live = RemoteSlideText(primary: "SECRET-LIVE-TEXT")
            await r.target.setState(s)
            let res = await http(r.port, "GET", "/")
            #expect(res.status == 200)
            #expect(res.headers["content-type"]?.hasPrefix("text/html") == true)
            #expect(!res.bodyText.contains("SECRET-LIVE-TEXT"))
            #expect(res.bodyText == ControlPage.html)
            #expect(res.headers["cache-control"] == "no-store")
            #expect(res.headers["x-frame-options"] == "DENY")
            #expect(res.headers["referrer-policy"] == "no-referrer")
        }
    }

    @Test func pageLoadsNothingFromOutside() {
        let html = ControlPage.html
        for forbidden in ["http:", "https:", "//", "<link", " src=", "href=", "@import", "url(", "<iframe", "<img", "xmlhttp", "style=\"", "WebSocket", "EventSource"] {
            #expect(!html.contains(forbidden), "page contains \(forbidden)")
        }
        #expect(html.contains("<title>"))
        #expect(html.contains("name=\"viewport\""))
        #expect(html.contains("lang=\"en\""))
    }

    @Test func pageNeverBuildsMarkupFromText() {
        let html = ControlPage.html
        for forbidden in ["innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval(", "new Function", "setTimeout(\"", "setInterval(\"", "javascript:", "onclick=", "onload=", "onerror="] {
            #expect(!html.contains(forbidden), "page contains \(forbidden)")
        }
        #expect(html.contains("textContent"))
    }

    @Test func cspPinsTheInlineScriptAndStyleAndForbidsEverythingElse() async throws {
        try await withServer { r in
            let res = await http(r.port, "GET", "/")
            let csp = try #require(res.headers["content-security-policy"])
            func hash(_ s: String) -> String { "'sha256-" + Data(SHA256.hash(data: Data(s.utf8))).base64EncodedString() + "'" }
            #expect(csp.contains("script-src \(hash(ControlPage.script))"))
            #expect(csp.contains("style-src \(hash(ControlPage.style))"))
            #expect(csp.contains("default-src 'none'"))
            #expect(csp.contains("connect-src 'self'"))
            #expect(csp.contains("frame-ancestors 'none'"))
            #expect(csp.contains("base-uri 'none'"))
            #expect(!csp.contains("unsafe-inline"))
            #expect(!csp.contains("unsafe-eval"))
            // The hashed text is exactly what is between the tags.
            let html = res.bodyText
            #expect(html.contains("<script>" + ControlPage.script + "</script>"))
            #expect(html.contains("<style>" + ControlPage.style + "</style>"))
        }
    }

    @Test func slideTextWithMarkupTravelsAsDataNotMarkup() async throws {
        try await withServer { r in
            var s = await r.target.state
            s.live = RemoteSlideText(primary: "<script>alert(1)</script>", secondary: "\"><img src=x onerror=alert(2)>")
            s.playlist = [RemotePlaylistItem(title: "</title><script>x()</script>", isLive: true)]
            await r.target.setState(s)
            let t = await pairClient(r)
            let res = await http(r.port, "GET", "/api/v1/state", token: t)
            #expect(res.headers["content-type"]?.hasPrefix("application/json") == true)
            #expect(res.headers["x-content-type-options"] == "nosniff")
            let live = res.json?["live"] as? [String: Any]
            #expect(live?["primary"] as? String == "<script>alert(1)</script>", "round-trips as a plain string")
            // And the page that shows it is static: the markup text is not in it, and it renders only through textContent.
            let page = await http(r.port, "GET", "/")
            #expect(!page.bodyText.contains("alert(1)"))
        }
    }

    @Test func pageSpeaksTheApiItActuallyHas() {
        let js = ControlPage.script
        for path in ["/api/v1/pair", "/api/v1/events", "/api/v1/transport", "/api/v1/macros/"] { #expect(js.contains(path), "\(path)") }
        for cmd in ["next", "previous", "clear", "blackout"] { #expect(js.contains("'\(cmd)'"), "\(cmd)") }
        #expect(ControlPage.html.contains("aria-live"))
    }
}
