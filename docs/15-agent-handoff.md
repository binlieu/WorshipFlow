# Agent handoff

Updated: 2026-11-21 (afternoon)

## State

- Public repository: github.com/binlieu/WorshipFlow, Apache 2.0, every commit authored as Simon Lieu <me@simonlieu.com> (repo-local git config). A local-only tag `backup/pre-rewrite-2026-11-21` holds the pre-rewrite history and must never be pushed. Push `main` only.
- 1935 package tests; `./scripts/check.sh` passes except for one intermittent failure under load (KI-079), being fixed in UI-003.
- The owner used the app on 2026-11-21 (imported a song; "everything working so far") and has a real library at `~/Library/Application Support/WORSHIPFLOW/`. **Never launch the app without a temporary `--library`; never touch that folder.**
- The owner's design session (a cloud session, not reachable by SendMessage) writes into `docs/UI`. Design revision 2 is committed. Do not edit `docs/UI`; commit the owner's changes to it separately.

## In flight

- **UI-003** (brief `AI/specs/UI-003-design-revision-2.md`): bring the app to design revision 2 (media dock and controller in Show, search in the sidebar, timers in the toolbar, tabbed inspector, quick edit tab, stage message) and fix KI-079. Report lands in `AI/reports/UI-003-report.md`. Coordinator then re-runs the check, confirms coordinator-owned tests, `docs/UI`, `docs/adr` and vendor files are untouched, commits and pushes.

## Next safe tasks, in order

1. After UI-003: rebuild the hardware-test package (`scripts/package-test-build.sh`) so the owner's friend gets the current build.
2. CUE-002b: wire the cue store, the MIDI layer (CUE-003) and the remote control server (CUE-004) into the app and give the Cues mode real content, following the design's Cues picture. Add the reflow warning for slide actions (KI-075).
3. LIB-004c: scripture interface (reference entry, translation picker, verses into a presentation, import screen). Bundling VI1925 waits on the owner (KI-062, KI-066).
4. A third independent review pass (Sonnet, read-only) after those, then fixes.
5. Phase 2 leftovers: Syphon (vendored source), live camera inputs. Phase 4: recording and RTMP.

## How work is run here

- Coordinator writes or specifies failing tests first, a brief in `AI/specs/`, then delegates to a Sonnet subagent; at most two or three agents at once on disjoint files; new work goes in its own target so parallel slices do not block each other.
- Agents: no git state changes, no advisor tool, no full computer control, temporary `--library`, `--silent-audio`, own uniquely named scratch directory, nothing left in the home folder.
- Before every commit the coordinator re-runs `./scripts/check.sh`, checks protected files are untouched, and scans staged files for personal strings (macOS user name, old email, computer name) because the repository is public.
- Migration assertions use `prefix(n)`. Tests must not assert on wall-clock durations.

## Waiting on the owner (none blocks building)

- Hands-on checklist (`docs/hands-on-checklist.md`) and the 60-minute soak.
- Friend's hardware test with the packaged build.
- VI1925: source of the database copy; whether the printed text has Matthew 17:21 (KI-062, KI-066); sixteen Vietnamese spellings (KI-064).
- An English translation to bundle (World English Bible or Berean Standard Bible are verified free).
- Apple Developer Program membership, later.
- OPEN-04 (is SDI needed?) and OPEN-11 (one church or many?).
