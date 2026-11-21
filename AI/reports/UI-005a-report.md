# UI-005a report: shared components and Show matched to the design

Feature ID UI-005a. Brief: `AI/specs/UI-005a-components-and-show-appearance.md`. Level: **Implemented**, compared by picture in a debug build. Not Unit Tested for appearance (pictures are the evidence), not Hardware Verified, not Live-Service Verified.

## What was built

1. **Comparison tool.** `UI_SNAPSHOT_DESIGN=1` in the ui-snapshots hook (`UISnapshotRun.swift`, `UISnapshotDesign.swift`) seeds a temporary library (libraries Songs, Sermons, Announcements; five songs; Amazing Grace in nine slides with the design's section names; the playlist "Sunday 9:00" with Pre-service, Worship, Message and Response; seven bin tiles with the design's names, one a test clip, six generated gradients; a prop; the timers; the four Look names; the simulated SDI card so Audience reads SDI 3 and Broadcast SDI 1+2) and captures the window at exactly 1440 x 900 points, 2x, as Show (dark), Show with Quick edit, and Show (light). `ComponentsBoard.swift` (debug only) draws the component sheet with the app's own components in its own 1440 x 754 window for `08` and `10`. `scripts/compare-design.sh` (a Swift tool it compiles) writes the side-by-side and the difference image and prints the share of pixels more than 24 of 255 apart, overall and per region. `scripts/design-capture.sh` builds, runs one throw-away copy of the app (temporary `--library`, `--silent-audio`, window outputs, its own bundle id) and compares all five pictures. Both are run by hand; `check.sh` does not call them.
2. **Shared components** (`WFControls.swift`, `Components.swift`, `DesignTokens.swift`): segmented control, toggle, checkbox, slider, field, pop-up field, tabs, thumbnail ring and tag, message card, button kinds (resting, primary, ghost, ring, 45 % off), pill with dot and icon, badge, key hint. Tokens added: `Radius.track` 7, `Radius.segment` 5, `Metric` (ring widths and offset, toggle, checkbox, scrubber, monitor gap, Look height, timer capsule). Test `UI005a_ComponentTokenTests` pins the radii to `design-tokens.json` and the extra values to the mockup CSS.
3. **Show**: toolbar, sidebar, playlist, header, grid, dock, controller row, inspector, Quick edit tab, stage message, transport bar, message card. Dark and light.
4. **Extras and the hidden bar** (below).

## Before and after (share of pixels differing by more than 24 of 255; the "before" is the tree at commit 19a6d3d with the same seed)

The floor is not zero: the mockups are set in Inter and the app in SF, so every line of text differs by a few pixels, and the design's sample art is CSS gradients where the capture has generated pictures and a rainbow test clip.

### `01-operator-show.png`

App capture `AI/reports/UI-005a-show-dark.png`, side by side (design left, app right) `UI-005a-show-dark-side.png`, difference `UI-005a-show-dark-diff.png` (red = more than 24 of 255 apart in any channel).

| Region | Before | After |
|---|---|---|
| overall | 34.9% | 20.2% |
| toolbar | 79.4% | 16.7% |
| sidebar | 52.1% | 13.3% |
| playlist | 20.2% | 17.3% |
| centre | 29.5% | 20.5% |
| dock | 30.6% | 26.1% |
| inspector | 40.3% | 21.9% |
| transport bar | 18.2% | 16.5% |

### `01b-operator-show-quick-edit.png`

App capture `AI/reports/UI-005a-show-quick-edit.png`, side by side (design left, app right) `UI-005a-show-quick-edit-side.png`, difference `UI-005a-show-quick-edit-diff.png` (red = more than 24 of 255 apart in any channel).

| Region | Before | After |
|---|---|---|
| overall | 35.6% | 21.2% |
| toolbar | 79.4% | 16.7% |
| sidebar | 52.1% | 13.3% |
| playlist | 20.2% | 17.3% |
| centre | 29.5% | 20.3% |
| dock | 30.6% | 26.2% |
| inspector | 43.2% | 26.2% |
| transport bar | 18.2% | 16.5% |

### `09-operator-show-light.png`

App capture `AI/reports/UI-005a-show-light.png`, side by side (design left, app right) `UI-005a-show-light-side.png`, difference `UI-005a-show-light-diff.png` (red = more than 24 of 255 apart in any channel).

| Region | Before | After |
|---|---|---|
| overall | 42.1% | 21.4% |
| toolbar | 78.5% | 15.3% |
| sidebar | 51.8% | 13.0% |
| playlist | 20.0% | 17.2% |
| centre | 44.4% | 23.9% |
| dock | 36.1% | 26.2% |
| inspector | 44.6% | 22.0% |
| transport bar | 18.2% | 16.5% |

