# WORSHIPFLOW — Native macOS Worship Presentation Application

WORSHIPFLOW is a **native, local-first macOS application** that helps churches present worship lyrics, Scripture, sermon slides, images, videos, announcements, timers, and live-production graphics across multiple independent outputs. It supports audience/projector screens, stage confidence monitors, and broadcast/lower-third feeds. Its professional hardware roadmap includes **Blackmagic DeckLink Duo 2 through a Thunderbolt PCIe enclosure**, SDI output, and integration with HDMI-based ATEM switchers through SDI-to-HDMI converters.

**Target platform:** macOS, Apple Silicon first. **Primary stack:** Swift 6, SwiftUI, AppKit when necessary, AVFoundation, CoreMedia/CoreVideo, CoreAudio, Metal, SQLite (prefer GRDB), and Swift Package Manager. Integrate Blackmagic's **Desktop Video / DeckLink SDK** behind a native C++/Objective-C++ bridge where required.

This is **not** a Laravel application, web app, Electron shell, phone/SMS platform, or multi-tenant cloud service. Do not carry over Twilio, Telnyx, Redis, PostgreSQL, Bootstrap, PHP, or contact-center assumptions from the previous project.

## Precedence

For this repository, this `CLAUDE.md` and `docs/MASTER-SPEC.md` take precedence over project-irrelevant defaults in global `~/.claude/CLAUDE.md` or parent-folder `AGENTS.md`. Follow higher-priority platform and safety instructions regardless of repository documentation. In particular:

- **Native macOS only.** Build actual Swift/SwiftUI/AppKit screens and a native playback/output engine. Never replace core functions with HTML, a WebView, a browser UI, or a server-based rendering workaround.
- **No Codex orchestration and no Opus advisor.** Claude coordinates task-focused Claude subagents according to the model assignment below. Do not assume a nonexistent model is available.
- **SQLite for local data.** Prefer GRDB with versioned migrations. Do not introduce PostgreSQL, MySQL, MariaDB, Redis, or a cloud dependency without an approved ADR for a new requirement.
- **Local-first operation.** A worship service must remain usable without internet. Optional sync, licensing, remote control, or online media integration must not block local presentations.
- **Decide and continue.** Prefer the smallest robust, reversible solution; record meaningful decisions in an ADR, `docs/16-known-issues.md`, or the milestone report. Stop only when something cannot safely be supplied, verified, or undone: hardware procurement, unavailable signed SDKs or credentials, required paid services, legal/licensing approval, or destructive operations involving real user data.
- **Evidence over claims.** Do not claim hardware compatibility, frame-perfect synchronization, alpha-keying, video performance, or live-service readiness based only on mocks, simulated devices, or build success.

## Read before working

1. `AGENTS.md` — project startup contract and non-negotiable engineering rules.
2. `docs/14-current-status.md` and `docs/15-agent-handoff.md` — current implementation status and next steps.
3. `AI/TASK-BREAKDOWN.md` — tasks, dependencies, acceptance criteria, ownership, and model assignments.
4. `docs/adr/` — accepted architectural decisions. Do not silently reopen an ADR.
5. `docs/features/<ID>-*.md` — specification for the feature being modified.
6. `docs/MASTER-SPEC.md` — functional requirements, output behavior, and acceptance criteria.

`docs/MASTER-SPEC.md` is the feature baseline. Accepted ADRs control explicit architectural exceptions; list any conflict with the master specification in `docs/16-known-issues.md`. If these project files are absent, create minimal truthful initial versions and record the gap. **Do not fabricate existing implementations, passing tests, or approvals.**

## Product scope

Build in small, testable vertical slices. Maintain separate feature specs and IDs for these areas:

| Area | Core responsibilities |
|---|---|
| `LIB` — Library & service plans | Song/presentation libraries, searchable assets, playlists, service order, import/export, and backups |
| `SLIDE` — Presentation editor | Slides, text, images, themes, templates, slide arrangement/reflow, multilingual lyrics, formatting, and live edits |
| `MEDIA` — Media & audio | Images, video playback, motion backgrounds, looping, audio files, decoding, seeking, and media playlists |
| `OUT` — Output & composition | Independent audience/stage/broadcast screens; output profiles; per-screen themes and layers; transitions; Looks |
| `STAGE` — Stage displays | Current/next lyric, speaker notes, clock, countdown, stage messages, and confidence layouts |
| `HW` — Hardware I/O | Native Mac display outputs; DeckLink device discovery, SDI output, mode negotiation, status, and recovery |
| `KEY` — Broadcast graphics | Lower thirds, overlays, transparent backgrounds, Fill/Key workflows, and alpha handling |
| `CUE` — Show control | Slide actions, media cues, timers, macros, optional MIDI, and future external controls |
| `SYS` — App reliability | SQLite migrations, project/media packaging, autosave, recovery, diagnostics, security, and performance |

