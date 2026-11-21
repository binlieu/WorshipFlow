# Agent handoff

Updated: 2026-11-20 (end of Phase 1 build)

## State

- Phase 1: every one of the 26 catalogue features has code and unit tests. Exit criterion **not met**; see `docs/phase-1-exit-review.md`.
- 550 package tests pass; `./scripts/check.sh` exits 0.
- An independent review of the live path, preview/live isolation and data safety is in progress. Its findings are fixed before Phase 2 feature work.

## Next safe tasks, in order

1. Fix confirmed findings from the independent review (test-first for each).
2. Phase 2 slices that need no hardware: OUT-005 mirrored outputs, OUT-006 Syphon, MEDIA-005 audio library, MEDIA-006 audio routing to a chosen device, MEDIA-004 live inputs from a USB or built-in camera.
3. HW-001 DeckLink: device abstraction and a simulator that can reach "Simulated". Real SDK integration is blocked on the SDK download (licence click-through) and the card.

## How work is run here

- The coordinator writes failing acceptance tests first (in their own test target, so parallel slices do not block each other), then a brief in `AI/specs/`, then delegates to a Sonnet subagent. Two agents at a time on disjoint files.
- Migration assertions must use `prefix(n)`, never exact equality, because later migrations follow.
- Agents must not request full computer control; background accessibility only. Anything unreachable goes on `docs/hands-on-checklist.md`.

## Blocked on the owner

- Hands-on checklist and the 60-minute soak (second display free at 60 Hz).
- Purchase of DeckLink Duo 2, Thunderbolt enclosure and ATEM (KI-001).
- Apple Developer Program membership for signing and notarization (DIST-02).
- OPEN-04 (is SDI needed?) and OPEN-11 (one church or many?).
