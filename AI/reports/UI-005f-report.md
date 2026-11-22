# UI-005f report: Screens mode measured and closed against the mockup's rectangles

Feature ID UI-005f. Brief `AI/specs/UI-005-mode-geometry.md` (the fifth slice, same rules as the four in its table). Design `docs/UI/screens/03-screens-outputs.png` and `11-screens-outputs-light.png`, mockup `docs/UI/mockups/03-screens-outputs.html`, audit rows "Screens" in `AI/reports/UI-005-audit-screens-cues-looks.md`. Level: **Implemented**, measured in a debug build at 1440 x 900 on a throw-away library with the simulated card (dark and light). Not Hardware Verified, not Live-Service Verified. No model, schema or behaviour change.

## Tools

- `scripts/design-capture-screens.sh` (new): runs a built Debug app copy under a throw-away bundle id, temporary `--library`, `--silent-audio`, window outputs and the simulated card only, in the Screens state (`App/Sources/ScreensSnapshot.swift`, `UI_SNAPSHOT_SCREENS=1`): audience screen on SDI 3, stage screen on SDI 4, fill-and-key broadcast screen on SDI 1 + 2 selected, each with a typed "Connected to" label; pictures `screens-dark`, `screens-light` with rectangles, plus `screens-audience-dark`, `screens-stage-dark`, `screens-window-dark` (checked by eye, not mapped).
- `scripts/design-map-screens.json` (new): 178 design elements joined to app identifiers (`sc.*`), 23 of them the toolbar's entries copied from the Show map. Every other design element is covered by a rule with its reason (`--unmapped` lists 0 unexplained).
- `scripts/compare-rects-screens.py` (new, wraps `compare-rects.py` without editing it): renames the mockup's `.win.nobar` root and prints Screens regions: toolbar, list (left column), map (header bar, diagram, footer), form (selected screen's header and fields), stats, previews.
- Run: `scripts/design-rects docs/UI/mockups/03-screens-outputs.html d.json [--light]`, then `scripts/compare-rects-screens.py d.json <capture>.rects.json --all --bad --rects --unmapped`.

## Before and after (dark; the light capture gives the same counts, 147 of 178)