### `08-components.png`

App capture `AI/reports/UI-005a-components-dark.png`, side by side (design left, app right) `UI-005a-components-dark-side.png`, difference `UI-005a-components-dark-diff.png` (red = more than 24 of 255 apart in any channel).

| Region | Before | After |
|---|---|---|
| overall | 15.2% | 12.7% |
| buttons | 13.0% | 11.4% |
| selection | 14.3% | 7.6% |
| role and status | 15.1% | 15.2% |
| thumbnail stat | 30.7% | 33.3% |
| messages | 30.5% | 11.5% |
| colour | 14.2% | 11.0% |
| brand | 10.6% | 8.4% |

### `10-components-light.png`

App capture `AI/reports/UI-005a-components-light.png`, side by side (design left, app right) `UI-005a-components-light-side.png`, difference `UI-005a-components-light-diff.png` (red = more than 24 of 255 apart in any channel).

| Region | Before | After |
|---|---|---|
| overall | 15.7% | 13.3% |
| buttons | 13.3% | 11.6% |
| selection | 11.9% | 7.3% |
| role and status | 15.4% | 15.5% |
| thumbnail stat | 34.5% | 36.2% |
| messages | 30.7% | 11.5% |
| colour | 14.1% | 10.9% |
| brand | 10.5% | 8.3% |

### What is still above tolerance, and why

