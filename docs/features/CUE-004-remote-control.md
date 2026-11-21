# CUE-004: remote control server (HTTP on the local network), off by default

Catalogue: AUTO-10 remote API, AUTO-13 web-based control; NFR-09 (refuses unauthenticated requests, off by default). Phase 3.

Verification level: Implemented; Unit Tested (against a real loopback socket). Not Simulated in the app, not Hardware Verified, not Live-Service Verified: the app does not use it yet, and no phone or second device has connected to it.

Code: `Packages/WorshipFlowKit/Sources/RemoteControl` (Foundation, Network.framework, CryptoKit, `CueEngine`, `Domain`; no third-party code). Tests: `Tests/RemoteControlTests`. There is no interface and no app wiring in this slice: the app later implements `RemoteControlTarget` and shows the pairing code and the paired devices.

## What the app provides and gets

- `RemoteControlTarget` (the app implements it; every call may hop to the main actor): `perform(_ CueTransport)`, `runMacro(id:)`, `snapshot() -> RemoteState`. The server calls it one request at a time, in the order requests arrived.
- `RemoteState`: mode (`live`, `stopped`, `cleared`, `blackedOut`), live and next slide text (primary and secondary language), position ("3 of 9"), presentation title, playlist titles with the live one marked, timers with display values, macros by id and name.
- `RemoteServer(target:tokens:configuration:clock:)`: `start()` returns the port, `stop()` releases it; `currentPairingCode`, `pairingCodeExpiresAt`; `listTokens()` (label, created, last used), `revoke(id:)`, `revokeAll()`; `stateDidChange()` (the app calls it when the show changed from the operator side; phones get the new state); `setEventHandler` (started, stopped, paired, pairing rejected, lockout, revoked, refused peer; never a token or a code).
- `TokenStore` (in-memory implementation `InMemoryTokenStore`): the server hands it `StoredToken` records (id, label, salt, SHA-256 hash, created, last used). The app may persist them; they hold no usable secret.
- `RemoteServerConfiguration`: port (0 = any free port), `loopbackOnly`, connection cap (16), request timeout (10 s), handler timeout (15 s), heartbeat (15 s), body limit (64 KB), header limit (8 KB), pairing limits, device cap (32), extra allowed host names.

## Endpoints

All JSON unless noted. Everything under `/api/v1/` except `pair` needs `Authorization: Bearer <token>`; without it the answer is 401 with an empty body. Only `/api/v1/` exists; `/api/...` without the version is a 404 for an authenticated client.

| Method and path | Meaning | Answers |
|---|---|---|
| `GET /` | The control page (one HTML document, no external assets). No token needed; it contains no show data. | 200 |
| `POST /api/v1/pair` | Body `{"code":"123456","label":"Pastor's phone"}` (`Content-Type: application/json`). Returns `{"token":"...","tokenID":"..."}`. | 200; 400 bad body; 403 wrong or expired code; 409 too many devices; 429 locked out (with `Retry-After`) |
| `GET /api/v1/state` | The `RemoteState` snapshot. | 200 |
| `POST /api/v1/transport` | `{"command":"next"}`, `previous`, `clear`, `clearAll`, `stop`, `{"command":"goToSlide","index":3}` (zero-based, 0 to 100000), `{"command":"blackout","mode":"on"|"off"|"toggle"}`. Unknown fields are refused. Answers `{"state": ...}`, the state after the command. | 200; 400; 409 the target refused (with its short reason); 503 not available |
| `POST /api/v1/macros/{id}/run` | Runs a macro by id (a UUID). Answers `{"state": ...}`. | 200; 404 unknown macro |
| `GET /api/v1/events` | Server-Sent Events: the state at once, then again after every change; `: heartbeat` comment every 15 s. | 200 stream |

Other answers: 403 wrong Host or cross-site Origin, 404 unknown route, 405 wrong method (with `Allow`), 413 body over 64 KB, 414/431 request line or headers too long, 415 not `application/json`, 417 `Expect`, 501 any `Transfer-Encoding` (chunked bodies are not implemented, so they are refused), 503 busy, 504 the app did not answer in time, 505 not HTTP/1.1. Every response closes the connection (one request per connection).

