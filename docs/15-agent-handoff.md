# Agent handoff

Updated: 2026-11-21 (afternoon)

## State

- Public repository: github.com/binlieu/WorshipFlow, Apache 2.0, every commit authored as Simon Lieu <me@simonlieu.com> (repo-local git config). A local-only tag `backup/pre-rewrite-2026-11-21` holds the pre-rewrite history and must never be pushed. Push `main` only.
- Package tests: see `AI/reports/UI-003-report.md` for the count and the five consecutive full runs after the UI-003 work. KI-079 is closed (a test rig race).
- The owner used the app on 2026-11-21 (imported a song; "everything working so far") and has a real library at `~/Library/Application Support/WORSHIPFLOW/`. **Never launch the app without a temporary `--library`; never touch that folder.**
- The owner's design session (a cloud session, not reachable by SendMessage) writes into `docs/UI`. Design revision 2 is committed. Do not edit `docs/UI`; commit the owner's changes to it separately.

## In flight

- **UI-003 is implemented and waiting for review and commit** (report `AI/reports/UI-003-report.md`). Brief `AI/specs/UI-003-design-revision-2.md`): bring the app to design revision 2 (media dock and controller in Show, search in the sidebar, timers in the toolbar, tabbed inspector, quick edit tab, stage message) and fix KI-079. Report lands in `AI/reports/UI-003-report.md`. Coordinator then re-runs the check, confirms coordinator-owned tests, `docs/UI`, `docs/adr` and vendor files are untouched, commits and pushes.

## Next safe tasks, in order

1. After UI-003: rebuild the hardware-test package (`scripts/package-test-build.sh`) so the owner's friend gets the current build.
2. CUE-002b is done (commit 1f94df9) and its review fixes are done (FIX-E, brief `AI/specs/FIX-E-cue-002b-review.md`, report `AI/reports/FIX-E-report.md`): 2126 package tests, `./scripts/check.sh` exits 0. Not done: playback markers. Not verified: a real MIDI device, a phone, mouse use of the Cues views, sleep and wake, a real network change, a real disk write failure. When a build is ready, tell the owner what changed and ask before replacing `/Applications/WORSHIPFLOW.app`.
3. LIB-004c scripture interface is implemented and waiting for review (`AI/reports/LIB-004c-report.md`). Bundling VI1925 waits on the owner (KI-062, KI-066).
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

## Design match (UI-005)

Added 2026-11-21. The owner wants the app to match `docs/UI` exactly, screen by screen, features included. Read `AI/specs/UI-005-design-match-plan.md` first: it holds the owner's four decisions, the coordinator's defaults and the order of slices. The audits are `AI/reports/UI-005-audit-*.md`. Done before it: MEDIA-010, LIB-005, UI-004 (the product is written WorshipFlow; the library folder keeps its old spelling) and FIX-G (schema v11). Next: UI-005a (`AI/specs/UI-005a-components-and-show-appearance.md`), then UI-005b to UI-005h in the plan's order. Tell the owner when a build is ready and ask before replacing `/Applications/WorshipFlow.app`; remove the old bundle first so the new capitals take.

UI-005h (output looks) is implemented and waiting for review and commit: report `AI/reports/UI-005h-report.md`, spec `docs/features/UI-005h-output-looks.md`. Migration v13 adds the Classic themes; the SDI output's readback changed to a GPU copy; the measuring tools are `scripts/design-rects` (now with `--root`, `--width`, `--css`), `wf-looks-probe`, `scripts/compare-rects.py` with `scripts/design-map-looks.json`, and `scripts/compare-looks.py`. Open: the audience watermark and the stage section label (KI-139), editing a plate or gradient in the theme editor (KI-143), hardware (KI-138). Next in the design order: Edit, Media, Stage, Screens, Cues, each with a mapping file.

FIX-J (the review of UI-005h) is implemented in the working tree and waiting for review and commit: brief `AI/specs/FIX-J-ui-005h-review.md`, report `AI/reports/FIX-J-report.md`, feature notes in `docs/features/UI-005h-output-looks.md`. Known issues KI-150 to KI-156. Open for the owner: whether the earlier UI005h digest tests may be gated by machine identity (KI-156). Next safe task: the design order after UI-005h (Edit, Media, Stage, Screens, Cues) or the hands-on pass of the FIX-J checklist.

## State on 2026-11-22, morning (read this first, then the section below)

- **HEAD** `4c62e8a` on `main`, pushed. Since the section below: UI-005c/d/e/f/g (modes matched to their mockups), FIX-K, FIX-L, FIX-M (drag and drop), FIX-N (review fixes, Stage keys), FIX-O (show state observed part by part). 2,990 tests pass.
- **Installed for the owner:** build 129 (commit `58cc234`) in Applications, library backed up to `WORSHIPFLOW-backup-2026-11-22-b` beside the library. Package for the hardware test: `dist/WorshipFlow-hardware-test-20261122-58cc234.zip`. FIX-O is newer than the installed build and has not been offered yet.
- **In flight:** one Sonnet agent in the main folder on `AI/specs/FIX-P-fix-n-review.md` (fixes from `AI/reports/REVIEW-FIX-N.md`, MIDI latency measurement, the KI-188 control run). When it reports: check protected folders, run `./scripts/check.sh`, scan for personal strings, commit, push, package, announce the build and ask before replacing build 129.
- **Known and told to the owner:** undo of "Apply to all slides" is wrong from the slide it was applied on (review M1, in FIX-P). Grid drops still stall 8 to 38 ms and Next takes 20 to 35 ms in a debug build (KI-186, KI-187): the remaining cost is in composing and publishing scenes, which needs its own slice with release-build numbers first.
- **Coordinator limit:** the weekly Fable limit was at 96% at this point. At 99% the coordinator stops and the work resumes in a new session after the reset on 2026-11-26 (the owner chose to wait, not to run a Sonnet coordinator).
- **Next, not started:** release-build timing of Next and drops, then the publish path (KI-187); the features each mode's design draws but the app lacks (lists in the UI-005c to g reports); a third full independent review; the 60-minute soak (`scripts/soak.sh 3600 1`); the friend's DeckLink test.
- **Open questions for the owner:** unchanged from the section below, plus whether the amber BLACKOUT/CLEARED tag is quiet enough.
- **Housekeeping:** agents' scratch build folders fill the boot disk (it reached 4 GB free on 2026-11-22); tell each agent to keep one build folder and delete it when done.

