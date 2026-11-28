# FIX-AB: the Show grid follows Live and Preview, and a video clicked in the Show media bin is heard

Feature IDs: UI (Show grid), MEDIA-010 (background sound). Model: Sonnet. One agent in the main folder; nothing else is in flight. No migration.

Reported by the owner on 2026-11-27 from build 219, in his words:

1. "when hit spacebar, it move the live to next one but when live move all the way down to the bottom of the song, the scrollbar doesn't follow it so I have to manually scroll the bar to the bottom."
2. "same as moving the preview by keyboard, it won't scroll the bar even the preview goes out of the screen to the bottom of the page"
3. "the media bin only play sound when it's foreground, I want to have both video and sound when user click any media file in media bin in the show tab. does't have to be a background or foreground"

## What the code does today (confirm before changing)

- `App/Sources/CentrePane.swift`: `ScrollToSelection` calls `proxy.scrollTo(keys[new])` when `workspace.showParts.selectedIndex` changes. Nothing follows the live index. The cells sit in a `LazyVGrid` inside a `LazyVStack` (one grid per section run), and each cell carries `.id(slot.key)`. The owner sees no scrolling for Preview either: find out why with evidence (the likely cause is that a cell far down in a nested lazy container does not exist yet, so `scrollTo` has no target; other candidates: the keyboard path changes another value than `selectedIndex`, or the `keys` captured by the background view are stale). The list layout (`ShowSlimRow` and the list around line 155 to 200) and the Scripture list have their own scroll code: check whether they have the same fault and fix what does.
- `OperatorCore/MediaModel.swift` and `MediaEngine/MediaRegistry.swift` (MEDIA-010): a background video starts muted (`isBackgroundMuted`) until the operator unmutes it; a foreground clip is heard.

## Required behaviour, each test-first (write the test, run it on the old code, record that it fails for the stated reason, then change the code)

1. **The grid follows Live.** When the live slide of the open presentation changes (Space, Next, Previous, a click, a cue) and its cell is not fully visible, the grid scrolls so it is. This must work for the last slide of a long song and for a section far below the visible part. Only while the live presentation is the one that is open (`liveIndex(app, workspace)` in the same file); a live change in another presentation scrolls nothing.
2. **The grid follows Preview.** The same for the selected slide moved by the keyboard, including to cells that have never been on screen.
3. **Scrolling rule, one pure function, unit tested:** given what changed (live, selection) and the indices, which cell to reveal. If both change in one step, Live wins. A cell already fully visible must not make the grid jump (use the smallest scroll that reveals it; do not centre on every step). No scrolling while the operator is dragging the scroll bar is not required.
4. FIX-Q's rule stays: the grid's own body must not read the selection, the live place or the mode; the follow code is a small view of its own, as `ScrollToSelection` is. Nothing ticks while idle; no timers or polling to "retry" a scroll unless you show with evidence that one deferred step is needed, and then it is one step, bounded, not a loop.
5. **A video clicked in the media bin on the Show tab is heard, whatever its role.** Click a video as a background from the bin: picture and sound. The slide's own background (set on the slide, or by a theme) keeps today's rule and stays muted until the operator unmutes it: a motion loop must not start making sound because a slide went live. State the rule you implement for the mute button afterwards (the operator can still mute a bin background; the next bin click is heard again or keeps the operator's choice: choose the one that fits the existing mute control and its label, and say which). Blackout still silences; Clear and Stop keep their meaning; `--silent-audio` still silences everything. A sound file clicked in the bin keeps its current behaviour. The Media tab's own preview player is not part of this.
6. Tests for item 5 at the model level with the existing fakes (the `onBackgroundAudioChange` values after a bin click as background, after a slide's own background goes live, after Blackout, after mute); do not assert wall-clock.

## Rules

- New tests in `FIXAB_*.swift`. Do not edit or weaken existing tests. Source-rule tests (`FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests`, `FIXU_ViewSourceTests`) and the MEDIA-010 tests pin today's behaviour: if a MEDIA-010 test pins "a background starts muted" for the bin click itself, do not edit it; stop, list the test and the exact assertion in the report and finish the other items (the coordinator decides, since the owner asked for this change).
- Out of scope, not to be touched: `OutputEngine/`, the SDI adapter, the scheduler, Fill/Key, `RenderEngine/`.
- Smallest change. No new abstraction. No force unwraps. Swift 6 strict concurrency clean in Debug and Release. Editing never changes Live. Accessibility labels and keyboard behaviour kept.
- Seeing the scroll work: if the existing capture tooling (`UISnapshot*`) can show the grid after a key step under a temporary `--library` with `--silent-audio`, use it and say what you saw; otherwise say "not seen running" and list hands-on steps. The owner's own copy of the app is running (build 219): do not quit or disturb it; stop only process ids you started; never `pkill` by name. Never open the owner's real library, never touch `/Applications/WorshipFlow.app` or `~/Library/Application Support/WORSHIPFLOW`. Nothing that makes sound. No soak. No display or system settings. No full computer control. No advisor tool.
- If any test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271).
- Do not edit `docs/`, `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. Write `AI/reports/FIX-AB-report.md`: per item the cause found with evidence, the failing test and why it failed, the change, what is not verified; then change-log text, known-issues text (unnumbered), hands-on entries.
- No git state changes: the coordinator commits. The repository is public: no personal strings in any file.
- Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0, reading the exit status itself (timing-flaky `MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`, `MediaAvailabilityTests`: re-run once, report both). Do not leave monitors or wait loops running when you report.
- If the same failure shows twice, stop that item and write down what was tried.
