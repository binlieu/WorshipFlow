# CUE-004 report: remote control server (AUTO-10, AUTO-13)

Status: Implemented; Unit Tested against a real loopback socket. Not Simulated in the app, not Hardware Verified, not Live-Service Verified. No phone or second device has connected to it.

## Files

Created (all inside the allowed paths; nothing else touched; no git state changed):

- `Packages/WorshipFlowKit/Sources/RemoteControl/RemoteState.swift` (state, target protocol, events, configuration)
- `.../RemoteControl/Secrets.swift` (secure random, constant-time compare, token store and authority, pairing manager)
- `.../RemoteControl/HTTP.swift` (strict request reader, response writer)
- `.../RemoteControl/NetworkPolicy.swift` (Host and Origin policy, local-network peer check)
- `.../RemoteControl/CommandPump.swift` (the one-at-a-time, in-order queue)
- `.../RemoteControl/ServerConnection.swift` (one client connection)
- `.../RemoteControl/RemoteServer.swift` (listener, routing, pairing, events)
- `.../RemoteControl/ControlPage.swift` (the phone page, CSP)
- `Packages/WorshipFlowKit/Tests/RemoteControlTests/` `TestSupport.swift`, `HTTPParserTests.swift`, `SecretsTests.swift`, `NetworkPolicyTests.swift`, `RemoteServerTests.swift`, `ControlPageTests.swift`
- `docs/features/CUE-004-remote-control.md`, this report.
- Deleted: the two `Placeholder.swift` files.

## Test-first record