- **Toolbar (16.7 % dark, 15.3 % light):** text in another font; the window's three controls are the system's and grey while the window is not key (the design draws them coloured); the sidebar button sits a few points right of the design's; timers read "0:12" (the model's format) not "00:12:32"; the title block reads "Sunday 9:00 / WorshipFlow · Songs" where the design has "Sunday 9:00 — 22 Nov / WorshipFlow · Lakeshore library" (service date is UI-005b).
- **Sidebar (13.3 %):** text font; library icons are all the song icon (kinds are UI-005b) and the capture has no Scripture count; the design's Songs shows 214, the seed 5.
- **Playlist (17.3 %):** the design's list has Countdown, Announcements loop, Ephesians, Sermon and a film item; the model has no such items (UI-005b), so rows differ in content and the rows below them are offset. The list is still a system List (drag-reorder and arrow keys), whose selected row shows a faint square block behind the rounded fill.
- **Centre (20 to 24 %):** slide text and the thumbnails' backgrounds (the design's gradients against the capture's theme background and a small prop mark), "Natural order" where the design says "Sunday" in the arrangement field, the grid's section labels' font.
- **Dock (26 %):** tile art (generated gradients, a rainbow test clip, the Waves tile shows a different frame), the tab and controller text font, the time (a running clip).
- **Inspector (22 %, Quick edit 26 %):** the Live and Stage and Broadcast previews are real renders (a rainbow clip, five lines of text) where the design draws two-line text on a teal gradient; Look names are the seed's, with the design's four; Props shows one prop where the design shows four (UI-005b); the Quick edit labels are "First language / Second language" (language names are not stored) and the saved note has no seconds.
- **Transport bar (16.5 %):** text font and the headline's content (the capture's slide has two long lines); the design's meter ends in red, the app's in warning (the owner-bound rule "red means on air").
- **Components (12.7 % dark, 13.3 % light):** font; the thumbnail states differ most (33 %, 36 %) because the design's thumbnails are radial CSS gradients and the board's are a linear gradient; the brand card has no logo mark or wordmark file in the app (the wordmark is plain text in the product spelling "WorshipFlow", the design's is the capitals file); the Components heading sits 4 pt lower.

Note on the "before" figures: the first baseline taken (before the data and the board were finished) is not used. The board's first picture was upside down (a rig bug, fixed), so the five "before" figures above come from a second run of the unchanged tree with the final seed and the final board code, built in a scratch copy made with `git archive` (no git state changed).

## Audit rows

**Closed (S and M) and seen in the capture:** window and panel widths and resize ranges (sidebar 256 in 240-380, inspector 372 in 320-440, centre 812); T3 sidebar toggle (Option-Command-S); T4 mode switcher; T5 timer capsule (look; the format is the model's); T6 timer colours (text colour, warning on overrun, never red); T7 pills. SB2 search field; SB3 key hint; SB5 Scripture row; SB6 divider; SB7 song list (a plain stack with arrow keys). PL1 header (field and dots; the "+" menu moved into the dots menu); PL3 section headers; PL4 icons and no numbers (kinds that exist); PL6 LIVE marker; PL7 selected row. H1 to H6. G1 to G10. D1 to D9. C1 to C8. I1 to I8, I11, I12, I15, I16, I22, I23. Q1, Q2, Q4 in part (12 pt text, 46 / 30 pt, "None"), ST1, ST2. TR1 to TR6, TR8, TR9 (cyan to warning). K1 to K10, K13. Edit/Media/Stage shared X1 (bar hidden), X6 (switch and checkbox app-wide); Screens/Cues X-03, X-04, X-05, X-09, X-10.

**Open, and why:**
- L, UI-005b: T1 service date, SB4 library kinds and icons, PL5 playlist item kinds, I13 the four seeded Looks, I20 and I21 prop kinds and per-prop targets, Q3 language names, Q5 "saved N s ago" (no source), K11 error actions (Retry output, Details; the card and Dismiss are done).
- H3 the arrangement field appears only when a playlist item is selected (the design always draws it; it has no meaning otherwise).
- G12 the "other" section colour: tokens and CSS disagree (decision A5), left as it was.
- I9 the stage monitor's content (stage layout default, Stage slice).
- T5 time format "00:12:32" (formatting lives in OperatorCore).
- C9 `MediaTransportStrip` and I19 the Audio tab: still system controls (their modes' slices, or a later drop-in pass).
- K3, K4, K5 in the other modes: segmented pickers, sliders and pop-ups in Edit, Media, Stage, Cues and Screens are still the system ones (their layouts belong to their own slices); X-01, X-02, X4, X5 there are open for the same reason.
- Playlist still a system List (selection block, see above); Q4 the focus glow on the focused field.

## Where each extra went

Quick edit: the centre header only (the button under Preview is gone; the tab is opened from the header, the slide menu and Command-E). Edit live slide, the live background override (with Drop) and Configure: one slim row under the monitors. Screens open/close: the toolbar, left of the pills. Playlist "+" (header, countdown): the playlist's "..." menu, with the playlist actions. Stage message "Stage screens only", recents, "On stage now" with Clear: kept in the stage message section. Own-background mark, context menus, drag and drop, search tags, "not installed" and "empty" tags: kept. Cues tab and Audio tab content: kept (their controls use the drop-in switch and checkbox where they had one). Clear menu's layer entries and Clear all: kept, in the one Clear menu, with "Clear words (Escape)" first. Scripture row (Command-J): kept in the library list. The transport states STOPPED, CLEARED and BLACKOUT: kept.

## Transport bar hidden in Edit, Stage and Screens

`WorkspaceMode.showsTransportBar` (OperatorCore) is true for Show, Media and Cues. Test `UI005a_TransportBarModesTests` pins that, and that every transport key decision (Return, Space, arrows, Escape, Shift-Escape, B) is the same for every mode (the key monitor never reads the mode). The operator sees what is live in those modes from a chip in the toolbar: a LIVE (or CLEARED or BLACKOUT) tag and the slide's words, beside the timers. Seen in the capture code path only, not in a picture of Edit, Stage or Screens.

## Existing tests changed

None edited. Added: `UI005a_TransportBarModesTests` (2 tests), `UI005a_ComponentTokenTests` (2 tests). One existing guard test (`UI004_NoOldSpellingTests`) caught the capital spelling in my new debug board; the board now writes "WorshipFlow".

## Checks actually run

- `./scripts/check.sh` run twice after the last code change: both exit 0, 2451 tests in 380 suites passed each time.
- Captures: `scripts/design-capture.sh` about a dozen times, each a Debug build, one run of a throw-away copy of the app with a temporary library, killed when done. No process of mine is left; `dist/` untouched; the real library folder never opened.

## Not verified

A real pointer (clicks, drags of the three resize strips, scrubbers, toggles, segmented controls), Tab with full keyboard access, VoiceOver on every custom control (traits and values are the system's by construction, but were not heard), a second display, a light-mode check of every new control beyond Show, the minimum window size 1100 x 640 with the new fixed columns, and the transport bar's hidden state in a picture of Edit, Stage and Screens. Colour contrast of ThumbTag text in light was set to white as the design says, not measured.

## What the owner should look at first

1. Show in the running app beside `docs/UI/screens/01-operator-show.png`: the toolbar, the dock and the inspector's slim row (the "Edit live slide…", override and Configure are packed tight when an override is on).
2. Drag the three resize strips and try Option-Command-S; try Up and Down in the song list, Tab through the controls, and VoiceOver on the mode switcher and a toggle.
3. Edit, Stage and Screens without the transport bar: is the toolbar's LIVE chip enough?
4. Decide the Clear key hint and the red-free meters (plan defaults used).

## Open rows handed to UI-005b

T1, SB4, PL5, I13, I20, I21, Q3, Q5, K11 (L rows), and from this slice: C9, I19, the other modes' pickers, sliders and pop-ups, G12, I9, the time format, and the playlist's system List.