## State on 2026-11-21, evening (read this first)

**How the coordinator works here.** The project `CLAUDE.md` overrides any global instruction file: no Codex, no advisor. The coordinator writes a brief in `AI/specs/`, a Sonnet agent builds it tests-first and reports to `AI/reports/`, a second Sonnet agent reviews the commit read-only, a fix brief follows, and the coordinator runs `./scripts/check.sh` itself, checks protected files (`docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/`), scans staged changes for personal strings (the repository is public), commits as the repository's configured author with the `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` trailer, and pushes `main` only. The local tag `backup/pre-rewrite-2026-11-21` must never be pushed. Independent slices run in parallel in git worktrees under `.claude/worktrees/` (ignored by git), at most three or four at once: more than that overloads the Mac and the package's MIDI tests interfere across simultaneous runs. Each worktree agent touches only its own files, commits to its own branch, and the coordinator merges, regenerates the project (`check.sh` runs xcodegen), merges the docs entries from the reports, and checks the merged tree.

**The owner.** Tests by hand and reports findings in plain lists; each list becomes a `FIX-<letter>` brief with their words quoted. They want the app to match `docs/UI` exactly (plan: `AI/specs/UI-005-design-match-plan.md`), measured by rectangles (`scripts/design-rects`, `scripts/compare-rects.py`, `scripts/design-map-*.json`), with their own later requests kept and their explicit overrides recorded. When a build is ready: say what changed and what is not verified, and ask before replacing `/Applications/WorshipFlow.app`. On yes: confirm the app is not running, copy `~/Library/Application Support/WORSHIPFLOW` to a dated backup beside it and confirm it is identical, remove the old bundle, `ditto` the packaged app in, verify signature and version. Never launch the app against that library; agents always use a temporary `--library`.

**Installed build:** 115 (commit e9fbd33). Package: `scripts/package-test-build.sh` writes `dist/WorshipFlow-hardware-test-<date>-<commit>.zip`; remove older zips and stray `.app` copies in DerivedData after each build so the owner sees one app.

**Done today, in order:** CUE-002b and FIX-E; LIB-004c and FIX-F; MEDIA-010, LIB-005, UI-004 (the name is WorshipFlow; the library folder keeps its spelling) and FIX-G (schema v11); UI-005a, UI-005b (v12), UI-005i (Inter), FIX-H, UI-005j (Show by rectangles), UI-005h (output looks, v13), FIX-I (keyboard sections: arrows move the selection, Return goes live, Space is Next), FIX-J (lyrics fit their block); UI-005c, UI-005d, UI-005g merged (Edit, Media, Cues by rectangles).

**In flight when this was written:**
- `AI/specs/FIX-K-hands-on-build-115.md` in the main folder: clear icons' glyphs, Clear menu removed, boxes draggable in Edit (lyric boxes get a per-slide frame, possibly migration v14), LIVE chip removed from Edit, Stage and Screens, mode switcher left-aligned, drag performance. Review it independently after it lands (it changes the editor and may add a migration).
- Stage (UI-005e) in a worktree: layout done at commit 47ec43b on its branch (71 of 82 within 1 point), now making every Stage canvas box draggable with eight handles. Merge after FIX-K is committed.
- Screens (UI-005f) in a worktree: layout pass under the hardware-truth rules.
- After each merge: check the merged tree, package, announce.

**Next, not started:** the features each mode's design draws and the layout passes left out (lists in `AI/reports/UI-005c`, `-d`, `-e`, `-f`, `-g` reports and the three audits): Edit (video object, align, per-role preview, zoom, fit control, text background, layers), Media (collections and audio playlists, offline and Locate, in and out points and markers, routing matrix and cue meters, the moving preview picture has no home), Stage (video and section elements, auto-fit, per-element eye, second-language colour, Band, Speaker and Clock presets), Cues (Test in Preview, keyboard trigger, marker timeline, second Slide-actions row), Screens (add, remove and identify screens, typed chain labels, statistics). One agent at a time owns a migration. Then a third full independent review, the 60-minute soak (`scripts/soak.sh 3600 1`), and the friend's DeckLink test with the package.

**Open with the owner:** whether the plain Clear button should also leave the transport bar; whether Stop should move into a menu; whether the moving preview picture should return in Media; VI1925 source and missing verses (KI-062, KI-066); which English translation to bundle; an Apple Developer account for signing.

**Nothing is Hardware Verified or Live-Service Verified.** The SDI path, the key matte with the plate, and the GPU-blit frame copy have only met the simulated card.