## Pairing, in plain words

1. The operator starts the server in the app. The app shows `currentPairingCode`, six digits, which changes every two minutes and after every successful pairing.
2. On the phone, open `http://<the Mac's address or name>:<port>/`, type the code and a name for the phone, press Pair.
3. The server answers with a long random token. The phone keeps it (the page uses `localStorage`) and sends it as a bearer token. The server keeps only a salted SHA-256 hash, so the token cannot be read back from the store.
4. The operator sees the paired devices (label, last used) and can revoke one or all. A revoked token fails on its next request and its event stream is closed.
5. Guessing: five wrong codes from one address in a minute lock that address out for a minute (even the right code is refused meanwhile); ten wrong guesses from anywhere against one code replace the code.

## Security notes

- **Off until started.** Nothing listens before `start()`. Tests listen only on `127.0.0.1` on an ephemeral port and stop the server at the end of each test.
- **Local network only.** The listener accepts peers whose address is loopback, private IPv4 (10/8, 172.16/12, 192.168/16), link-local, or IPv6 loopback, link-local or unique-local; anything else is closed at once. This is a defence in depth: it is not a firewall and the Mac's own firewall setting still applies.
- **Host and Origin.** A request whose `Host` is not this Mac's own address or name (localhost, the host name, its `.local` form, extra configured names) with the right port is refused: this stops DNS rebinding. A request with an `Origin` that is not this server is refused. No `Access-Control-*` header is ever sent and `OPTIONS` is a plain 405, so another website cannot call the API from a browser.
- **Strict HTTP.** Only HTTP/1.1; the request line and headers are parsed byte by byte: no bare line feeds, no folded headers, no duplicate headers of any kind, a single numeric `Content-Length`, no `Transfer-Encoding`, no `Expect`, ASCII only. Bytes after the declared body are refused, and every connection closes after its answer, so a second request cannot ride behind the first.
- **Bounded.** Header 8 KB, body 64 KB, 64 header lines, 16 connections, 10 s for a whole request (trickling does not extend it), 15 s for the app to answer, at most 32 unsent event writes per stream.
- **Tokens and codes** come from `SecRandomCopyBytes`; a failure of the random source means nobody can pair (it fails closed). A token is 256 random bits; it is compared in constant time and stored only as `SHA-256(salt + secret)` with a per-token salt. Nothing is logged; the event handler never receives a token or a code.
- **Commands** from all phones go through one queue: one at a time, in arrival order, each answered with the state after it.
- **The control page** sets every piece of show text with `textContent`, never as markup. Its Content-Security-Policy allows only its own inline script and style (by hash), connections to its own origin, no frames, no base URI. It sends `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `nosniff`.

### Known limitation: plain HTTP

This slice speaks plain HTTP on the church network. Anyone who can see the traffic on the same Wi-Fi (a joined device, a compromised access point) can read the state and any token or pairing code in flight, and can reuse a captured token until the operator revokes it. Pairing codes are short-lived and single-use, so a code seen after use is worthless; a token is not. What such an attacker cannot do without a token: send a command, read the state, or pair (the pairing code must be read off the Mac's screen, and guessing is limited). What an attacker on the same network can always do: connect and fail (connection cap and per-address pairing lockout limit the damage), and refuse service. A guest on the same Wi-Fi therefore must be kept off it: use a separate network for guests. TLS (a self-signed certificate pinned at pairing, or a local CA) is future work and should be an ADR before it is built.

### macOS prompts

A real app that listens may trigger the macOS local-network or firewall prompt the first time. This is expected; nothing here tries to suppress it and `project.yml` is not changed in this slice. Whether the sandbox entitlements need an incoming-connection entry is for the wiring slice to decide.

## Not done in this slice

No interface and no app wiring; no TLS; no WebSocket (Server-Sent Events carry the push, see the report); no persistence of tokens beyond the `TokenStore` protocol; no Bonjour announcement; no per-token permissions (every paired phone may do everything the API offers); timers and macros are shown but timers cannot be started from the page.
