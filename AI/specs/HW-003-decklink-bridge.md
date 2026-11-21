# Brief: HW-003 — the real DeckLink bridge

Read first: `CLAUDE.md` (hardware and video-output rules, verification levels), `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md`, `docs/adr/0006-decklink-sdk-licence.md`, `AI/reports/HW-001-report.md` (especially "what a real bridge must implement"), all of `Sources/SDIEngine`, the vendored headers in `Sources/DeckLinkC/sdk/`, and — for learning the SDK 16.0 call sequences only — the manual and samples under `Vendor/DeckLinkSDK/` (`Mac/Samples/DeviceList`, `SignalGenerator`, `KeyerOutput`, `DeviceConfigure`, `ActivateProfile`, `InputLoopThrough`, and the PDF manual in the top folder). **Do not copy sample code**: write the bridge from the headers and the documented sequence (ADR-0006 decision 3). The 16.0 API differs from older tutorials (video frames and buffers changed in 14.3 and 15.x): trust the headers in `sdk/`, not memory.

Catalogue: SCRN-11, SCRN-10. **This Mac has no DeckLink card and no Desktop Video driver.** The bridge can be compiled and its "driver absent" behaviour run here; everything else is **Implemented, Not Verified** until a hardware test (a separate slice builds the test kit). Say so plainly in every status you write.

## What to build

**`Sources/DeckLinkC`** (Objective-C++; `include/DeckLinkBridge.h` is the public header and must be plain Objective-C with nullability annotations — no C++, no vendor types; replace the placeholders):
- Driver presence and API version (`CreateDeckLinkAPIInformationInstance`); `nil`/absent handled without crashing when the driver is not installed.
- Device enumeration and hot-plug (`IDeckLinkDiscovery`), per device: model and display names, persistent ID, device group and sub-device index, number of connectors as far as the API exposes it, duplex or profile state, whether it supports playback, capture, internal and external keying, and the active profile; profile activation where the API allows (for example to make connector pairs available as a fill and key pair on a Duo 2) — follow the manual's profile section; if what is needed for a Duo 2 is not determinable without hardware, implement the documented calls, expose everything as data, and record the uncertainty.
- Output: mode query (`DoesSupportVideoMode` for mode, pixel format and keying), enable, frame creation from a BGRA byte buffer the caller supplies (premultiplied, top row first; copy once into the SDK buffer, reuse frames from a small pool), `ScheduleVideoFrame`, pre-roll, `StartScheduledPlayback`, completion callback delivering the SDK's result (completed, displayed late, dropped, flushed), buffered frame count, stop, disable. External keyer enable with level; disable on stop.
- Input (needed for the loopback hardware test): enable capture on a connector with format detection, deliver frames as BGRA bytes (convert with the SDK's conversion interface if the input arrives as YUV) with the hardware timestamp, report "no signal".
- Reference counting through a small RAII holder; every COM pointer released exactly once; callbacks arrive on SDK threads and are forwarded without touching Swift actor state.
- A status snapshot for diagnostics: everything above as a dictionary of plain values.

**`Sources/DeckLinkSDI`** (Swift; replace the placeholder): `DeckLinkDeviceProvider` and types conforming to `SDIDevice` and `SDIOutputPort` from `SDIEngine`, mapping modes, keying and completion results exactly; `SDIDeviceInfo.isSimulated` false; an input port type for capture; `DeckLinkEnvironment.current` reporting driver present or absent, API version, and an operator-readable message ("Blackmagic Desktop Video is not installed on this Mac…" — DIST-06). If `SDIEngine` lacks a protocol member the bridge needs (for example input capture), do **not** edit `SDIEngine` (another agent may be using it): define what you need in `DeckLinkSDI` and list it in the report for the coordinator to fold in.

**Tests** (`Tests/DeckLinkSDITests`, replace the placeholder): everything that can run without a card — driver-absent environment returns no devices and a clear message and never crashes (this Mac is that environment; make the test skip with a recorded reason, not fail, if a driver is present); mode mapping covers every `SDIVideoMode.allKnown` both ways; completion-result mapping; keying mapping; BGRA frame packing (row order, stride padding) into a fake buffer; persistent-ID parsing. Use a seam (a small C++ or Objective-C fake behind the same wrapper interface) only where it buys a real test.

## Do not modify

Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/`, the files in `Sources/DeckLinkC/sdk/` (never edit vendor files), and anything outside `Sources/DeckLinkC`, `Sources/DeckLinkSDI`, `Tests/DeckLinkSDITests`: another agent is working in the output engine, domain, operator core and app right now. If `Package.swift` needs a setting to build (a linked framework, a flag), do not edit it: say exactly what is needed and why, and work around it if you can.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps, no exceptions crossing the Objective-C boundary. Do not commit or change git state. Do not consult any advisor tool. Do not download or install anything (in particular do not install the Desktop Video driver). Use your own uniquely named scratch directory if you need one.

## Done means

1. `swift build --package-path Packages/WorshipFlowKit --target DeckLinkSDI` succeeds with no warnings from your code, and `swift test --package-path Packages/WorshipFlowKit --filter DeckLinkSDITests` passes (if the full package cannot compile solely because of the other agent's unfinished files, run your tests in a scratch copy and say so, then retry the real run before finishing).
2. `AI/reports/HW-003-report.md` records: files, the SDK interfaces and call sequence actually used (with header names), every place where behaviour on a real Duo 2 is an assumption, what you could run here and what you could not, and a list of the questions a hardware test must answer.
