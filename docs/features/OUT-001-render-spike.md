# OUT-001 — Render spike

Satisfies: ARCH-03, ARCH-20 to ARCH-23, NFR-01, NFR-02, G-6 (in part). Phase 0.

## Purpose

Prove the pipeline everything else rests on: one Metal compositor produces frames, and output targets only present them.

## Behaviour

1. A scene is a background (colour or a looping video frame) plus text layers, each with a style, a normalised frame and an alignment.
2. Text is laid out by Core Text, so Vietnamese stacked diacritics shape correctly, fonts fall back, and no mark is clipped.
3. The compositor renders a scene to an offscreen premultiplied BGRA texture of any size. A transparent background stays transparent.
4. An output target takes those frames and presents them. Two targets exist: a borderless full-screen window on a chosen display, and an ordinary resizable window.
5. Each output counts presented, dropped and late frames against its target interval, and the operator can see the counts.
6. A soak mode runs unattended for a set duration and writes a report.

## Acceptance

| Check | Level needed |
|---|---|
| Coordinator tests in `DomainTests`, `RenderEngineTests`, `OutputEngineTests` pass | Unit Tested |
| `./scripts/check.sh` passes | Unit Tested |
| English and Vietnamese lyrics over a looping 1080p video on the second display, a different composition in an output window | Implemented, seen running |
| 60-minute soak on a 60 Hz display mode with zero dropped frames; memory and GPU load recorded | Measured on this Mac |

## Not in this slice

Persistence, editing, playlists, transitions, DeckLink, audio.