Tests were written before any implementation. First build of the test target, with no implementation: `swift build --build-tests` failed with 171 errors, 134 of them "cannot find ... in scope" (`HTTPRequestParser`, `TokenAuthority`, `PairingManager`, `PeerAddress`, `SecureRandom`, `RemoteServer`...), i.e. the missing API, which is the right reason for a not-yet-built feature. After implementation the first full run was 74 of 76 pass; the two failures were real: `HostPolicy` accepted the shortened IPv4 forms `0x7f.1` and `2130706433` (Network's address parser takes them). Fixed by accepting only plain dotted decimal. A 504 test was added afterwards (77 total).

## Commands and exit status

- `swift test --filter RemoteControlTests` in `Packages/WorshipFlowKit` (the real package): exit 0, "Test run with 77 tests in 12 suites passed after 1.020 seconds". Repeated 6 times before the last test was added, 6 of 6 passed (about 1.0 s each). No listener was left behind after the runs (`lsof` showed none from the test process).
- Full package run `swift test --package-path Packages/WorshipFlowKit`: exit 0, "Test run with 1935 tests in 292 suites passed after 62.498 seconds" (1815 before, plus the 77 here, plus the other agent's tests present at that moment).
- `./scripts/check.sh` was not run (it generates the Xcode project and builds the app, which another agent and the owner's interface work may be touching); only the package tests were run.

## Decisions where the brief left room

- **Push channel: Server-Sent Events, not WebSocket.** The channel is one way (server to phone); commands already have their own POST endpoints with acknowledgements. SSE is plain HTTP, so it goes through the same strict parser, Host and Origin checks, bearer check and connection cap, with no upgrade handshake, no frame masking and no frame parser (a second hostile-input parser that WebSocket would add). The browser `EventSource` cannot send an `Authorization` header (the token would have to go in the URL, where it gets logged and cached), so the page reads the stream with `fetch` and a stream reader, which can; it reconnects with back-off and gives up pairing on 401. Cost: a client other than a browser has to parse `text/event-stream` (a few lines).
- **One request per connection, `Connection: close` always.** It removes request smuggling by pipelining or reuse. Cost: a new TCP connection per request on the LAN, which is cheap.
- **Only `/api/v1/...`.** The brief lists unversioned names and also says to version; the unversioned paths are 404.
- **Unauthenticated surface:** only `GET /` (static page, no show data), `POST /api/v1/pair` (rate limited) and error answers. Authentication is checked before routing, so an unknown client gets the same empty 401 for a real or a made-up route.
- **State reads go through the same queue as commands** (the target may hop to the main actor; one writer at a time is simpler to reason about and keeps pushes in order).
- **Change notification is by call:** the app calls `stateDidChange()`; the server also refreshes after each command, and only pushes when the snapshot differs from the last one pushed.
- **Pairing:** a code is replaced after two minutes, after one success, and after ten wrong guesses from anywhere. A correct code during a lockout is refused. A bad label is refused before the code is checked, so a typo does not burn a good code.
- **Token format** `<uuid>.<43 chars>`: the uuid selects the record (one hash per request, not one per paired device), the secret is the 256 random bits. Hash is `SHA-256(salt || secret)`. An unknown id still computes a hash so timing does not reveal which ids exist.
- **Device cap 32; blackout accepts `toggle` as well as `on` and `off`** (it exists in `CueBlackout`); `goToSlide` is zero-based like `CueTransport`.
- **Error mapping:** target `rejected(reason)` becomes 409 with the reason (cut to 200 characters), `unavailable` 503, `unknownMacro` 404; anything else 500 with no detail.
- **Control page:** static HTML held as a Swift string, text only through `textContent`, CSP with the script and style pinned by SHA-256 computed from the same strings, so nothing else can run even if an escape were missed. The token is kept in `localStorage` (so the phone stays paired; revocation is on the Mac).
- Added beyond the brief: local-network-only peer filter, Origin check, handler timeout (504), per-stream write bound, device cap, global guess limit per code.

## Security self-review

| Point | Where enforced | Test that proves it |
|---|---|---|
| Off until started; port released | `RemoteServer.beginStart/beginStop`; nothing is created in `init` | `offUntilStartedAndStopReleasesThePort`, `startingTwiceFailsAndRestartWorksOnTheSamePort`, `stopClosesOpenEventStreams` |
| Refuses every unauthenticated request | `RemoteServer.handle`: bearer check before routing for everything under `/api/` except `pair` | `everyApiEndpointRefusesWithoutATokenAndGivesNoDetail` (every endpoint, wrong method, unknown route, bad tokens; empty body; target never called) |
| Bounded reads | `HTTPLimits` in `HTTPRequestParser.parseHead` (8 KB head, 64 headers, 2 KB target, 64 KB body from the declared length); `ServerConnection` buffers nothing beyond the declared body | `oversizeHeadersAreRefused`, `oversizeBodyIsDecidedFromTheHeader`, `oversizedBodyIs413AndNeverParsed`, `bodyAtTheLimitIsReadButStillNeedsToBeValid` |
| Timeouts, slowloris | `ServerConnection.start` request deadline from accept (trickling does not extend it); handler deadline | `aClientThatSendsNothingIsDropped`, `aSlowRequestThatNeverFinishesIsDropped`, `aTargetThatNeverAnswersGets504AndTheServerStaysUp` |
| Connection cap | `RemoteServer.accept` | `connectionsAreCapped` (fifth refused, slot reusable) |
| No leaked connections | `ServerConnection.finish` removes it from the runtime | `twoHundredSequentialRequestsLeaveNoConnectionsBehind` (count 0) |
| Strict request line and headers | `HTTPRequestParser`: single spaces, upper-case token method, origin-form target, HTTP/1.1 only, ASCII only, CRLF only, no folding, no duplicate headers, Host once | `rejectsMalformedRequests` (24 cases), `rejectsControlBytesAndNul`, `otherHTTPVersionsAreRefused`, `malformedRequestsGetErrorsAndNeverReachTheTarget` |
| No request smuggling | duplicate or odd `Content-Length` refused; any `Transfer-Encoding` refused (501), including with `Content-Length`; bytes after the body refused; one request per connection | `transferEncodingIsNotImplementedAndRefused`, `smuggledSecondRequestInTheSameBytesIsRefused`, malformed cases above |
| Constant-time comparison | `constantTimeEqual` (tokens and pairing code); dummy hash for unknown ids | `constantTimeEqualWorks` (behaviour only; see not verified) |
| Secure random for tokens and codes | `SecureRandom.bytes` (`SecRandomCopyBytes`), `sixDigits` by rejection sampling; failure fails closed | `tokensAreLongAndUnique`, `codeIsSixDigits`, `failsClosedWhenRandomIsUnavailable`, `failsClosedWithoutRandom` |
| Tokens stored only as salted hashes | `TokenAuthority.issue` stores `StoredToken` (salt and hash, no secret) | `theStoreHoldsOnlyASaltedHashNeverTheToken` |
| Tokens and codes never logged | The server writes no log; `RemoteServerEvent` has no secret field | `pairingGivesATokenThatWorks` (event dump contains neither token nor code) |
| Pairing limits | `PairingManager.attempt` | `fiveWrongCodesLockTheAddressOut`, `lockoutEndsAfterTheCoolDown`, `tooManyGuessesFromAnywhereReplaceTheCode`, `lockoutAndRecovery`, `wrongAndExpiredCodesAreRefused`, `successRotatesTheCode`, `codeRotatesEveryTwoMinutes` |
| Revoke takes effect and closes the stream | `TokenAuthority.revoke`; `RemoteServer.revoke` closes that token's streams; heartbeat re-checks tokens | `revokeTakesEffectOnTheNextRequestAndClosesThatClientsStream` |
| Host header (DNS rebinding) | `HostPolicy.isAllowedHost` in `handle`, before any route | `refusesEverythingElse` (21 hosts), `allowsOwnNamesAndAddresses`, `wrongHostHeaderIsRefusedEverywhere` (page, API, pair, events) |
| No permissive CORS; cross-site calls | no `Access-Control-*` header anywhere; `HostPolicy.isAllowedOrigin`; JSON `Content-Type` required for POST | `crossSiteOriginsAreRefusedAndNoCorsHeadersAreEverSent`, `routingErrors` (OPTIONS) |
| `Cache-Control: no-store`, nosniff | `HTTPResponse.serialized` | `apiResponsesAreNeverCached` |
| Local network only | `PeerAddress.isLocalNetwork` in `accept` | `PeerAddressTests` (unit only; see not verified) |
| Commands one at a time in arrival order | `CommandPump` (synchronous submit into an `AsyncStream`, one consumer) | `runsJobsOneAtATimeInSubmissionOrder`, `concurrentCommandsAreAppliedInArrivalOrderWithoutInterleaving`, `manyClientsAtOnceNeverInterleave` |
| Each command reaches the target once | `authenticated` routing | `stateAndEachTransportCommandReachTheTargetOnce`, `badTransportBodiesAreRefusedAndNeverReachTheTarget` |
| Control page: no external URL, text escaped | static page, `textContent` only, CSP by hash | `pageLoadsNothingFromOutside`, `pageNeverBuildsMarkupFromText`, `cspPinsTheInlineScriptAndStyleAndForbidsEverythingElse`, `slideTextWithMarkupTravelsAsDataNotMarkup` |

What I checked beyond tests: read the parser and router again for any path that reaches the target before authentication (none: the target is reached only through `submit`/`refresh`, called from `authenticated` and `openStream`).

## Not verified

- **No phone or second device has connected.** Nothing was tested on a real Wi-Fi network, over a non-loopback interface, or with a real browser. The page's JavaScript was never executed (no browser and no JavaScript engine in the tests); its properties are checked by inspecting its text and the CSP. It may have bugs in rendering, the stream reader or the pairing form.
- Binding to all interfaces (the app's configuration, `loopbackOnly = false`) was not exercised; the local-network peer filter, the Host check against real interface addresses and the `.local` name were tested only as pure functions or on loopback. macOS local-network and firewall prompts were not seen.
- Constant-time behaviour is by construction (no early exit), not measured.
- Not tested: a stalled event-stream reader (the 32-write bound), a slow reader of a large response, `maxPairedDevices` through the server (unit only), the connection-cap and peer-refusal events, concurrent start and stop, memory or file-descriptor use under sustained load, many streams at once, IPv6 clients.
- A hung target blocks the queue for later requests (the 504 frees only that client); the pump holds at most 256 waiting jobs and then answers 503.
- A client that fills all 16 connections can keep the remote unavailable for up to the request timeout (10 s) repeatedly; that is a denial of service for the phone, not for the show.
- Plain HTTP (see the feature doc): traffic and tokens are readable by anyone on the same network.
- `./scripts/check.sh` (project generation, app build) was not run.