**Initial scope:** reliable library → edit → playlist → preview → live audience output, followed by stage/broadcast screen variants and the DeckLink output path. Remote control, NDI, cloud collaboration, DMX, advanced timecode, and licensed Bible/song services are separate later milestones unless required by `docs/MASTER-SPEC.md`.

## Architecture boundaries

- `App/UI` — SwiftUI operator interface; use AppKit for specialist editor surfaces, keyboard handling, window placement, full-screen output windows, and native menus where SwiftUI is insufficient.
- `Domain` — presentations, slides, cues, screen profiles, layers, playlists, and other platform-independent rules; no hardware SDK imports.
- `Persistence` — GRDB/SQLite repositories, migrations, transactions, and portable project documents.
- `MediaEngine` — AVFoundation decoding/playback, audio routing, timebase management, and playback state.
- `RenderEngine` — consistent Metal-based composition of slides, text, effects, video layers, and alpha to output frames.
- `OutputEngine` — common output lifecycle with separate adapters for native displays and Blackmagic SDI hardware.
- `Infrastructure/Blackmagic` — DeckLink SDK / Desktop Video integration and the C++ or Objective-C++ interoperability layer.
- `Integrations` — opt-in third-party protocols and remote control, each isolated behind a capability interface.

Use dependency injection and protocols at genuine hardware and persistence boundaries. **Do not build a plugin platform or speculative abstraction framework before a real second implementation exists.** Keep domain logic independent from SwiftUI, AVFoundation, and DeckLink-specific types.

## Hardware and video-output rules

- Treat **Thunderbolt → PCIe enclosure → DeckLink Duo 2** as a native video-I/O path, **not** as four standard macOS desktop monitors. Discover DeckLink channels via the supported driver/SDK; do not infer them from `NSScreen`.
- A DeckLink Duo 2 provides **four configurable 3G-SDI connections**, not native HDMI ports. HDMI-only targets require correctly directed, powered SDI-to-HDMI conversion.
- Support independently assignable outputs with explicit device IDs, connector/channel, pixel format, resolution, frame rate, color assumptions, audio behavior, and fault status. Never hard-code connector order as if it cannot change.
- Use a time-aware output scheduling pipeline. Keep decoding, compositing, frame conversion, and hardware scheduling off the main UI thread. Bound queues, avoid unnecessary copies, and log dropped/late frames.
- A transparent broadcast graphic may require **two SDI channels for Fill + Key**. Document channel consumption, key/fill pairing, and the receiving ATEM configuration. A black background is **not** equivalent to transparency.
- Target **1080p59.94** as the first production format if supported by the complete chain; allow validated alternate modes. Respect the Duo 2's **3G-SDI / HD** limits; do not advertise 4K through this card.
- Distinguish **Audience**, **Stage**, and **Broadcast** output compositions. The same slide can have different themes, visible layers, or text arrangement on each screen.
- If a hardware output disappears or a mode becomes unsupported, retain operator control, report an actionable error, and degrade safely; never freeze the entire service.
- A hardware simulator may test device lifecycle and frame delivery logic, but only a real enclosure, card, driver, converter, receiving screen/ATEM, and signal test can mark the end-to-end path **Hardware Verified**.
- Any NDI, network control, Bible translations, song catalogs, or other third-party assets must respect licensing, SDK compatibility, and user authorization. Do not silently bundle copyrighted media or proprietary implementation details.

## Model assignment and delegation

| Model | Work |
|---|---|
| Haiku | Mechanical document updates, source inventory, test fixtures, repetitive UI previews, straightforward renames, and stubs |
| Sonnet | SwiftUI/AppKit features, SQLite repositories, render/output integration, unit/UI tests, debugging, refactors, and standard ADRs |
| Sonnet (independent review pass) | Video/audio architecture, hardware boundaries, synchronization, threading, memory safety, security, migrations, and milestone integration |

