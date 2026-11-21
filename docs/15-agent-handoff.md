# Agent handoff

Updated: 2026-11-21

## State

- 1641 package tests pass; `./scripts/check.sh` exits 0 at commit "feat(UI-002)".
- Phases 0 and 1: every feature has code and tests; **exit criteria not met** (no hands-on use, no 60-minute timing run). See `docs/phase-1-exit-review.md` (written before the six-mode interface; the feature states still hold).
- Phase 2: SDI engine, real DeckLink bridge, SDI and mirrored outputs, audio, hardware test kit are built. Highest level reached: Simulated. The real bridge is Implemented, Not Verified (KI-052).
- Interface: six modes per ADR-0007 (UI-001, UI-002). Driven only by the debug snapshot hook; never clicked or typed in (KI-067).
- Phase 3 and 4 rules exist with no interface: cue engine (CUE-001), scripture engine and store with the import tool (LIB-004, LIB-004b).
- A hardware-test build can be packaged with `scripts/package-test-build.sh` (KI-074).

## Next safe tasks, in order

1. Independent review pass (Sonnet, read-only) over everything since the Phase 1 review: SDI engine and bridge, hardware test kit, six-mode interface, playlist kinds, scripture store, cue engine. Then fix confirmed findings test-first.
2. Scripture interface (LIB-004c): reference entry, translation picker, slides into a presentation, import screen. Bundling VI1925 waits on the owner (KI-062, KI-066).
3. Cue storage and interface (CUE-002): slide actions, macros and the schedule in the Cues mode; CoreMIDI devices (CUE-003); remote API and web control (CUE-004).
4. Phase 2 leftovers: Syphon (vendored source), live camera inputs.
5. Phase 4: recording and RTMP.

## How work is run here

- Coordinator writes or specifies failing tests first, a brief in `AI/specs/`, then delegates to a Sonnet subagent; at most two agents at once on disjoint files; new work goes in its own test target so parallel slices do not block each other.
- Migration assertions use `prefix(n)`, never exact equality.
- Agents: no git state changes, no advisor tool, no full computer control, temporary `--library`, `--silent-audio`, own scratch directory, nothing left in the home folder.
- The coordinator re-runs `./scripts/check.sh` and checks coordinator-owned tests, `docs/UI`, `docs/adr` and vendor files are untouched before every commit.

## Waiting on the owner (none blocks building)

- Hands-on checklist (`docs/hands-on-checklist.md`) and the 60-minute soak (`scripts/soak.sh 3600 1`, second display free at 60 Hz).
- Friend's hardware test with the packaged build.
- VI1925: where the database copy came from, and whether the printed text has Matthew 17:21 (KI-062, KI-066). Sixteen Vietnamese spellings to confirm (KI-064).
- An English translation to bundle (World English Bible or Berean Standard Bible are verified free).
- Apple Developer Program membership, when the app is to be given out without the approval step.
- OPEN-04 (is SDI needed?) and OPEN-11 (one church or many?).
