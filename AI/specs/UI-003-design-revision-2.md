# Brief: UI-003 — bring the app to design revision 2

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0007-ui-design-adoption.md`, **all of `docs/UI/README.md`** (revised: run `git show HEAD -- docs/UI/README.md` to see exactly what changed in this revision), every picture in `docs/UI/screens/` (look at each, especially `01-operator-show.png` and the new `01b-operator-show-quick-edit.png`), `AI/reports/UI-001-report.md`, `AI/reports/UI-002-report.md`, `docs/16-known-issues.md` (KI-067 to KI-073, KI-079), `docs/hands-on-checklist.md`, all of `App/Sources` and `Sources/OperatorCore`.

The owner used the app, then revised the design to make it more convenient. This slice makes the app match the revision. It is a layout and convenience pass over working features, plus one small new feature (stage message).

## Rules (unchanged from UI-001 and UI-002)

Test first for every decision; views stay thin (decisions in `OperatorCore` or `Domain`); no dead controls and no invented data; red only for "on screen now"; a simulated device is always labelled; behaviour beats the picture (ADR-0007); never load anything from `docs/UI/mockups`; nothing that works today may be lost — keep the before-and-after control table up to date and include it in the report; transport bar and transport keys work in every mode.

## Part 0 — fix the flaky relaunch test first (KI-079)

`UI002_PlaylistItemsTests.relaunchOnAHeaderLandsOnTheNextPlayableItem` fails intermittently under load: after a relaunch whose saved place is a playlist header, `selectedPlaylistItemID` is sometimes nil. Find the real cause in `WorkspaceModel.load()` and the restore path (an ordering race between loading playlist items and applying the saved place is the suspicion). Reproduce it deterministically (inject the delay or ordering), fix the cause, and run the full suite five times in a row. Do not weaken the test or add sleeps.

## Part 1 — Show mode, revision 2 (match `01-operator-show.png`)

- **Search** moves from the toolbar to the top of the sidebar's Libraries section (Command-F focuses it; Escape returns focus to the grid). It searches titles and lyrics and filters the list beneath it; results open as today. The toolbar has no search field.
- **Timers in the toolbar**, beside the AUD, STG and BRD pills, visible in every mode: the timers the operator marks as "show in toolbar" (default: the first elapsed timer and the first countdown), with a start or pause button on a stopped or running countdown. Overrun uses the warning colour. No timers: nothing is shown.
- **Slide grid** fits five thumbnails across at the design's window size, adapting to width.
- **Media bin dock** under the slide grid (a vertically resizable, collapsible pane whose height and collapsed state are remembered in settings): tabs Backgrounds, Videos, Images, Audio; a horizontal strip of thumbnails with duration badges and the same Preview and Live rings as slides; a Background layer or Foreground choice that decides what a click does; "+" to add files; reuse `MediaBinPanel`, `MediaTransportStrip` and `MediaModel` logic. Clicking a tile changes the media without leaving Show.
- **Media controller row** under the thumbnails, only while a video or audio file is loaded: restart, play or pause, stop, name, elapsed and remaining, scrubber, loop, mute and volume, and which screens it is on. It replaces the separate clip strip above the transport bar in Show (keep that strip in the other modes so a clip can always be stopped).
- **Monitors:** Preview and Live side by side at the top of the right column; Stage and Broadcast (every other enabled screen) beneath, each captioned with its destination text ("SDI 3", "Window", a display name) and the Simulated badge where true.
- **Look:** one compact row of buttons with a chevron menu for the rest; names are the operator's own Look names (the design's "Full", "Notes", "Lower 3rd", "BG only" are examples).
- **Tabs** in the lower right column: Props, Cues, Audio, and Quick edit when editing. Props: the existing props list with toggles (show role chips only if they reflect real data: which roles' screens show the props layer in the active Look). Cues: the Cues placeholder note until cue wiring exists. Audio: the existing audio panel.
- **Quick edit tab** (`01b`): Command-E, or selecting a slide and choosing Quick edit, opens a fourth tab with the selected slide's two language fields and notes, a "Preview only" chip, and Done (Escape). It replaces the words editor strip under the grid in Show (the Edit mode keeps its full editor). It edits the **selected** slide and never the live output, exactly as the strip did. The existing "Quick edit live slide" action, which deliberately changes the live slide, must remain available and must be unmistakably labelled as changing what is on screen (for example in the transport bar's menu or on the Live monitor) — do not merge the two meanings. Read the README's wording on this carefully and, if it conflicts with keeping both, keep both and say so in the report.
- **Stage message** (new, small; catalogue LIVE-03): a text field and Send in the right column; Send shows the message on stage screens through the stage layout's message element (and as a banner on stage screens whose layout has no message element), never on audience or broadcast; Clear removes it; it survives slide changes and is cleared by Stop. Test first in `OperatorCore` and with `StageComposer`. Persist the last few messages for reuse.
- **Screen configuration** is not in Show: the "Configure…" affordance switches to the Screens mode.

## Part 2 — the other modes

Compare `02-editor.png`, `03-screens-outputs.png`, `04-stage.png`, `05-media-audio.png`, `06-cues.png` and the light pictures with the app and with their previous versions (`git diff HEAD~1 --stat -- docs/UI/screens` shows which changed); apply what changed in this revision, using only features that exist. List per mode what you changed and what you left and why.

## Part 3 — checklist and pictures

Update `docs/hands-on-checklist.md` for the new layout without dropping any check. Using the debug `--ui-snapshots` hook (extend it) with a temporary `--library`, `--silent-audio`, a bilingual song, media in the bin with a background playing and a clip loaded, timers, a prop, and the simulated SDI card: save `AI/reports/UI-003-<mode>.png` for each mode, plus Show with the Quick edit tab open, Show with the dock collapsed, and Show in light. Look at each beside its design picture and write the comparison.

## Do not modify

Coordinator-owned tests. `Package.swift`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, earlier migrations, vendor files. `Sources/MIDIIO`, `Sources/RemoteControl`, `Sources/CueStore`, `Sources/CueEngine` (not wired in this slice).

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps in the live path. **The owner's real library exists at `~/Library/Application Support/WORSHIPFLOW/` and contains their data: never launch the app without a temporary `--library`, and never touch that folder.** Keep runs under two minutes, never cover a display, never switch display modes, play no sound, do not request full computer control, quit the app, leave nothing in the home folder. Do not commit or change git state in any way. Do not consult any advisor tool. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0, and the full suite passed five times in a row after the Part 0 fix. Paste the summary line.
2. The pictures exist with your comparisons.
3. `AI/reports/UI-003-report.md`: per part, what was built, what was left out and why, the updated control table, paths exercised in the running app, commands run with exit status, and everything not verified.