Use only models actually available in the environment. Prefer the least costly model reliable for the task. If the same approach fails twice, pause the implementation path, inspect the failure, and escalate to a more focused review or decomposition; do not repeatedly retry blindly. No Opus advisor and no cross-tool Codex orchestration.

- **Test-first on risky logic:** editing transaction safety, migrations, media timing, cue ordering, screen routing, output failover, Fill/Key pairing, concurrency, and file recovery. The coordinator defines failing acceptance tests before delegating implementation; the implementing agent must not weaken them to pass.
- Parallelize only independent tasks touching disjoint files. Only one task at a time owns a migration, shared output scheduler, or public domain interface.
- Store delegation briefs in `AI/specs/`, results and validation evidence in `AI/reports/`.
- Include the relevant feature ID (for example `HW-004`, `OUT-003`, or `MEDIA-006`) in task briefs, implementation notes, tests, and commits.

## Working rules

- Develop complete **vertical slices**, not a broad collection of unconnected screens, placeholder database tables, and unused protocols. Deliver functional workflows with tests and documentation.
- Prefer Apple frameworks over unnecessary external libraries. Use a third-party dependency only when it materially reduces risk and its license and maintenance status are acceptable.
- Keep the live playback path deterministic, observable, and isolated from expensive UI updates. Avoid force unwraps, blocking calls on the main actor, unsafely shared mutable buffers, and unbounded media queues.
- Implement well-defined **Preview**, **Live**, **Blackout/Clear**, and **Stop** semantics. Never let editing an inactive slide unexpectedly alter the live output.
- Preserve the user's media and presentations: atomic writes, safe schema migrations, explicit backups, recoverable autosave, and no destructive cleanup without approval.
- Use security-scoped file access/bookmarks when persistent access to external user media is required; do not assume file URLs remain accessible after restart.
- Make output mapping visible to the operator. Never silently redirect the livestream feed to a sanctuary projector, or accidentally expose speaker notes on an audience screen.
- Maintain accessibility, keyboard-first operation, readable stage typography, and bilingual/multilingual Unicode text handling.
- Code, tests, and docs change together. A feature is complete only after its feature spec, `docs/19-data-dictionary.md` (if data changed), `docs/17-change-log.md`, current status, and handoff files reflect the implementation.
- Track verification separately as **Implemented**, **Unit Tested**, **Simulated**, **Hardware Verified**, and **Live-Service Verified**. State **Not Verified** when a level is not supported by actual evidence.
- Do not copy third-party application code, branding, or proprietary assets. Build original WORSHIPFLOW behavior from documented requirements and permitted APIs.

## Build, test, and quality commands

Use the actual checked-in project and scheme; the commands below assume `WORSHIPFLOW.xcodeproj` and scheme `WORSHIPFLOW`. Create and maintain `scripts/check.sh` when initializing the repository.

```bash
# Discover configured targets and schemes
xcodebuild -list -project WORSHIPFLOW.xcodeproj

# Build the macOS application
xcodebuild -project WORSHIPFLOW.xcodeproj \
  -scheme WORSHIPFLOW -configuration Debug \
  -destination 'platform=macOS' build

# Run unit/integration/UI tests available in the scheme
xcodebuild -project WORSHIPFLOW.xcodeproj \
  -scheme WORSHIPFLOW -destination 'platform=macOS' test

# Project quality gate: build, tests, formatting, static checks
./scripts/check.sh
```

Use **Swift Testing or XCTest**, and **XCUITest** for operator workflows where appropriate. Unit tests must cover pure composition decisions and routing state. Integration tests must cover decoding and persistence. Add benchmark/performance tests for representative full-HD multi-output scenes. Require a macOS machine with the actual Blackmagic equipment for device qualification; normal CI builds must not depend on connected hardware.

Do not say a command passed unless it was executed and its exit status was checked. A missing scheme, driver, hardware device, or test environment is a documented blocker, not a success.

## Completion and handoff contract

At the end of each task, provide a concise report recording:

1. Feature ID, scope, changed files, and decisions made.
2. Build/test/lint results **actually run**, plus failures and skipped checks.
3. Output devices and formats tested, with evidence and verification level.
4. Relevant ADR, feature-spec, data-dictionary, change-log, status, and handoff updates.
5. Next safe task, known issues, and any genuinely blocking external prerequisites.

Commit after each reviewed task or milestone. Include feature IDs in the commit message (example: `feat(HW-004): add DeckLink device discovery and SDI output profiles`). Never report a feature done if its end-to-end acceptance criteria are incomplete.