"Before" is the tree at 92d196a with only probe tags added to the views that existed (59 of the 178 elements could be tagged; the rest were not drawn: no Mac-node icon, no BNC rings, no destination nodes, no form fields at the design's places, and so on). "After" is this commit.

| Region | Mapped (before / after) | Within 1 pt before | Within 1 pt after |
|---|---|---|---|
| toolbar (shared bar, copied from the Show map) | 23 / 23 | 16 | 16 |
| list (left column) | 20 / 26 | 0 | 20 |
| map (header bar, diagram, footer) | 7 / 49 | 0 | 41 |
| form (selected screen) | 3 / 51 | 0 | 42 |
| stats | 3 / 16 | 0 | 16 |
| previews | 3 / 13 | 0 | 12 |
| total | 59 / 178 | 16 | 147 |

Without the toolbar (not this slice's file): 155 mapped, 131 within 1 pt after (0 of the 36 that could be measured before). A region is matched only where its row says all of its mapped elements are within 1 pt: **stats is matched**; list, map, form and previews are not (below).

Worst remaining, in points (app minus design; edges L T R B):
- toolbar (shared `ContentView`/`ToolbarTimersView`, same numbers as the Show report): timers capsule L -2.7, timer icon L -2.7 R -2.7, name L -2.7 R -1.8, value L -1.8.
- list: verify "Export log bundle" button L -0.8 R -1.7; Audience badge R -1.7; "Verification" R -1.7; Broadcast badge R -1.5; "SCREENS" R -1.0.
- map: header note L +3.4; connector titles R -2.4, -2.2, -2.1 ("SDI 4 · Confidence", "SDI 3 · Sanctuary", "SDI 1 · Fill"); plan switch L +1.9 (its first segment R +0.5); "Signal map" R +1.0.
- form: status pill L -3.2 R -5.9; Broadcast badge L -1.6 R -3.2; fill-alpha switch R -2.7 (second segment L -1.4 R -2.7, first R -1.4); title R -1.6; Stop output L +1.3; role switch R -1.1.
- previews: "SDI 1 · Fill" caption R -1.8.

Every one of these is a text width: SwiftUI sets the same Inter words 1 to 2 % narrower than the 1x browser render the mockup was measured from (bold and semibold words about 2 %, regular about 1 %), and the narrower word moves what follows it. All heights, tops, paddings, gaps and radii are within 1 pt; the cause of every earlier miss was fixed in layout, not by offsets (see below). I did not tune tracking to hide it; the 2x design picture is the reference and the side-by-side agrees by eye.

Pixel comparison, for reference only (tolerance 24; `scripts/compare-design.sh`): dark 42.7 % before, 11.7 % after; light 27.1 % before, 9.0 % after. What remains in the difference picture is text anti-aliasing, the slide plate inside the previews and thumbnails (UI-005h), the SIMULATED pills the design does not draw, the toolbar's live chip and title block (seeded content), and the fourth screen.

Pictures: `AI/reports/UI-005f-screens-dark.png`, `-dark-side.png` (design left, app right), `-dark-diff.png`, the same three for light, and `-screens-stage-dark.png`, `-screens-window-dark.png` (other states, by eye). All under 1 MB.

## What was wrong (causes)

- Column widths: left column 330 (design 299 plus a 1 pt border), map and form padded 14 not 12 / 14 in the right places, node widths 190, fixed 300 tiles.
- CSS line boxes: wrapped text in the design has 16 pt (12 pt text), 15 pt (map nodes) or 17 pt (the explanation) lines whatever the font; added `Text.screensLines` (line spacing plus half above and below, with SwiftUI's own rounded line height) for text that may wrap (screen names, destinations, verification text, node text).
- Fields, pop-ups, segmented controls, toggles, checkboxes were system controls: now `WFTextField`, `WFPopup`, `WFSegmented`, `.wfBare`, `.wfCheckbox`; the destination picker is a `WFPopup` menu (`DestinationPopup`).
- Rows: thumbnails 88 (96), top alignment (centred), selected outline, name 14 (13 bold), toggle at the card's edge (on the name line), role chip and destination at the design's offsets.
- Map: the Mac tile, one wire, column of tiles with a "Connected to" box: now the design's Mac node, 2 pt wires, role-coloured 46 pt tiles with BNC ring and role icon, and the destination node.
- Form: 2 columns at 28 gap, rows 32 high, label 96 right-aligned; Fill and key, Fill alpha and Look moved to the right column.
- Stats: padding 8 x 10 and 54.8 tall, bold mono 17, neutral colour (zeros in the status colour, non-zero in the warning colour, no longer cyan), thin grouping ("18 440").
- Previews: 270 wide (was about 230), captions with the role-coloured square, explanation 12/17.
- Probe subtleties found on the way: half-point paddings make the probe's whole-point origin round up (use whole points); inline boxes of the browser (14.1 pt title, 13 pt label, 2.3 pt below the line top) are tagged on a box of that size placed inside the 16 pt line.

## Rows the design draws that are left out (room kept)

| Design | Why not drawn | Status |
|---|---|---|
| Add screen (list header) | the model cannot add a screen (SC-03) | open, needs a feature slice |
| Remove screen (detail header) | no removeProfile (SC-40) | open, needs a feature slice |
| Identify screens (map header) | no overlay that labels every output (SC-21) | open, needs a feature slice |
| Thunderbolt PCIe enclosure node | the app cannot observe it and the model has nowhere to keep a typed label (SC-25) | open: needs a per-destination chain label in the model |
| SDI to HDMI converter nodes | same (SC-31) | open, same |
| Destination nodes (ATEM input, Projector, Stage monitor) | drawn from the one label the operator types ("Connected to"), marked "typed by you"; one label per screen, so the key tile shows the fill tile's label | drawn, partly: needs a label per connector |
| Pixel format as a choice (SC-45) | not in the model; the second control is read-only text "8-bit BGRA" (what the renderer composes) | open: choice needs the model and DeckLink conversion |
| Colour row (SC-46) | nothing truthful to say; its room holds "Connected to" (below) | open |
| Audio row (SC-47) | read-only text "No embedded audio" for an SDI destination; left out (room kept) for a display or window | open: embedded audio is a separate feature |
| If output fails as a choice (SC-53) | what the app does is stated, not chosen: read-only text "Keep the show running, show a warning here", the full sentence in its tooltip and accessibility label | open |
| Notes layer (SC-52) | speaker notes never reach an audience or broadcast screen | not to be built on those screens |
| Per-screen Look pop-up (SC-51) | the per-screen setting the app has is the theme inside the current Look (Looks switch every screen at once); the row is named "Theme". A real per-screen Look is a new feature | open, needs a feature slice |
| Mean schedule lead statistic (SC-63) and the Mac node's render time | not measured; the fifth tile shows "repeated" frames (SDI) and stays empty for a display | open |
| Calibration slide in the explanation (SC-68) | none exists; the app's own sentence ("with a test pattern") is kept | open |
| "HD only, no 4K" and "four 3G-SDI" in the footer | not reported by the device; the footer says what the card reports (its name, with its connector count) | open (only if a device reports a Duo 2) |
| The fourth screen (Lobby) | the capture has three screens and none can be added | follows Add screen |

Kept wording: the verification card keeps the app's more cautious sentence (SC-12), the header note and button labels follow the design.

## Where each extra went

- Open / Close screens: the toolbar button that already exists in `ContentView` (it floats right of the mode switcher); removed from the list header.
- SIMULATED: a small pill on the corner of each screen's thumbnail; a pill inside each connector tile before the role icon; the header badge ("SIMULATED", outline in the broadcast role colour) and a badge on the verification card's heading, both only while a device is simulated; the status pill says "Running (simulated)".
- The device block's caption ("Simulated SDI card (4 connectors)"): the footer text under the map. With more than one card, each card gets a caption line above its rows.
- Fill and key route lines "Connectors 1 and 2: fill on 1, key on 2 (reported by the card's simulator)": below the designed area (see next), with the card's name; the tile subtitle "paired with SDI 1" stays on the key tile.
- Unused connector: a tile with a muted ring ("SDI 3 · Unused").
- Displays and windows: tiles after the SDI rows, same style, with a display or window glyph in place of the ring; their typed label becomes the same destination node.
- Preset proposal (Apply / Cancel): under the footer when the plan switch is moved; the switch shows the chosen plan until Apply or Cancel; the plan the card is in shows when none is pending.
- Connected to (typed label): the form's fifth left-hand row, in the room of the design's Colour row; each mirror's label inside its mirror block.
- Mirrors: the Mirror row's content, above the "+ Add mirror" button; each mirror keeps its destination pop-up, keying controls, note, Remove and status line.
- Stage role: the Look row becomes "Stage layout" and the Layers row holds the sentence "Themes, Looks and props do not apply." with "Edit layouts…".
- Fault, hidden window, render error and "Left out of this screen": a block under the detail header, only while there is something to say.
- Verification: the level appears as the SIMULATED badge, or in the sentence for a real card ("not yet been checked on hardware"); the export result line sits under the sentence.
- Images that cannot be read, the SDI environment line, the profile notice, the route lines, the **Look list (new, rename, delete)**, **Props** (also in the Show inspector) and **Developer** (simulated card toggle, unplug and replug): one block below the designed area at the foot of the main column, one scroll away in the keyed state. Developer is unchanged here; the plan moves it to Settings in a later slice, `ShowInspector.swift` is not edited by this slice.
- Scroll bars of the main column are hidden: a legacy scroller took 17 pt of the designed 1140, and the content scrolls by wheel, trackpad and keys.

## Shared-file lines added

- `App/Sources/UISnapshotRun.swift`: one commented block (5 lines) before the design-capture block that runs `runScreensScenario` for `UI_SNAPSHOT_SCREENS`.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` is regenerated by `xcodegen` for the new files and is **not** in this commit (the check regenerates it).

Wanted in the shared files: `Text.screensLines` (CSS line box for wrapped text), `ScreensFormRow` (the form row), `ScreensReadOnlyField`, `ScreensBNC` and the typed-node chrome are defined in `ScreensComponents.swift` and could move to `Components.swift`; `CheckerboardView` and `ScenePreview` already shared. A `WFSegmented`/`WFPopup`/`PillTag` text-width gap of 1 to 2 % against the mockup is the cause of every remaining number above.

## Docs entries for the coordinator (verbatim)

Change log:
> UI-005f: Screens mode drawn to the mockup (left column 299, signal map with Mac node, role-coloured connector tiles with BNC ring, destination node from the operator's typed label, plan switch, two-column form with the design's pop-ups, toggle and segmented controls, counters, keyed previews at 270 wide). Left out with room kept: Add screen, Remove screen, Identify screens, enclosure and converter nodes, pixel-format and colour choices, Notes layer, per-screen Look, schedule-lead statistic. Look list, Props, Developer and warnings are below the designed area. New tools: `scripts/design-map-screens.json`, `scripts/compare-rects-screens.py`, `scripts/design-capture-screens.sh`. Implemented; 147 of 178 mapped elements within 1 pt (131 of 155 without the toolbar).

Known issues:
> KI (UI-005f): the design's per-screen Look pop-up is not built: Looks switch every screen at once, the per-screen row is the theme inside the current Look. A per-screen Look needs a model change.
> KI (UI-005f): the signal map cannot show the enclosure or converter: the model keeps one "Connected to" label per screen and mirror, not a chain per connector; the key tile repeats the fill tile's label.
> KI (UI-005f): screens cannot be added, removed or identified; there is no pixel-format, colour, embedded-audio or output-failure choice, and no schedule-lead statistic.
> KI (UI-005f): the Screens main column hides its scroll bar (to keep the designed 1140 pt); the Look list, Props and Developer are one scroll below the designed area.

Hands-on checklist:
> Screens: select each screen in the list and from its tile in the map; rename it, change its role and destination; switch Fill and key and Fill alpha; type a "Connected to" label and see "typed by you" in the map; choose a plan under the map and Apply or Cancel; Stop and Start output; add and remove a mirror; scroll to the bottom for the Look list, Props and Developer; check the SIMULATED marks appear only with the simulated card; dark and light.

## Checks

`WF_DERIVED_DATA=<own folder> ./scripts/check.sh`: first run exit 1 with 4 issues in timing-sensitive package tests while other agents were building (`ToolProcessRunnerTests.aClientThatHangsIsStopped`, `ScriptureLibraryTests.onlyTheNeededVersesAreReadFromTheLibrary`, `MIDIRouterTests` ordering); those suites alone: 36 tests in 3 suites passed. Second full run: **exit 0**, package tests 2720 in 423 suites passed, domain boundary, xcodegen and app build OK. The same tree built and captured (Debug) for every measurement above.

## Not verified

Hardware: nothing here touches a card; everything ran against the simulated card and window outputs. VoiceOver reading of the new tiles, destination nodes and pop-ups (labels were kept or written, not exercised with VoiceOver). Dragging and keyboard use of `WFSegmented` and `WFPopup` as used here (shared controls, exercised by Show). States other than the three roles and the window destination (a card unplugged, a fault, a hidden window, more than one card, a display destination with a long name, mirrors present, a screen whose card does not support keying). Window sizes other than 1440 x 900 (the three 270 pt previews and the 1140 pt grid are fixed as in the mockup, so a narrower window clips). The Screens rows in a library with many screens. No test was added: no pure layout logic with a testable contract was introduced.
