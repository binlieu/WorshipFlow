# ADR-0005: Phase 2 integration choices

Status: Accepted, 2026-11-20. Based on `AI/reports/research-2026-11-20-phase2-integrations.md`.

| # | Decision | Reason |
|---|---|---|
| 1 | **Output targets stay behind one protocol.** DeckLink, Syphon and mirrored displays are new `OutputTarget` kinds fed by the same compositor frames. | ARCH-03. |
| 2 | **DeckLink is built in two layers.** A Swift `SDIDevice` abstraction (discovery, modes, scheduled frame output, completion callbacks, keying, status) with a **simulator** implementation, and later a real Objective-C++ bridge behind the same abstraction. | The simulator lets scheduling, pre-roll, late-frame handling, pairing and failover be built and tested now. Only the bridge needs the SDK and the card. |
| 3 | **The DeckLink SDK is not downloaded by an agent.** It sits behind a registration and licence acceptance. The owner downloads it and places it in `Vendor/DeckLinkSDK/` (git-ignored until its licence block is read). | Accepting terms and creating accounts are the owner's to do. |
| 4 | **Nothing built on the simulator is called more than "Simulated".** | `CLAUDE.md`, evidence over claims. |
| 5 | **The output frame scheduler is clock-driven, not display-link-driven, for SDI.** It schedules frames against the device's own clock at the chosen mode (first target 1080p59.94), with a bounded pre-roll queue, and counts late and dropped frames from completion callbacks. | SDI has no display link; the card's clock is the reference. |
| 6 | **Fill and Key is a property of an SDI output**, not a second composition: one premultiplied BGRA frame with alpha is submitted and the device (or the simulator) derives fill and key on a connector pair. Channel consumption (two connectors) is shown to the operator. Straight versus premultiplied is a per-output setting. | Matches how the card's external keyer works per research; exact Duo 2 behaviour is unverified (UNV-02, UNV-03). |
| 7 | **Syphon is vendored from source at a pinned commit** under `Vendor/Syphon/` with its licence, built as a framework target of the Xcode project, wrapped by one small Swift class. | No Swift package exists; the tagged binary predates the Metal server. BSD-style licence permits it. |
| 8 | **Audio:** cues and music play through `AVAudioEngine`; video players route with `audioOutputDeviceUniqueID`; devices are enumerated and watched through Core Audio. One "programme audio device" setting first; per-layer routing later. | Smallest design that satisfies MEDIA-05 and MEDIA-06 without SDI. |
| 9 | **Live inputs** use AVFoundation capture devices delivered as Metal textures through the existing media-frame path, as a third media kind. The app gains a camera usage description and the camera entitlement. | Reuses the registry and compositor layers. |
| 10 | **Mirroring** is a list of extra destinations on a screen profile; every destination of one screen shows the same published scene. Each destination is routed and faulted on its own. | SCRN-05 with per-destination failover. |

## Blocked on the owner

- DeckLink SDK download into `Vendor/DeckLinkSDK/` (decision 3).
- The card, enclosure and ATEM for anything beyond "Simulated".
