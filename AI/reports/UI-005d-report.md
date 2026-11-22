# UI-005d report: Media mode measured against the mockup's rectangles, and the clear icon buttons

Feature ID UI-005d. Brief `AI/specs/UI-005-mode-geometry.md` (item 5 is this slice's alone). Level: **Implemented**, measured in a debug build on a generated library at 1440 x 900 (dark and light). Not Hardware Verified, not Live-Service Verified. Design: `docs/UI/screens/05-media-audio.png`, `docs/UI/mockups/05-media-audio.html`.

## Tools used (the UI-005j ones, plus two files of this slice)

- `scripts/design-rects` on the mockup (322 elements), `App/Sources/DesignProbe.swift` tags in the views, `scripts/compare-rects.py`.
- `scripts/design-map-media.json` (new): 175 entries. Left and right column, header bar, grid, strip: mine. Toolbar and transport bar are the same code as Show, so their entries are the Show entries joined to the Media mockup's paths; they are listed separately below and are not this slice's region.
- `scripts/design-capture-media.sh` (new, by hand): builds, runs a copy of the app under a throw-away bundle id with a temporary `--library` and `--silent-audio`, prints the comparison for dark and light.
- `App/Sources/UISnapshotMediaDesign.swift` (new, debug only): `UI_SNAPSHOT_UIMEDIA=1` with `UI_SNAPSHOT_DESIGN=1` seeds fifteen tiles in the design's order (eight clips that are the same test file under other names, seven generated pictures), the live background, the strip's item, a 4:31 tone playing at 2:14, at 1440 x 900.

## Before and after (dark; the light capture gives the same counts)

"Before" is the tree at 99c97a9 with only the tags added (same capture, same map). Mapped = elements that are drawn and in the map; the design's elements that the app does not draw are in the list further down.

| Region | Mapped before / after | Within 1 pt before | Within 1 pt after |
|---|---|---|---|
| left list (sidebar) | 10 / 11 | 0 | 11 |
| centre (bar, grid, tiles, strip) | 33 / 91 | 0 | 86 |
| right column (audio cue, output, levels) | 0 / 31 | 0 | 29 |
| toolbar (Show's code) | 23 / 23 | 16 | 16 |
| transport bar (Show's code) | 19 / 19 | 14 | 14 |

Before, the right column had no element that existed in the design's structure (the old column was a player, a list and a two-bar meter), the centre had four-column tiles of another size, and no row of the left list was at the design's height (30 high rows, 14 pt text, no section rule).

Worst remaining, in points (app minus design; edges L T R B):
- strip badge "Live · background": R -2.7 (the text is 3.5 pt narrower than the browser's; the Show LIVE badge matches, so it is this string's measure); meta line L -2.7 follows from it (R is skipped: it states only what the app knows).
- header bar: Import L +2.0 R +1.5 and the layer switch L +1.5: the switch's two labels are 0.5 pt narrower each than the browser's, and everything left of it moves (same cause as the UI-005j "SwiftUI text measure").
- "Audio cue" label R -1.5 (letter-spaced text, as LIBRARIES in UI-005j); level label "R" L +0.8 R +1.2 (a 7.0 pt glyph centred where the design's is 6.7).
Not within 1 point: 7 of 175 mapped elements counting the two toolbar/transport groups' Show leftovers excluded; of the 133 in this slice's three regions, 126 are within 1 point (the 7 above).

## Closed

Left list 220 (219 and a 1 pt rule), rows 26 high with 8 pt padding, 13 / 11 pt, section rules and the 172 pt first group; header bar (47 high: title 17 / 700, Import, layer switch, grid / list switch at the design's x); grid of five equal columns (12 / 14 gaps, padding 14), tile picture 16:9 radius 4, kind chip, duration chip (mono 10 / 600), caption 11 / 600, rings from the shared thumbnail ring; clip strip (77 high, two rows, 6 pt scrub with a 14 pt knob in `MediaScrub`); right column 340 (Audio cue card 120 high, Output section 255, Levels with 14 x 130 meters and the 0 / -12 / -24 / -48 scale). Everything uses the shared segmented control, pop-up, buttons, thumb rings and type styles; no offsets.

## Left out (open, needs a feature slice; the room is kept)

L rows of the audit, with the design element: named bin collections (Motion backgrounds, Announcement loop, Sound cues rows; the first group's two empty rows keep its 172 pt height, the audio group's second row keeps 26 pt), Live inputs row, the offline callout and Locate... (M5), Mark in / Mark out / Add marker (M18, their 260 pt stays: the extras below sit in it), the routing matrix (M24, its 136 pt stays empty; its section is titled "Output" because it holds only what exists), the Cue L and Cue R meters (M26: two 14 pt columns stay empty), the audio collection name at the right of "Audio cue". The title "Motion backgrounds" reads "All media" (the bin's existing kinds). Counts and names differ because the seed is not the design's data. M9's list view was built (a plain list, no design picture to match).

## Where the extras went

- Bin player: it is the clip strip now. It plays the item chosen in the bin on this Mac only, shows the "Live · background / foreground" badge or the blue "Background / Foreground" mark, restart / play / stop, times, scrub, Loop. The video's own picture is no longer drawn (the strip has no room; the tile is the picture). The "preview on this Mac only" note and the silent-audio line moved into the strip's accessibility label and the mute button's tooltip.
- Live background / Live foreground (and Play live for a sound): in the room of the marker buttons. Mute for the preview and "Use the slide's own background" (only while an override is on): in row 1 left of Loop. The selected-item action row and the override row under the grid are gone; the context menu keeps both.
- Hot folders: a "Folders" group in the left list below Audio (add, per-folder row, missing state); the folder header with Play folder, Stop folder, Stop following and Point to the folder again... stays at the top of the grid.
- BACKGROUND / PLAYING capsules: bottom left of the tile picture (the design shows only the ring).
- Sound-file list (play, loop, overlap, Stop sound, the paragraph): a "Sound files" section under Levels. The Output refresh button: right end of the Output label.
- The long hint under the grid is now the layer switch's tooltip.

## The owner's request: clear icon buttons (item 5)

Five icon buttons, in this order: Clear lyric, Clear background, Clear foreground, Clear music, Clear all (`MediaClearButtons.swift`). In the Show dock's header row (`MediaDockView.swift`) they follow the Audio tab after the design's 1 pt divider (16 pt tall, 3 pt each side); the Show dock's right-hand elements did not move. The same row sits in Media mode's bin header, after the title, in free room (the title and the buttons share the bar's left; Import and both switches keep the design's x).

Each button calls the existing command through the one command path (`AppModel.clear`, `clearBackground`, `clearForeground`, `clearMusic`, `clearAll`), has a tooltip with its name and key (`Clear lyric (esc)`, `Clear background (⌃⌥B)`, `Clear foreground (⌃⌥F)`, `Clear music (⌃⌥M)`, `Clear all (⇧ esc)`), an accessibility label and hint, and looks disabled (muted, 45 %) when there is nothing of its kind: lyric needs a live slide with words showing, background a live or chosen background, foreground a playing clip, music a sounding cue, all any of them. No red. The Clear menu of the transport bar is untouched.

Pictures: `AI/reports/UI-005d-clear-buttons-show-dock.png` (Show dock header, lyric and background enabled; foreground and music disabled; Clear all enabled), `AI/reports/UI-005d-clear-buttons-media-bar.png` (Media bar).

**Show re-run** (`scripts/design-map-show.json`, same capture as UI-005j, before and after the dock change): 242 mapped / 207 within 1 point before and after; dock 51 / 42 before and after; the set of elements outside 1 point is identical (diff of the `--all --bad` listings is empty), so every other dock element still passes as before (the dock's 9 leftovers are UI-005j's own: tile captions, layer switch, Loop pill, tabs).

## Pictures

`UI-005d-media-dark.png`, `-media-dark-side.png` (design left, app right), `-media-dark-diff.png` (pixels differing by more than 24 / 255: 16.5 %; reference only; what remains is the test clip's rainbow in every clip tile, the text anti-aliasing, the meters' live fill, and the seed's different names), `UI-005d-media-light.png`. The design set has no light picture for Media, so no light side-by-side exists. Each picture is under 1 MB.

## Shared-file lines added

- `App/Sources/UISnapshotRun.swift`: one commented block (9 lines, the hook's usual shape) that runs `runMediaDesignScenario` when `UI_SNAPSHOT_UIMEDIA` is set, placed just before the Design block.
- `WORSHIPFLOW.xcodeproj/project.pbxproj`: regenerated by xcodegen for the new files (the coordinator will regenerate after merging; do not hand-merge).
- Wanted in the shared files: `MediaScrub` (a 6 pt / 14 pt scrub, the Media and Audio-cue geometry that differs from `WFSlider`'s 5 / 13) could move to `WFControls.swift`; `Badge` could take an `uppercase` option (strings are upper-cased by the caller now).

## Docs entries for the coordinator

**Change log** (UI-005d, 2026-11-21): Media mode drawn to the design's rectangles: 220 pt bin list, header bar with Import, layer switch and a grid / list switch, five-column grid with kind chip and duration, 77 pt clip strip (the bin player moved into it; the video picture is no longer drawn), 340 pt column with the Audio cue card, Output (device) and Levels (vertical meters on the printed scale), sound list below. Show dock header and Media bin header gain five clear icon buttons (lyric, background, foreground, music, all) through the existing commands. New scripts/design-map-media.json and scripts/design-capture-media.sh.

**Known issues**: (1) Media: the preview video's picture is not drawn any more (no room in the strip); the tile and the grid show the poster. (2) Media: strip badge "Live · background" is 3.5 pt narrower than the design's, header Import and layer switch 1.5 to 2 pt off, "Audio cue" label 1.5 pt narrow (SwiftUI text measure of letter-spaced and medium text). (3) Left out, need feature slices: named collections and Announcement loop, Live inputs, offline detection and Locate..., in / out points and markers, routing matrix, cue bus and its meters. (4) The old foreground-clip strip (`MediaTransportStrip`) still stacks above the transport bar when a clip plays over the words, in addition to the new strip. (5) The Show dock header may overflow before the Layer switch below about 1000 pt window width (five more buttons); not checked at other widths.

**Hands-on checklist**: In Media: click each row of the list; click a tile (blue ring, strip shows it), double-click (goes live as the layer switch says, red ring only while on air); play, restart and stop in the strip; Live background / Live foreground; the clear icons (tooltip with the key, greyed when nothing to clear, each clears only its layer; Clear in the transport bar still works); switch grid / list; add a folder; drag a tile on a slide; change the output device; play a sound and watch the Audio cue card and the Levels move.

## Check and tests

`./scripts/check.sh` (own build folder) exits 1: the Inter-font source test caught a system font in my first clear-button glyph (fixed); the three runs after that fail only MIDIRouterTests (aHeldPadFiresOnceUntilReleased, orderIsKeptForABurst: 30 s waits) plus, in the first run, ToolProcessRunnerTests and ScriptureLibraryTests timing limits, all in packages this slice did not touch, under four parallel builds. 2720 tests in 423 suites. The app builds (xcodebuild Debug, no errors).

## Not verified

Other window sizes (grid at 5 columns gets narrow below about 900 pt of centre width), the list view beyond a look, VoiceOver on the new strip and cue card, the audio device pop-up with several devices, hot folder states in the new list, the Clear buttons' disabled logic against every show state (checked: lyric, background and music enabled in the capture, foreground disabled), a real hardware run (none: Implemented only).
