# Brief: MEDIA-005 and MEDIA-006 — audio library and audio routing

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0005-phase-2-integrations.md` (decision 8), `AI/reports/research-2026-11-20-phase2-integrations.md` (audio section — much of it is unverified background knowledge: check each API against the SDK headers on this Mac before relying on it), `docs/MASTER-SPEC.md` rule HW-08, `AI/reports/MEDIA-001-report.md`, `Sources/MediaEngine`, `Sources/OperatorCore/MediaModel.swift`, `App/Sources/MediaBinPanel.swift`, `MediaTransportStrip.swift`.

Catalogue: MEDIA-05 (audio library: import, play from a list, level control, visible meter), MEDIA-06 (audio routing: media audio to a chosen sound device). SDI audio embedding is out of scope until the DeckLink bridge exists.

## Rules for this slice

Test first for every decision: write the failing test, record its output, then implement. Decisions live in `OperatorCore` (or a pure part of `MediaEngine`) so they can be tested without real devices; inject device lists, players and clocks.

## What to build

**`MediaEngine`**:
- `AudioDeviceCatalog`: lists Core Audio output devices (UID, name, channel count, is default), observes devices appearing and disappearing, behind a protocol so tests use a fake.
- `AudioCuePlayer`: plays audio files (the bin's audio assets) through `AVAudioEngine` to a chosen device UID, with play, pause, resume, seek, stop, loop on or off, volume, and a level meter (peak and RMS per channel, delivered to the main actor at about 20 Hz, never touching actor state from the real-time thread). If the chosen device disappears it falls back to the system default, reports it, and keeps playing where possible.
- Video players in `MediaRegistry` route their audio to the same chosen device (`audioOutputDeviceUniqueID` or what the headers on this Mac actually offer).

**`OperatorCore`**:
- `AudioModel` (`@MainActor @Observable`): the audio list (audio assets from the bin), the selected "programme audio device" (persisted; nil means system default), transport for the current cue (reuse `MediaTransport`), volume, mute, meter values, an operator-readable error when a file is unreadable or a device is lost. Rules to test: one cue plays at a time unless a cue is marked "overlap"; choosing a missing device falls back and reports; the chosen device survives a relaunch; Stop (show stop) stops cues; Clear and Clear all do not.
- HW-08 guard: the app plays each audio signal down one path only. A foreground video's sound and a cue both go to the programme device; there is no second copy anywhere. State this in the feature doc you write (`docs/features/MEDIA-005-audio.md`).

**App**:
- An Audio section in the right-hand column: the list of audio files with duration, play or pause, a scrubber, loop toggle, volume, mute, a two-channel level meter, and a device picker showing output devices by name with the default marked.
- Info.plist or entitlement changes only if genuinely required for output (none expected); say what you changed in `project.yml` if anything.

## Do not modify

Coordinator-owned tests. `Package.swift`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`. `Sources/SDIEngine` and `Tests/SDIEngineTests`: another agent is working there (its test target may not compile until it finishes — that is expected; verify with filtered runs of your own targets, or a scratch copy, then retry the full check before finishing).

## Seeing it run

Sound: you may play audio **only** at very low volume for at most two seconds, once, to confirm the meter moves and the device picker lists real devices; say exactly what you did. Prefer verifying with the meter on a rendered-to-nowhere or muted path if the engine allows it. Launch with a temporary `--library`, keep runs under a minute, never cover a display, never switch display modes, do not change the system volume or the system default device, do not request full computer control, quit the app, leave nothing behind in the home folder. Save `AI/reports/MEDIA-005-audio.png` of the Audio section and describe it.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, nothing blocking on the main thread or the real-time audio thread. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests|MediaEngineTests'` passes with your new tests; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step failed solely because of the other agent's unfinished work.
2. The screenshot exists and you have described it.
3. `AI/reports/MEDIA-005-report.md` records what was built, which APIs you verified against headers, which paths you exercised in the running app, commands run with exit status, and everything not verified (in particular whether any sound was actually heard or metered).
