# UI-005g report: Cues mode measured and closed against 06-cues.html

Feature ID UI-005g. Brief `AI/specs/UI-005-mode-geometry.md`. Level: **Implemented**, measured in a debug build on the seeded design library at 1440 x 900 (dark and light). Not Hardware Verified, not Live-Service Verified. No model, schema or behaviour change.

## Tools (own files only)

- `scripts/design-rects docs/UI/mockups/06-cues.html out.json` (the Show tool, unchanged): 281 design elements.
- `App/Sources/CuesDesignCapture.swift` (debug only) with `scripts/cues-capture.sh`: opens the Cues mode at 1440 x 900 with the design's five macros (5, 4, 6, 3, 2 steps), a slide action on two slides, seven MIDI bindings and one macro run. Writes `cues-dark` and `cues-light` pictures and rectangle dumps. One block added in `UISnapshotRun.swift` (see "Shared-file lines").
- `scripts/design-map-cues.json`: 182 mapped elements (toolbar and transport reuse Show's entries; the chosen mode is `b.on[4]` here).
- Compare: `scripts/compare-rects.py <design.json> <app.rects.json> scripts/design-map-cues.json`.

## Before and after (dark; light gives the same counts)

"Before" is the tree at HEAD with only tags added to the old views (old code had no bar, tables, number circles or title block, so elements it did not draw count as not drawn).

| Region | Mapped | Drawn before | Within 1 pt before | Within 1 pt after |
|---|---|---|---|---|
| toolbar (shared bar) | 23 | 23 | 16 | 16 |
| sidebar | 25 | 12 | 0 | 16 |
| centre (bar, action rows, Add action, note) | 39 | 9 | 0 | 38 |
| right column | 76 | 20 | 0 | 72 |
| transport (shared bar) | 19 | 19 | 14 | 14 |
| total | 182 | 83 | 30 | 156 |

Worst remaining (app minus design, points):
- sidebar, 9 elements exactly 26.0 down in top and bottom with left and right exact: the Control inputs section and `sb.sec.1` bottom. Cause: the design lists two presentations under Slide actions, the app one (see below). Nothing else is out.
- centre, one element: title chip `main.pill` L +0.6, R -1.5 (the chip's text is 2.1 pt narrower than the browser's).
- right column, 4 elements, all content: the keyboard table has 13 keys in the app and 9 in the design, so the keyboard section ends 116 lower and the Activity section starts 116 lower (`r.sec.1` B +116, `r.sec.2` T +116, B -31, `r.act.title`, `r.act.lines` T +116).
- toolbar and transport misses are the shared bars (timers capsule -2.7, Previous L -8.3 from a shorter live text): the same as in the Show report, not touched here.

Not called matched: sidebar (the 26 pt), right column below the keyboard table. Matched within 1 pt: the page bar, the five action rows with every number, column, detail, tag and pill, Add action, the order note (top, left, right), the MIDI map header, table header, all seven rows and their cells, the keyboard table's first nine rows, the Macros and Slide actions sections, all section labels.

Pixel comparison, for reference only: 10.5 % differ at tolerance 24 (toolbar 10.0, sidebar 9.0, centre 14.5, inspector 12.1, transport 13.0). The rest is text anti-aliasing, the left-out Playback markers, the content differences and the sample text.

Pictures: `AI/reports/UI-005g-cues-dark.png`, `-dark-side.png` (design left, app right), `-dark-diff.png`, `-light.png` (there is no light design picture for Cues).

## What was wrong (causes)

Columns were 260 / 372 (design 230 / 380, borders inside); rows 32 pt with 14 pt text and 18 pt icons (26 / 13 / 15); no 43 pt bar (title was an in-page 22 pt field); action rows 48 pt with a 24 pt number, 190 pt kind column and 14 pt semibold titles (38 / 20 / 150 / 13 bold); buttons 30 pt and native menu chrome; MIDI and keyboard lists were stacks with dividers, not tables (header row, 28 / 29 pt rows, cells with 8 pt padding); the note had no card fill, radius or bold lead. Now built from `CuesSection` (`.sec`), `CuesListRow` (`.li`), `CuesPage` (`.bar`), `CuesActionRow` (`.act`), `CuesTableRow` / `CuesCell` / `CuesKbd` (tables), all in `CuesComponents.swift`, using the shared `PillTag`, `HeaderButtonStyle`, `wfField`, `SectionLabel` and `Tok` tokens.

## Left out (open, needs a feature slice)

- CU-22 Test in Preview (no dry run to Preview exists). Its 126.9 pt place is kept so the Trigger field stays where the design has it.
- CU-21 keyboard trigger: the Trigger field shows only the MIDI binding and is absent when there is none.
- CU-33 Playback markers section (header, 54 pt timeline, three marker lines, time axis): markers are not stored or run. Its room (142 pt) is kept, so the order note sits where the design has it.
- CU-29 "Stage layout" action and CU-28 loop and dissolve in "Start background": no such action or parameter. The design's row 4 is a Stage message in the seed; row 2 reads "Set background".
- "CC 7: Media audio level": no such command; the seed binds CC 7 to Stop.
- The second Slide actions row ("Baptism testimony 3"): actions are stored per slide and only the open presentation's slides can be listed, so one row for the open presentation (its title and the number of slides with actions).
- "Learn…" in the MIDI map header: learning lives on the MIDI page; the button says "Manage…" and opens it.

"Later" rows: Stream Deck is drawn as the design draws it, a disabled row with "later" (no button, VoiceOver says "Stream Deck, later, not available"). Remote API reads "Remote control" (it is a phone page; kept, as the audit recommended).

## Where the extras went

- Schedule: its own section at the bottom of the left column, below Control inputs (so no designed row moves).
- Macro delete: an ellipsis menu in the bar, between the title chip and the trigger (free room).
- Move up, move down, edit, remove on action rows: they appear at the right of the row on hover, while the edit form is open, and stay in the accessibility tree (VoiceOver and full keyboard access reach them while hidden).
- Per-binding menu (open the MIDI page, delete binding): the design's "..." cell.
- Conflict triangle on a MIDI row: after the command text.
- The MIDI, Remote, Schedule and Slide-actions pages use the same 43 pt bar with the page title, and 14 pt padding.
- MIDI channel in the MIDI map: omitted for channel 1 ("Note C2"), "Note C2 ch 2" otherwise.

## The order note

Bold "Order is fixed and visible." followed by the text the app had: actions run top to bottom as shown, except a step that moves the show comes first, then the Look, props and messages, media, sound, timers and MIDI; a wait splits the list in two; a macro never changes a screen's destination and cannot put speaker notes on an Audience or Broadcast screen. It does not say "on one frame boundary", which the executor does not promise.

## Unmapped elements

Design side: window buttons 4 (system); icon glyph boxes 42 (SF Symbols draw to their own metrics; the control holding each is compared); wrappers 15; Test in Preview 1 and the bold key in the Trigger field 1; the kind text inside each action's column 5; Playback markers 17; the note's text boxes 3; the second Slide actions row 2; the table wrappers 4; the activity's warning line 1; status dots and meters in the shared bars 10. App side: the 4 extra keyboard rows (16 tagged elements) and the Schedule section (4 elements).

## Shared-file lines

`App/Sources/UISnapshotRun.swift`: one block (5 lines, commented) running `runCuesDesignScenario` when `UI_SNAPSHOT_CUESDESIGN` is set, in the same shape as the other scenario blocks, placed before the UI-005a block.

## Wanted in the shared files

- `SectionLabel` as a block (full column width) as the design's `div.h`; the label is as wide as its text and its right edge is not compared.
- A table row, cell and inline `.kbd` component (now `CuesTableRow`, `CuesCell`, `CuesKbd`) and the `.li` row (`CuesListRow`), which Edit, Media and Stage may want too.
- OperatorCore wording the design has: "Start background" (the app says "Set background"), richer detail lines ("Worship, full, on Audience and Broadcast", "from 00:00").

## Change log (for docs/17-change-log.md)

UI-005g: Cues mode matched to 06-cues.html: columns 230 / 1fr / 380, 26 pt list rows, a 43 pt page bar with an editable title and the Run button, 38 pt action rows (move, edit and remove on hover), tables for the MIDI map and the keyboard, the order note as a card with a bold lead, Stream Deck as a "later" row, Schedule moved to the bottom of the left column. Playback markers, Test in Preview and the keyboard trigger are not drawn. New debug capture `UI_SNAPSHOT_CUESDESIGN` and `scripts/cues-capture.sh`, map `scripts/design-map-cues.json`.

## Known issues (for docs/16-known-issues.md)

- Cues: the left column lists one Slide actions row (the open presentation); the design lists every presentation with actions. Needs a per-presentation count from the cue store.
- Cues: Test in Preview, a keyboard trigger and Playback markers are open (CU-21, CU-22, CU-33); "Stage layout" and loop and dissolve in "Start background" are open (CU-28, CU-29).
- Cues: the title chip is 2 pt narrower than the design's.

## Hands-on checklist (for docs/hands-on-checklist.md)

- Cues: hover an action row: move, edit and remove appear at its right; Tab through the row reaches them; the edit popover still opens.
- Cues: rename a macro in the bar's title (Return or leaving the field); delete from the ellipsis menu in the bar; "..." on a MIDI row deletes that binding.
- Cues: the left column's Stream Deck row cannot be clicked; Schedule sits below Control inputs.
- Cues: dark and light, a window narrower than 1440: the bar's Run button stays at the right.

## Checks

`./scripts/check.sh` did NOT exit 0. Run three times with `WF_DERIVED_DATA` set while the machine was at load average 18 to 46 (four agents building): run 1 crashed in `anUnplugEndsTheRenderThread` (unowned reference), run 2 had 7 timing failures (MIDIRouterTests, VideoPlayerSourceTests), run 3 had 3 (ScriptureLibraryTests 2.22 s against a 2 s limit, MIDIRouterTests `orderIsKeptForABurst`): each time other tests failed, none in code this slice touches (no package file changed). The failing suites passed when re-run alone: `swift test --filter "MIDIRouterTests|VideoPlayerSourceTests|anUnplugEndsTheRenderThread"` 29 tests in 4 suites passed. The rest of the check was run by hand: domain boundary grep found nothing (exit 1 from grep = clean), `xcodegen generate` and the app build exit 0. A full package run of 2720 tests in 423 suites has therefore not passed in this worktree; the coordinator should re-run the check on a quiet machine.

## Not verified

Window widths other than 1440 (the 142 pt reserved for the markers and the 126.9 pt reserved for Test in Preview are fixed sizes); a macro title wider than the bar; the other pages (Slide actions, Schedule, MIDI, Remote) were restyled to the bar and padding but not measured (the design has no picture of them); VoiceOver on the new rows; hover controls with a real pointer (the capture has no pointer); the app with a connected MIDI device (the sidebar dot and the device name).
