# Brief: CUE-004 — remote control server (HTTP and WebSocket on the local network), off by default

Read first: `CLAUDE.md` (local-first; security), `AGENTS.md`, `docs/MASTER-SPEC.md` rows AUTO-10 (remote API) and AUTO-13 (web-based control) and NFR-09 (refuses unauthenticated requests; off by default), `docs/features/CUE-001-cue-engine.md`, `Sources/CueEngine/CueAction.swift`, `Sources/Domain/ShowState.swift`.

Catalogue: AUTO-10, AUTO-13. Phase 3. **No interface and no app wiring in this slice**: the owner is redesigning the interface, so nothing under `App/` or `Sources/OperatorCore` may be touched. The app will later provide the "target" the server drives.

## Scope

A new target `Sources/RemoteControl` (Foundation, Network.framework, CryptoKit, `CueEngine`, `Domain`). No third-party dependency. Delete both placeholders. Test first for every decision.

## What to build

1. `RemoteControlTarget` protocol (the app implements it later; tests use a recording fake): perform a transport command (next, previous, go to slide, clear, clear all, blackout on or off, stop), run a macro by id, read a state snapshot (`RemoteState`: live or stopped or cleared or blacked out, the live and next slide text in both languages, position "3 of 9", presentation title, playlist item titles with the live one marked, timers with values, the list of macros by name). All calls are `async` and hop to the main actor on the app side.
2. `RemoteServer`: an HTTP/1.1 server on Network.framework (`NWListener`), bound to a chosen port, **off until started**, with:
   - **Pairing and tokens.** The operator sees a six-digit pairing code in the app (the server exposes `currentPairingCode`, rotating every two minutes and after each use); a client posts the code to `/api/pair` and receives a long random bearer token; tokens are stored by the caller as salted hashes (the server hands back only what must be stored: provide `TokenStore` protocol with an in-memory implementation), can be listed by label and last-used time, and revoked individually or all at once. Every other endpoint requires `Authorization: Bearer <token>`; missing or wrong → 401 with no detail. Constant-time comparison. Rate limit pairing attempts (for example five wrong codes per minute per address, then a cool-down) and report lockouts.
   - **Endpoints** (JSON): `GET /api/state`; `POST /api/transport` with a command; `POST /api/macros/{id}/run`; `GET /api/events` as a WebSocket (or Server-Sent Events if simpler and robust) pushing state changes, with a heartbeat. Versioned under `/api/v1/`. Unknown routes → 404; malformed JSON → 400 with a short reason; bodies over 64 KB → 413; slow or stalled clients time out; at most a fixed number of connections (for example 16).
   - **A small built-in control page** at `/` (one self-contained HTML document held as a Swift string: no external assets, no build step): pairing form, then current and next text, large Previous, Next, Clear, Blackout buttons, playlist list, connection status. This page is a remote for a phone on the church network, **not** the app's interface (the app's own interface stays native per `CLAUDE.md`). Keep it small and accessible; escape every piece of text it displays.
   - **Network exposure:** listens on the local network only; reject requests whose `Host` header is not the Mac's own address or name (DNS-rebinding protection); no CORS headers that would let other sites call it; `Cache-Control: no-store` on API responses; never logs tokens or pairing codes. Transport is plain HTTP on the local network in this slice: say so plainly in the feature doc as a known limitation, with what an attacker on the same Wi-Fi could and could not do, and list TLS as future work.
   - Commands are serialised: one at a time, in arrival order, each acknowledged with the resulting state.
   - Start, stop and restart are clean (the port is released; in-flight requests finish or are cancelled within a bound).
3. Tests, all against a server started on an ephemeral port on the loopback interface inside the test: unauthenticated requests refused on every endpoint; pairing success, wrong code, expired code, lockout and recovery; token revoke takes effect on the next request and closes that client's event stream; each transport command reaches the fake target once; concurrent commands from several clients are applied in order with no interleaving; state push arrives after a change; oversized body, malformed JSON, unknown route, wrong method, wrong Host header; a client that connects and sends nothing is dropped; 200 sequential requests leave no leaked connections; the control page contains no external URL and escapes a slide text containing `<script>`.
4. Docs: `docs/features/CUE-004-remote-control.md` with the endpoint list, the pairing flow in plain words, and the security notes.

## Do not modify

Anything outside `Sources/RemoteControl`, `Tests/RemoteControlTests` and the feature doc. Not `Package.swift`, `project.yml`, `App/`, `Sources/OperatorCore`, `docs/UI/`, `docs/adr/`. Another agent is working at the same time in `Sources/MIDIIO`; touch nothing there. If a full `swift test` fails solely because of its unfinished files, run your tests in a uniquely named scratch copy outside the repository (`wf-cue004-<random>`) and retry the real run before finishing.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps. The server must only ever listen during tests on the loopback interface and an ephemeral port, and must be stopped at the end of each test. Outside the sandbox no entitlement is needed for a listener; macOS may show a local-network or firewall prompt for a real app: describe this in the doc, do not try to suppress it, and do not edit `project.yml`. Do not commit or change git state. Do not consult any advisor tool. Do not download anything. Do not request full computer control.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'RemoteControlTests'` passes in the real package (or you state exactly why not and give the scratch result). Paste the summary line.
2. `AI/reports/CUE-004-report.md`: files, decisions, the security review of your own work (what you checked, what you did not), commands with exit status, and everything not verified (in particular: no phone or second device has connected to it).
