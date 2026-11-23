# Agent handoff

Updated: 2026-11-22 (night)

## Current state (2026-11-22, night): read this section first; everything below it is history

- **HEAD** `be6d84c` on `main` (OUT-002c), pushed, plus docs commits. `./scripts/check.sh` passes on it: 3,507 tests, Debug and Release builds. Schema v15 (ADR-0009): a library opened by a v15 build cannot be opened by an older build; a copy is taken into the library's `Backups` folder before a migration.
- **Done on 2026-11-22:** FIX-K to FIX-V, UI-005c to g, UI-006c to g, SYS-015 (migration v15), UI-007c (Edit layers, lock, hide, text Fit and fill, video objects), UI-007d (mark in and out, markers, marker actions in Cues), UI-007e (Stage Section elements), UI-007f (Screens key label, typed signal chain, per-screen Look), FIX-U (Show window update cost), UI-008 (every mode re-measured against its design), TESTDATA-001, three independent reviews (REVIEW-FIX-N, REVIEW-3, REVIEW-4) with their fixes. Reports are in `AI/reports/`, briefs in `AI/specs/`.
- **Installed for the owner:** build 189 (commit `4bddabe`) in Applications, installed 2026-11-22 night with the owner's standing consent for that one install; library backed up first to `WORSHIPFLOW-backup-2026-11-22-h` (the older `-g` copy is also kept). The owner's library is at v14 until build 189 first opens it, which migrates it to v15 after an automatic copy. Package: `dist/WorshipFlow-hardware-test-20261122-4bddabe.zip` (the only zip kept). The rule for later builds stands: say a build is ready and ask before replacing the installed app.
- **The owner's real library** is `~/Library/Application Support/WORSHIPFLOW/`. Agents never open it and never launch the app without a temporary `--library`. Two exceptions happened, both asked for by the owner: the backup copy before each install, and the test-data import (a "Performance test" library of 100 synthetic songs and 204 bin images that point into the git-ignored `TestData/` folder, which must stay in place).
- **In flight:** nothing. No agent is running and no worktree holds unmerged work. Finished worktrees under `.claude/worktrees/` may be removed when clean and unlocked; never force-remove one.
- **Not verified, by any evidence:** nothing is Hardware Verified or Live-Service Verified (no DeckLink, enclosure or ATEM is owned). Almost none of the 2026-11-22 features has been operated by a person: `docs/hands-on-checklist.md` lists what to try. Marker timing against the real picture is unmeasured (KI-243).
- **Open speed gaps (KI-186, KI-187, KI-189, KI-267, KI-268):** longest main-thread burst, quiet machine: Clear 19 ms, Go Live after Clear 21 ms, Blackout 11 ms, slide drops 14 to 40 ms, against 8 ms median and 16 ms worst; MIDI at one message every 7 ms lags (median 66 to 83 ms). The cost is SwiftUI's graph update; Instruments cannot attach to the ad-hoc signed measuring build (KI-269).
- **Build caution (KI-271):** after a stored-property change to a shared domain type, run `swift package clean` before trusting a test failure, and package from an empty derived-data folder.
- **Soak:** a 60-minute run on display 1 on 2026-11-22 night (build 189 source) **measured no timing**: the output window was covered for all 14,126 samples (the screen was almost certainly locked while the owner was away), so presented, dropped and late are all 0 and KI-007 stays open. What the run does show: it ran the full 3,600 s without a crash or render error, 359,996 frames submitted, 706 slide advances, 214,599 video frames delivered, resident memory 149 to 186 MB. Both displays were at 100 Hz, so even an uncovered run would not have counted for the 60 Hz criterion. The soak must be repeated with the screen unlocked, nothing covering display 1, and the display set to 60 Hz by the owner (`scripts/soak.sh 3600 1`). **Second run, 2026-11-23 morning, display 1 uncovered at 100 Hz** (`AI/reports/soak-screen1-3600s-20261123-0524.log`, not in git): completed; 358,901 frames presented, 75 dropped, 10 late (0.02%), longest interval 590 ms against a 10 ms target, the window covered in 39 of 14,115 samples (about 10 s), memory 146 to 181 MB, no render error. Whether the drops and the 590 ms gap fall inside the covered seconds is not known: the report has no per-drop times. Not a pass for KI-007 (drops are not zero, and the display was not at 60 Hz). **10-minute runs on the 60 Hz display (screen index 2), 2026-11-23, never covered:** before OUT-002c 7 drops of 35,989 (six at the first show of each of the soak's six slides, one at 531.7 s); after OUT-002c (`be6d84c`) 4 drops of 35,984, none at a first show (343.1, 544.8, 567.8, 580.6 s), each one missed refresh, longest interval 33.33 ms. The first-show drop is fixed at Simulated level on a real display; the sporadic single drops are unexplained (the Mac was in use over Remote Control during both runs). KI-007 stays open. Installed build 189 does not contain OUT-002b or OUT-002c.
- **Next safe tasks:** an independent review of the UI-007, FIX-U, FIX-V and UI-008 merge (`0f89ce3..HEAD`); KI-272 (Cues in light appearance); the open low findings of REVIEW-3 and REVIEW-4; the hands-on checklist with the owner.
- **Waiting on the owner (none blocks building):** plain Clear button and amber tag; Stop in a menu; a moving preview in Media; which English Bible to bundle; Edit toolbar icons; whether to start a Windows port (the project is macOS-only until an ADR says otherwise); sending the new zip to the DeckLink tester; an Apple Developer account for signing.
- **Coordinator rules:** the project `CLAUDE.md` overrides any global file (no Codex, no advisor). Hand off at 97% context or 99% of the weekly Fable limit. The repository is public: scan staged changes for personal strings before every commit; push `main` only; never push the tag `backup/pre-rewrite-2026-11-21`.

## History: state on 2026-11-21, afternoon (superseded)

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

## History: state on 2026-11-22, morning (superseded by the current state at the top)

- **HEAD** `1d1e3be` on `main`, pushed. Since the section below: UI-005c/d/e/f/g, FIX-K, FIX-L, FIX-M (drag and drop), FIX-N (Stage keys), FIX-O (show state observed part by part), FIX-P (review fixes). 3,017 tests pass. FIX-Q: the check now also compiles the Release build (and fails if the Release app contains a measuring hook); `scripts/package-test-build.sh` still builds the packaged app.
- **Installed for the owner:** build 145 (commit `a0fa76c`) in Applications, library backed up to `WORSHIPFLOW-backup-2026-11-22-g`. Package for the hardware test: `dist/WorshipFlow-hardware-test-20261122-a0fa76c.zip`. The owner's library now also holds a "Performance test" library (100 synthetic songs) and 200 bin images that point into `TestData/` in the repository folder. Build 139 crashed for the owner at launch (KI-193); 145 guards the crash site but the crash was not reproduced: ask what they clicked.
- **In flight (started 2026-11-22 afternoon):** five Sonnet agents. Three in worktrees on `AI/specs/UI-006-mode-features.md` (UI-006c Edit, UI-006d Media, UI-006e Stage), each committing to its own branch for the coordinator to merge; one in the main folder on FIX-S (reproduce and root-cause the KI-193 crash, intermittent tests, the `FIXO_ViewSourceTests` wart, build copies showing as apps); one read-only on a third full review (`AI/reports/REVIEW-3.md`). After the merges: UI-006g Cues and UI-006f Screens, one migration slice for whatever the modes list under "needs a migration", the 60-minute soak, then a build offer.
- **Needs a migration (collected from the UI-006 reports, not built):**
  - UI-006c (Edit):
    - `TextObject.fit: enum { none, shrinkToFit }` and `TextObject.backgroundFill: ColorRGBA?` (plus compositor support in `TextLayer`).
    - `SlideObject.name: String?`, `SlideObject.isHidden: Bool` (default false), `SlideObject.isLocked: Bool` (default false); the scene must skip hidden objects.
    - `SlideObject.Content.video(VideoObject { mediaID, loops, muted })`.
  - UI-006d (Media):
    - `mediaAsset`: `markIn REAL NULL`, `markOut REAL NULL` (seconds; null = whole clip). Used by the registry's player and `MediaTransport` for foreground and background clips (engine work as well).
    - New table `mediaMarker(id TEXT PK, assetID TEXT NOT NULL REFERENCES mediaAsset(id) ON DELETE CASCADE, time REAL NOT NULL, name TEXT, actions TEXT NOT NULL)` (the `PlaybackMarker` shape; `actions` is the `CueAction` JSON) and the app side that feeds `MarkerTracker`.
    - Collections are in app state today (key `media.collections`, one JSON); if the library should carry them in a program package export (LIB-005) they need `mediaCollection(id, name, sortOrder)` and `mediaCollectionItem(collectionID, assetID, sortOrder)`. Not needed for them to work.
  - UI-006e (Stage):
    - For features not built: Section element needs on `SlideContent` (or `ShowDeck`) a stored `sectionName: String?` and the arrangement order of the presentation's items (`nextSectionName: String?`) carried to `ShowState`; Video element needs no stored field but a render path.
  - UI-006f (Screens):
    - `ScreenProfile.connectedTo` is indexed per destination (0 primary, n+1 mirror n); an SDI screen with Fill + Key has one destination for two connectors. To label the key tile separately: add `connectedToKey: String?` per destination (or change the array to `[DestinationNote]` with `fill`, `key`).
    - Enclosure and converter nodes (SC-25, SC-31): per destination `chain: [ChainNode]` where `ChainNode` is `{kind: enclosure | converter | other, label: String}`, typed by the operator, labelled "typed by you".
    - Per-screen Look (SC-51): `Look` keyed per screen (`screenLookID: UUID?` on `ScreenProfile`, or a per-screen selected-Look table).
  - UI-006g (Cues):
    - **Playback markers (CU-33)**: table `cuePlaybackMarker` (`id` TEXT primary key, `assetID` TEXT not null references the media asset, `time` REAL not null, `definition` TEXT not null (versioned JSON `{version, actions}` as the other cue rows), `sortOrder` INTEGER, `createdAt`, `updatedAt`), index on `assetID`. `PlaybackMarker` and `MarkerTracker` exist in CueEngine and are tested; what is missing is the table, the store methods and the clip-position feed.
- **Known and told to the owner:** undo of "Apply to all slides" is wrong from the slide it was applied on (review M1, in FIX-P). FIX-Q (committed): Release numbers show the cost is not in composing or publishing scenes (0.3 to 0.9 ms) but in SwiftUI updating the Show window (a Next is about 25 to 40 ms of main-thread CPU; every drop above the 8 ms target; MIDI at one message per 7 ms still queues): KI-186, KI-187, KI-189. FIX-Q removed a steady 15 to 19% idle load (KI-190).
- **Coordinator limit:** the weekly Fable window read 0% on 2026-11-22 afternoon (it had been 98% that morning), so the hold was lifted. The rule stands: hand off at 99%.
- **Next, not started:** release-build timing of Next and drops, then the publish path (KI-187); the features each mode's design draws but the app lacks (lists in the UI-005c to g reports); a third full independent review; the 60-minute soak (`scripts/soak.sh 3600 1`); the friend's DeckLink test.
- **Open questions for the owner:** unchanged from the section below, plus whether the amber BLACKOUT/CLEARED tag is quiet enough.
- **Housekeeping:** agents' scratch build folders fill the boot disk (it reached 4 GB free on 2026-11-22); tell each agent to keep one build folder and delete it when done.

## History: state on 2026-11-21, evening (superseded)

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
