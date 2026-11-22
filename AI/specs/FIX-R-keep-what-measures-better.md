# FIX-R: keep the FIX-Q changes that measure better, roll back the ones that do not

Feature IDs: UI (Show, Cues, Media), SYS. Model: Sonnet. One agent in the main folder. No migration.

The owner, 2026-11-22, after the FIX-Q report (`AI/reports/FIX-Q-report.md`): "Keep all fixes have better result and rollback fixes didn't hit the spec". FIX-Q (commit d6594de) made several separate changes; some measured clearly better, and Next, Previous, Go Live, Blackout, Clear and the drops measured **slower** after it, with the cause not established (KI-191).

## What to do

1. **List FIX-Q's changes as separate units** from the commit: (a) the release compile and hook check in `scripts/check.sh`; (b) `TickingWhile` for the Media controller row, audio cue card and sound rows (KI-190); (c) grid cells reading their own marks through `ObservedShow.isSelected(at:)` and `isLive(at:)`; (d) the Cues slide-action list working out the chosen slide once and being lazy; (e) the `#if DEBUG || WF_MEASURE` hooks; (f) anything else you find in the diff. Say which files each unit owns.
2. **Measure each product unit (b, c, d, f) by an interleaved A/B in a release measuring build:** build one variant with the unit and one without (everything else equal), and alternate them A, B, A, B at least three times each in the same session, so drift affects both alike. Gestures: Next, Previous, Go Live, Blackout, Clear, each drop kind, idle CPU, Next in Cues, with 200 slides and 100 bin items. Report median and spread per variant. The gap between repeat runs of the same variant is the noise floor: a difference inside it is "no measurable difference".
3. **Decide per unit, by the numbers:** a unit that is measurably better on some gesture and not measurably worse on any is kept. A unit that is measurably worse on any gesture, or shows no measurable benefit, is **rolled back** (its code, its tests and its doc entries removed or marked withdrawn; public additions it alone needed removed). Units (a) and (e) are tooling and stay. `FIXO_ViewSourceTests` must pass on real code after a rollback of (c), not on a comment kept to satisfy it: if (c) is rolled back, restore the original line; if (c) is kept, say so and leave the comment workaround listed as a known wart for the coordinator.
4. **If the slowdown is not explained by any unit** (both variants of every unit read equally slow against FIX-Q's "before"), say so plainly, measure commit 1d1e3be the same interleaved way against the final tree, and report whether a slowdown exists at all. Close or update KI-191 with what you found.
5. Output content must be unchanged: `FIXQ_PublishedScenesDigestTests` passes at the end without edits.

## Rules

- Do not edit existing tests other than removing FIX-Q's own tests for a unit you roll back. No wall-clock assertions.
- Editing never changes Live. No change to what any command does.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, or anything under `.claude/`.
- No git state changes in the main folder. To build a variant, copy the tree to your own scratch folder or use `git worktree add` under your scratch folder and remove it when done; never stash or check out in the main folder. No advisor tool. No full computer control. Never open the owner's real library; use a temporary `--library` and `--silent-audio`; do not disturb a WorshipFlow copy you did not start.
- The repository is public: no personal strings in any file or picture. Known issues continue from the highest number in `docs/16-known-issues.md`.
- Keep scratch build folders to the minimum the A/B needs and delete them all before you finish.
- Run each check in the foreground; leave no wait timers or background work; send one final message. Finish with `./scripts/check.sh` twice. Report to `AI/reports/FIX-R-report.md` with the table: unit, numbers with and without, noise floor, decision. Update the change log, known issues and hands-on checklist.
